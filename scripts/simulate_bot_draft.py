"""Monte Carlo evaluation for Overforged's actual Lua bot draft module.

The staged strategy calls lv_bot_draft.lua through Lua 5.1 (lupa), rather
than reimplementing it in Python. With --oha-root, the report also loads OHA's
matchups_data.lua and aba_matchups.lua and builds a hypothetical late-pick
reference using OHA's published scoring formula. This is an evaluator only; it
does not launch Dota, change the addon, or modify the installed OHA scripts.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
import math
import os
from pathlib import Path
import random
import statistics
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "bin" / "lua-test-runtime"))

from kv_tools import read  # noqa: E402
from project_paths import BASELINE, GAME  # noqa: E402

try:
    from lupa.lua51 import LuaRuntime
except ImportError as exc:  # pragma: no cover - environment diagnostic
    raise SystemExit(
        "Lua simulation requires lupa's Lua 5.1 runtime; see tests/run_lua_tests.py."
    ) from exc


TOP_FUZZ_WEIGHTS = (35, 25, 20, 12, 8)
OHA_COMMIT = "cb814c6c8dc51ed08045d6efd9f4a48147992711"


def enabled_heroes() -> list[str]:
    roots = read(BASELINE / "scripts/npc/npc_heroes.txt")
    hero_root = next(value for key, value in roots if key == "DOTAHeroes")
    result = []
    for hero_name, values in hero_root:
        if not isinstance(values, list) or not hero_name.startswith("npc_dota_hero_"):
            continue
        fields = dict(values)
        if fields.get("Enabled") == "1" and int(fields.get("HeroID", "0")) > 0:
            result.append(hero_name)
    return sorted(set(result))


def lua_quote(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/").replace('"', '\\"')


def create_lua(seed: int, oha_root: Path | None = None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    vscripts = GAME / "scripts/vscripts"
    package_prefix = f'{lua_quote(vscripts)}/?.lua;'
    if oha_root is not None:
        matchups_path, _ = resolve_oha_files(oha_root)
        # lv_bot_draft requires bots/FretBots/... and bots/FunLib/... exactly as
        # the addon server VM does, so expose the directory above bots/.
        package_prefix += f'{lua_quote(matchups_path.parents[2])}/?.lua;'
    lua.execute(
        f'package.path = "{package_prefix}" .. package.path\n'
        f"math.randomseed({seed})\n"
        "RandomInt = function(minimum, maximum) return math.random(minimum, maximum) end"
    )
    return lua, lua.eval('require("lv_bot_draft")')


def resolve_oha_files(root: Path) -> tuple[Path, Path]:
    candidates = (root / "bots", root)
    for bots in candidates:
        matchups = bots / "FretBots/matchups_data.lua"
        synergy = bots / "FunLib/aba_matchups.lua"
        if matchups.is_file() and synergy.is_file():
            return matchups, synergy
    raise FileNotFoundError(
        f"{root} is neither an OHA repository root nor its bots directory"
    )


def load_oha_data(lua, root: Path):
    resolve_oha_files(root)
    matchups = lua.eval('require("bots/FretBots/matchups_data")')
    hero_matchups = lua.eval('require("bots/FunLib/aba_matchups")')
    return matchups, hero_matchups


def lua_list(lua, values):
    return lua.table_from(list(values))


def lua_set(lua, values):
    table = lua.table()
    for value in values:
        table[value] = True
    return table


def actual_lineup(lua, draft, heroes: list[str], enemies: list[str]) -> list[str]:
    used: set[str] = set()
    lineup = []
    weak_count = 0
    enabled = lua_list(lua, heroes)
    for position in range(1, 6):
        # Human pick N triggers bot pick N. Once the last human has picked, all
        # remaining bot positions see the complete human lineup.
        known_enemies = enemies[: min(position, len(enemies))]
        order = draft.GetCandidateOrder(
            enabled,
            lua_set(lua, used),
            position,
            weak_count,
            lua_list(lua, known_enemies),
            lua_list(lua, lineup),
        )
        hero = order[1]
        if hero is None:
            raise RuntimeError(f"no candidate for position {position}")
        lineup.append(hero)
        used.add(hero)
        if draft.IsWeakHero(hero):
            weak_count += 1
    return lineup


def fuzzy_choice(scored: list[tuple[float, str]], rng: random.Random) -> str:
    top = scored[: len(TOP_FUZZ_WEIGHTS)]
    weights = TOP_FUZZ_WEIGHTS[: len(top)]
    return rng.choices([hero for _, hero in top], weights=weights, k=1)[0]


def counter_component(matchups, candidate: str, enemies: list[str]) -> float:
    candidate_matchups = matchups[candidate]
    if candidate_matchups is None:
        return 0.0
    score = 0.0
    for enemy in enemies:
        advantage = candidate_matchups[enemy]
        if advantage is None:
            continue
        counter_score = -float(advantage)
        score += math.copysign(math.sqrt(abs(counter_score)), counter_score)
    return score


def candidate_oha_score(
    draft,
    matchups,
    hero_matchups,
    candidate: str,
    position: int,
    enemies: list[str],
    allies: list[str],
    weak_count: int,
) -> float:
    score = counter_component(matchups, candidate, enemies)
    for ally in allies:
        if candidate != ally and hero_matchups.IsSynergy(candidate, ally):
            score += 1.5
        if hero_matchups.IsCounter(ally, candidate):
            score -= 0.5
    score *= float(draft.GetPositionWeight(candidate, position)) / 100.0
    if draft.IsWeakHero(candidate):
        score *= 0.6**weak_count
    return score


def oha_reference_lineup(
    draft,
    heroes: list[str],
    enemies: list[str],
    matchups,
    hero_matchups,
    rng: random.Random,
) -> list[str]:
    """Apply OHA's score/top-five fuzz over our enabled positive-role pool.

    This intentionally does not claim to reproduce OHA's Bot Script VM timing,
    randomized role-pool construction, tag filters, chat commands, or modes.
    """
    lineup: list[str] = []
    weak_count = 0
    for position in range(1, 6):
        scored = []
        for hero in heroes:
            if hero in lineup or draft.GetPositionWeight(hero, position) <= 0:
                continue
            if weak_count >= 1 and draft.IsWeakHero(hero):
                continue
            score = candidate_oha_score(
                draft,
                matchups,
                hero_matchups,
                hero,
                position,
                enemies,
                lineup,
                weak_count,
            )
            scored.append((score, hero))
        scored.sort(key=lambda item: (-item[0], item[1]))
        if not scored:
            raise RuntimeError(f"OHA reference has no candidate for position {position}")
        selected = fuzzy_choice(scored, rng)
        lineup.append(selected)
        if draft.IsWeakHero(selected):
            weak_count += 1
    return lineup


@dataclass
class Metrics:
    name: str
    position_weights: list[list[float]] = field(default_factory=lambda: [[] for _ in range(5)])
    lineup_role_totals: list[float] = field(default_factory=list)
    weak_counts: Counter = field(default_factory=Counter)
    picks: list[Counter] = field(default_factory=lambda: [Counter() for _ in range(5)])
    lineups: Counter = field(default_factory=Counter)
    duplicate_violations: int = 0
    zero_role_picks: int = 0
    oha_scores: list[float] = field(default_factory=list)
    synergy_scores: list[float] = field(default_factory=list)
    counter_scores: list[float] = field(default_factory=list)

    def add(self, lineup, draft, enemies=None, matchups=None, hero_matchups=None):
        self.lineups[tuple(lineup)] += 1
        if len(set(lineup)) != len(lineup):
            self.duplicate_violations += 1
        weak_count = sum(bool(draft.IsWeakHero(hero)) for hero in lineup)
        self.weak_counts[weak_count] += 1
        role_total = 0.0
        for index, hero in enumerate(lineup):
            weight = float(draft.GetPositionWeight(hero, index + 1))
            self.position_weights[index].append(weight)
            self.picks[index][hero] += 1
            role_total += weight
            if weight <= 0:
                self.zero_role_picks += 1
        self.lineup_role_totals.append(role_total)

        if matchups is None or hero_matchups is None or enemies is None:
            return
        total_score = 0.0
        raw_counter = 0.0
        raw_synergy = 0.0
        prior_allies: list[str] = []
        prior_weak = 0
        for position, hero in enumerate(lineup, 1):
            raw_counter += counter_component(matchups, hero, enemies)
            for ally in prior_allies:
                if hero_matchups.IsSynergy(hero, ally):
                    raw_synergy += 1.5
                if hero_matchups.IsCounter(ally, hero):
                    raw_synergy -= 0.5
            total_score += candidate_oha_score(
                draft,
                matchups,
                hero_matchups,
                hero,
                position,
                enemies,
                prior_allies,
                prior_weak,
            )
            prior_allies.append(hero)
            if draft.IsWeakHero(hero):
                prior_weak += 1
        self.oha_scores.append(total_score)
        self.synergy_scores.append(raw_synergy)
        self.counter_scores.append(raw_counter)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int((len(ordered) - 1) * fraction)))
    return ordered[index]


def print_metrics(metrics: Metrics, rounds: int, top: int, with_oha: bool):
    print(f"\n[{metrics.name}]")
    print(
        "role total (max scale 500): "
        f"mean={statistics.fmean(metrics.lineup_role_totals):.2f}, "
        f"p10={percentile(metrics.lineup_role_totals, 0.10):.2f}, "
        f"median={statistics.median(metrics.lineup_role_totals):.2f}"
    )
    print(
        "position mean weights: "
        + ", ".join(
            f"P{position}={statistics.fmean(values):.2f}"
            for position, values in enumerate(metrics.position_weights, 1)
        )
    )
    weak_violations = sum(count for weak, count in metrics.weak_counts.items() if weak > 1)
    print(
        f"unique lineups={len(metrics.lineups)}/{rounds}, "
        f"duplicate violations={metrics.duplicate_violations}, "
        f"weak-cap violations={weak_violations}, zero-role picks={metrics.zero_role_picks}"
    )
    max_lineup_count = metrics.lineups.most_common(1)[0][1]
    position_peaks = [counts.most_common(1)[0][1] / rounds for counts in metrics.picks]
    print(
        f"most-common exact lineup={max_lineup_count / rounds:.2%}, "
        "position peak shares="
        + ", ".join(
            f"P{position}={share:.2%}"
            for position, share in enumerate(position_peaks, 1)
        )
    )
    if with_oha:
        print(
            f"OHA post-hoc total score mean={statistics.fmean(metrics.oha_scores):.4f}, "
            f"raw counter mean={statistics.fmean(metrics.counter_scores):.4f}, "
            f"ally synergy mean={statistics.fmean(metrics.synergy_scores):.4f}"
        )
    for position, counts in enumerate(metrics.picks, 1):
        common = ", ".join(
            f"{hero.removeprefix('npc_dota_hero_')}={count}"
            for hero, count in counts.most_common(top)
        )
        print(f"P{position} top {top}: {common}")


def random_lineup(heroes: list[str], rng: random.Random) -> list[str]:
    return rng.sample(heroes, 5)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=20260904)
    parser.add_argument("--enemy-size", type=int, default=1)
    parser.add_argument(
        "--fixed-enemy",
        action="append",
        default=[],
        help="fixed enemy hero for repeat-play concentration checks; may be repeated",
    )
    parser.add_argument("--top", type=int, default=5)
    parser.add_argument(
        "--oha-root",
        type=Path,
        default=Path(os.environ["OHA_ROOT"]) if "OHA_ROOT" in os.environ else None,
        help="OHA repository root or its bots directory; enables full score comparison",
    )
    args = parser.parse_args()
    if args.rounds <= 0 or not 1 <= args.enemy_size <= 5 or args.top <= 0:
        parser.error("rounds/top must be positive and enemy-size must be 1..5")
    if len(args.fixed_enemy) > 5:
        parser.error("fixed-enemy may be supplied at most five times")
    return args


def main():
    args = parse_args()
    heroes = enabled_heroes()
    if len(heroes) < 10:
        raise SystemExit(f"only {len(heroes)} enabled heroes were parsed")
    fixed_enemies = [
        name if name.startswith("npc_dota_hero_") else f"npc_dota_hero_{name}"
        for name in args.fixed_enemy
    ]
    unknown_fixed = sorted(set(fixed_enemies) - set(heroes))
    if unknown_fixed:
        raise SystemExit("fixed enemy is not enabled: " + ", ".join(unknown_fixed))
    lua, draft = create_lua(args.seed, args.oha_root)
    matchups = hero_matchups = None
    if args.oha_root is not None:
        matchups, hero_matchups = load_oha_data(lua, args.oha_root)
        if not draft.HasOhaScoring():
            raise SystemExit("lv_bot_draft did not load the supplied OHA scoring modules")

    rng = random.Random(args.seed)
    actual = Metrics("Overforged staged Lua draft")
    baseline = Metrics("Uniform-random no-repeat baseline")
    reference = Metrics("OHA late-score reference") if matchups is not None else None

    for _ in range(args.rounds):
        enemies = fixed_enemies or rng.sample(heroes, args.enemy_size)
        actual_pick = actual_lineup(lua, draft, heroes, enemies)
        baseline_pick = random_lineup(heroes, rng)
        actual.add(actual_pick, draft, enemies, matchups, hero_matchups)
        baseline.add(baseline_pick, draft, enemies, matchups, hero_matchups)
        if reference is not None:
            reference_pick = oha_reference_lineup(
                draft, heroes, enemies, matchups, hero_matchups, rng
            )
            reference.add(reference_pick, draft, enemies, matchups, hero_matchups)

    print("Overforged bot draft Monte Carlo")
    print(
        f"rounds={args.rounds}, seed={args.seed}, enabled heroes={len(heroes)}, "
        f"simulated known enemies={len(fixed_enemies) or args.enemy_size}"
    )
    if fixed_enemies:
        print("fixed enemies=" + ", ".join(fixed_enemies))
    print(f"actual selector=game/dota_addons/overforged/scripts/vscripts/lv_bot_draft.lua")
    if matchups is None:
        print("OHA data=not supplied; role/duplicate/weak/diversity evaluation only")
    else:
        print(f"OHA evaluator={args.oha_root} (expected source commit {OHA_COMMIT})")
        print(
            "Reference scope: OHA counter/synergy/role/weak scoring + top-five fuzz; "
            "not the Bot VM timing or randomized/tag-filtered role-pool builder."
        )

    print_metrics(actual, args.rounds, args.top, matchups is not None)
    print_metrics(baseline, args.rounds, args.top, matchups is not None)
    if reference is not None:
        print_metrics(reference, args.rounds, args.top, True)

    baseline_role = statistics.fmean(baseline.lineup_role_totals)
    actual_role = statistics.fmean(actual.lineup_role_totals)
    print("\n[Comparison]")
    print(
        f"Overforged role-fit improvement vs random: "
        f"{actual_role - baseline_role:+.2f} ({(actual_role / baseline_role - 1) * 100:+.2f}%)"
    )
    if reference is not None:
        print(
            "Overforged receives enemy picks incrementally; the OHA reference sees the "
            "same complete enemy lineup for all five bot slots."
        )

    failures = []
    actual_weak_violations = sum(
        count for weak, count in actual.weak_counts.items() if weak > 1
    )
    if actual.duplicate_violations:
        failures.append(f"{actual.duplicate_violations} duplicate lineups")
    if actual_weak_violations:
        failures.append(f"{actual_weak_violations} weak-cap violations")
    if actual.zero_role_picks:
        failures.append(f"{actual.zero_role_picks} zero-role picks")
    if actual_role <= baseline_role:
        failures.append("mean role fit did not beat uniform random")
    for position, counts in enumerate(actual.picks, 1):
        peak_share = counts.most_common(1)[0][1] / args.rounds
        if peak_share > 0.35:
            failures.append(f"position {position} peak hero share exceeded 35%")
    max_lineup_share = actual.lineups.most_common(1)[0][1] / args.rounds
    if max_lineup_share > 0.05:
        failures.append("one exact lineup exceeded 5% of all rounds")
    if failures:
        print("QUALITY GATE: FAIL - " + "; ".join(failures))
        raise SystemExit(1)
    print("QUALITY GATE: PASS")


if __name__ == "__main__":
    main()
