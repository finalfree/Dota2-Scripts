package.path = "game/dota_addons/overforged/scripts/vscripts/?.lua;" .. package.path

package.preload["bots/FretBots/matchups_data"] = function()
    return {
        npc_dota_hero_antimage = {npc_dota_hero_axe = 9},
        npc_dota_hero_juggernaut = {npc_dota_hero_axe = -9},
    }
end
package.preload["bots/FunLib/aba_matchups"] = function()
    return {
        IsSynergy = function(candidate, ally)
            return candidate == "npc_dota_hero_juggernaut"
                and ally == "npc_dota_hero_crystal_maiden"
        end,
        IsCounter = function() return false end,
    }
end

RandomInt = function(minimum, maximum)
    assert(minimum == 1 and maximum >= minimum)
    return minimum
end

local Draft = require("lv_bot_draft")
assert(Draft.HasOhaScoring())
assert(Draft.GetOhaScoringStatus() == "matchups=loaded synergy=loaded")
local enabled = {
    "npc_dota_hero_antimage",
    "npc_dota_hero_nevermore",
    "npc_dota_hero_axe",
    "npc_dota_hero_earth_spirit",
    "npc_dota_hero_crystal_maiden",
}
local expected = {
    "npc_dota_hero_antimage",
    "npc_dota_hero_nevermore",
    "npc_dota_hero_axe",
    "npc_dota_hero_earth_spirit",
    "npc_dota_hero_crystal_maiden",
}

local used = {}
for position = 1, 5 do
    local order = Draft.GetCandidateOrder(enabled, used, position, 0)
    assert(order[1] == expected[position], "position " .. position .. " should prefer its specialist")
    assert(Draft.GetPositionWeight(order[1], position) > 0)
    used[order[1]] = true
end
print("PASS: draft produces a unique position-1-through-5 lineup")

local order = Draft.GetCandidateOrder({
    "npc_dota_hero_puck",
    "npc_dota_hero_juggernaut",
}, {}, 2, 1)
assert(order[1] == "npc_dota_hero_juggernaut")
assert(order[#order] == "npc_dota_hero_puck", "weak hero is held back after the per-team cap")
assert(Draft.CountWeakHeroes({npc_dota_hero_puck = true}) == 1)
print("PASS: weak-hero cap affects normal ordering without making team fill impossible")

order = Draft.GetCandidateOrder({
    "npc_dota_hero_antimage",
    "npc_dota_hero_future_unknown",
}, {npc_dota_hero_antimage = true}, 5, 0)
assert(order[1] == "npc_dota_hero_future_unknown",
    "unknown future heroes remain available as an emergency fallback")
print("PASS: unknown future heroes remain safe fallback candidates")

order = Draft.GetCandidateOrder({
    "npc_dota_hero_antimage",
    "npc_dota_hero_juggernaut",
}, {}, 1, 0, {npc_dota_hero_axe = true}, {})
assert(order[1] == "npc_dota_hero_juggernaut",
    "OHA matchup data should make the stronger counter answer first")
print("PASS: known human picks activate OHA counter scoring")

order = Draft.GetCandidateOrder({
    "npc_dota_hero_antimage",
    "npc_dota_hero_juggernaut",
}, {}, 1, 0, {npc_dota_hero_lina = true}, {
    npc_dota_hero_crystal_maiden = true,
})
assert(order[1] == "npc_dota_hero_juggernaut",
    "previous bot picks should contribute OHA synergy scoring")
print("PASS: prior bot picks activate OHA ally-synergy scoring")

local rankRollMaximum = nil
RandomInt = function(minimum, maximum)
    if minimum == 1 and maximum == 100 then rankRollMaximum = maximum end
    return minimum
end
Draft.GetCandidateOrder({
    "npc_dota_hero_antimage", "npc_dota_hero_slark",
    "npc_dota_hero_terrorblade", "npc_dota_hero_troll_warlord",
    "npc_dota_hero_juggernaut", "npc_dota_hero_furion",
    "npc_dota_hero_lina", "npc_dota_hero_luna",
    "npc_dota_hero_drow_ranger", "npc_dota_hero_phantom_assassin",
    "npc_dota_hero_spectre", "npc_dota_hero_sven",
    "npc_dota_hero_chaos_knight", "npc_dota_hero_riki",
    "npc_dota_hero_ursa",
    "npc_dota_hero_alchemist", "npc_dota_hero_bloodseeker",
    "npc_dota_hero_bristleback", "npc_dota_hero_clinkz",
    "npc_dota_hero_dragon_knight", "npc_dota_hero_faceless_void",
    "npc_dota_hero_gyrocopter", "npc_dota_hero_huskar",
    "npc_dota_hero_medusa", "npc_dota_hero_monkey_king",
    "npc_dota_hero_naga_siren", "npc_dota_hero_nevermore",
    "npc_dota_hero_phantom_lancer", "npc_dota_hero_razor",
    "npc_dota_hero_sniper",
}, {}, 1, 0)
assert(rankRollMaximum == 100, "the broadened 30-candidate rank lottery should total 100")
print("PASS: final rank lottery covers thirty viable heroes")
