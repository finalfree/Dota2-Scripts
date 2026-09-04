-- Role weights are adapted from OpenHyperAI's aba_hero_pos_weights.ts at
-- commit cb814c6c8dc51ed08045d6efd9f4a48147992711 (MIT License).
-- See the addon's THIRD_PARTY_NOTICES.txt for attribution and license text.
--
-- This module deliberately contains only server-Lua-safe draft policy. OHA's
-- hero_selection.lua runs in the separate Bot Script VM and cannot be called
-- directly from addon_game_mode.lua.

local Draft = {}

-- These two OHA modules are pure data/helpers and can also be loaded from the
-- host's existing Local Dev Script installation in the server Lua VM. Keep the
-- position-only selector as a safe fallback for Workshop hosts without OHA.
local matchupOK, matchupResult = pcall(require, "bots/FretBots/matchups_data")
local MATCHUPS = matchupOK and type(matchupResult) == "table" and matchupResult or nil
local MATCHUP_STATUS = MATCHUPS ~= nil and "loaded"
    or (matchupOK and ("returned " .. type(matchupResult)) or tostring(matchupResult))
local synergyOK, synergyResult = pcall(require, "bots/FunLib/aba_matchups")
local HERO_MATCHUPS = synergyOK and type(synergyResult) == "table" and synergyResult or nil
local SYNERGY_STATUS = HERO_MATCHUPS ~= nil and "loaded"
    or (synergyOK and ("returned " .. type(synergyResult)) or tostring(synergyResult))

local POSITION_WEIGHTS = {
    ["npc_dota_hero_abaddon"] = {25, 5, 30, 20, 50},
    ["npc_dota_hero_abyssal_underlord"] = {5, 20, 80, 5, 0},
    ["npc_dota_hero_alchemist"] = {50, 30, 15, 5, 0},
    ["npc_dota_hero_ancient_apparition"] = {5, 25, 10, 30, 50},
    ["npc_dota_hero_antimage"] = {90, 5, 5, 0, 0},
    ["npc_dota_hero_arc_warden"] = {30, 60, 5, 5, 0},
    ["npc_dota_hero_axe"] = {30, 5, 80, 5, 0},
    ["npc_dota_hero_bane"] = {0, 20, 10, 30, 40},
    ["npc_dota_hero_batrider"] = {5, 60, 30, 5, 0},
    ["npc_dota_hero_beastmaster"] = {5, 35, 65, 35, 0},
    ["npc_dota_hero_bloodseeker"] = {45, 40, 35, 0, 0},
    ["npc_dota_hero_bounty_hunter"] = {0, 45, 30, 50, 35},
    ["npc_dota_hero_brewmaster"] = {5, 15, 85, 5, 0},
    ["npc_dota_hero_bristleback"] = {30, 40, 60, 0, 0},
    ["npc_dota_hero_broodmother"] = {15, 60, 30, 5, 0},
    ["npc_dota_hero_centaur"] = {5, 5, 85, 5, 0},
    ["npc_dota_hero_chaos_knight"] = {55, 40, 25, 0, 0},
    ["npc_dota_hero_chen"] = {0, 5, 10, 15, 20},
    ["npc_dota_hero_clinkz"] = {40, 45, 5, 10, 0},
    ["npc_dota_hero_crystal_maiden"] = {0, 5, 10, 30, 55},
    ["npc_dota_hero_dark_seer"] = {5, 5, 80, 10, 0},
    ["npc_dota_hero_dark_willow"] = {0, 20, 10, 30, 25},
    ["npc_dota_hero_dawnbreaker"] = {5, 20, 75, 10, 0},
    ["npc_dota_hero_dazzle"] = {0, 45, 10, 30, 55},
    ["npc_dota_hero_death_prophet"] = {5, 60, 40, 5, 0},
    ["npc_dota_hero_disruptor"] = {0, 5, 10, 30, 55},
    ["npc_dota_hero_doom_bringer"] = {15, 25, 85, 5, 0},
    ["npc_dota_hero_dragon_knight"] = {55, 70, 35, 10, 0},
    ["npc_dota_hero_drow_ranger"] = {70, 35, 5, 0, 0},
    ["npc_dota_hero_earth_spirit"] = {0, 5, 30, 70, 15},
    ["npc_dota_hero_earthshaker"] = {0, 5, 35, 70, 15},
    ["npc_dota_hero_elder_titan"] = {0, 5, 20, 30, 15},
    ["npc_dota_hero_ember_spirit"] = {15, 70, 15, 0, 0},
    ["npc_dota_hero_enchantress"] = {0, 5, 20, 35, 50},
    ["npc_dota_hero_enigma"] = {0, 35, 65, 30, 0},
    ["npc_dota_hero_faceless_void"] = {60, 0, 25, 5, 0},
    ["npc_dota_hero_furion"] = {75, 25, 80, 60, 0},
    ["npc_dota_hero_grimstroke"] = {0, 5, 10, 35, 50},
    ["npc_dota_hero_gyrocopter"] = {60, 5, 25, 20, 10},
    ["npc_dota_hero_hoodwink"] = {0, 5, 10, 25, 20},
    ["npc_dota_hero_huskar"] = {35, 50, 35, 0, 0},
    ["npc_dota_hero_invoker"] = {30, 70, 10, 30, 0},
    ["npc_dota_hero_jakiro"] = {0, 35, 30, 60, 65},
    ["npc_dota_hero_juggernaut"] = {80, 15, 15, 0, 0},
    ["npc_dota_hero_keeper_of_the_light"] = {0, 15, 10, 25, 25},
    ["npc_dota_hero_kunkka"] = {35, 85, 35, 5, 0},
    ["npc_dota_hero_legion_commander"] = {5, 35, 65, 5, 0},
    ["npc_dota_hero_leshrac"] = {15, 30, 25, 25, 20},
    ["npc_dota_hero_lich"] = {10, 35, 20, 80, 80},
    ["npc_dota_hero_life_stealer"] = {20, 0, 20, 0, 0},
    ["npc_dota_hero_lina"] = {75, 70, 5, 66, 30},
    ["npc_dota_hero_lion"] = {30, 45, 10, 30, 45},
    ["npc_dota_hero_lone_druid"] = {20, 25, 15, 0, 0},
    ["npc_dota_hero_luna"] = {70, 5, 15, 0, 0},
    ["npc_dota_hero_lycan"] = {45, 45, 45, 5, 0},
    ["npc_dota_hero_magnataur"] = {5, 15, 85, 5, 0},
    ["npc_dota_hero_marci"] = {0, 5, 20, 20, 15},
    ["npc_dota_hero_mars"] = {5, 55, 55, 5, 0},
    ["npc_dota_hero_medusa"] = {50, 65, 5, 0, 0},
    ["npc_dota_hero_meepo"] = {20, 20, 5, 0, 0},
    ["npc_dota_hero_mirana"] = {10, 65, 10, 65, 20},
    ["npc_dota_hero_monkey_king"] = {50, 35, 45, 0, 0},
    ["npc_dota_hero_morphling"] = {20, 15, 5, 0, 0},
    ["npc_dota_hero_muerta"] = {35, 5, 5, 15, 5},
    ["npc_dota_hero_naga_siren"] = {45, 25, 20, 10, 0},
    ["npc_dota_hero_necrolyte"] = {5, 60, 30, 5, 0},
    ["npc_dota_hero_nevermore"] = {45, 80, 5, 0, 0},
    ["npc_dota_hero_night_stalker"] = {25, 35, 55, 25, 0},
    ["npc_dota_hero_nyx_assassin"] = {0, 5, 40, 65, 20},
    ["npc_dota_hero_ringmaster"] = {5, 20, 5, 50, 20},
    ["npc_dota_hero_obsidian_destroyer"] = {5, 90, 5, 0, 0},
    ["npc_dota_hero_ogre_magi"] = {20, 55, 40, 40, 45},
    ["npc_dota_hero_omniknight"] = {40, 5, 50, 30, 55},
    ["npc_dota_hero_oracle"] = {0, 35, 10, 30, 45},
    ["npc_dota_hero_pangolier"] = {5, 25, 15, 5, 0},
    ["npc_dota_hero_phantom_assassin"] = {70, 25, 5, 0, 0},
    ["npc_dota_hero_phantom_lancer"] = {50, 45, 5, 0, 0},
    ["npc_dota_hero_phoenix"] = {0, 35, 30, 65, 20},
    ["npc_dota_hero_primal_beast"] = {5, 5, 25, 5, 0},
    ["npc_dota_hero_puck"] = {5, 70, 25, 10, 10},
    ["npc_dota_hero_pudge"] = {5, 35, 50, 25, 5},
    ["npc_dota_hero_pugna"] = {0, 35, 20, 65, 20},
    ["npc_dota_hero_queenofpain"] = {25, 50, 25, 20, 0},
    ["npc_dota_hero_rattletrap"] = {5, 5, 55, 35, 10},
    ["npc_dota_hero_razor"] = {5, 85, 5, 5, 0},
    ["npc_dota_hero_riki"] = {55, 10, 20, 15, 10},
    ["npc_dota_hero_rubick"] = {0, 35, 20, 40, 45},
    ["npc_dota_hero_sand_king"] = {5, 35, 65, 25, 0},
    ["npc_dota_hero_shadow_demon"] = {0, 15, 10, 30, 55},
    ["npc_dota_hero_shadow_shaman"] = {0, 20, 20, 45, 55},
    ["npc_dota_hero_shredder"] = {5, 25, 65, 5, 0},
    ["npc_dota_hero_silencer"] = {10, 55, 10, 30, 35},
    ["npc_dota_hero_skeleton_king"] = {50, 5, 45, 0, 0},
    ["npc_dota_hero_skywrath_mage"] = {0, 45, 10, 65, 20},
    ["npc_dota_hero_slardar"] = {35, 5, 55, 5, 0},
    ["npc_dota_hero_slark"] = {90, 5, 5, 0, 0},
    ["npc_dota_hero_snapfire"] = {20, 35, 30, 60, 15},
    ["npc_dota_hero_sniper"] = {70, 65, 5, 0, 0},
    ["npc_dota_hero_spectre"] = {70, 5, 5, 0, 0},
    ["npc_dota_hero_spirit_breaker"] = {0, 5, 20, 20, 15},
    ["npc_dota_hero_storm_spirit"] = {25, 30, 5, 0, 0},
    ["npc_dota_hero_sven"] = {60, 5, 35, 0, 0},
    ["npc_dota_hero_techies"] = {10, 35, 20, 40, 15},
    ["npc_dota_hero_templar_assassin"] = {5, 90, 5, 0, 0},
    ["npc_dota_hero_terrorblade"] = {90, 5, 5, 0, 0},
    ["npc_dota_hero_tidehunter"] = {25, 25, 45, 5, 0},
    ["npc_dota_hero_tinker"] = {5, 15, 5, 20, 0},
    ["npc_dota_hero_tiny"] = {5, 25, 65, 5, 0},
    ["npc_dota_hero_treant"] = {0, 5, 10, 30, 55},
    ["npc_dota_hero_troll_warlord"] = {90, 5, 25, 0, 0},
    ["npc_dota_hero_tusk"] = {0, 20, 35, 40, 15},
    ["npc_dota_hero_undying"] = {0, 5, 30, 30, 55},
    ["npc_dota_hero_ursa"] = {50, 25, 25, 0, 0},
    ["npc_dota_hero_vengefulspirit"] = {0, 5, 10, 30, 55},
    ["npc_dota_hero_venomancer"] = {35, 55, 45, 35, 30},
    ["npc_dota_hero_viper"] = {45, 65, 45, 5, 0},
    ["npc_dota_hero_visage"] = {5, 15, 25, 5, 0},
    ["npc_dota_hero_void_spirit"] = {15, 30, 15, 0, 0},
    ["npc_dota_hero_warlock"] = {0, 35, 0, 70, 70},
    ["npc_dota_hero_weaver"] = {35, 15, 10, 45, 15},
    ["npc_dota_hero_windrunner"] = {5, 45, 45, 5, 0},
    ["npc_dota_hero_winter_wyvern"] = {0, 35, 10, 20, 25},
    ["npc_dota_hero_wisp"] = {0, 5, 10, 25, 20},
    ["npc_dota_hero_witch_doctor"] = {0, 5, 10, 35, 55},
    ["npc_dota_hero_zuus"] = {25, 60, 15, 40, 20},
    ["npc_dota_hero_kez"] = {50, 40, 5, 0, 0},
    ["npc_dota_hero_largo"] = {0, 5, 0, 40, 40},
}

local WEAK_HEROES = {
    npc_dota_hero_chen = true,
    npc_dota_hero_ancient_apparition = true,
    npc_dota_hero_tinker = true,
    npc_dota_hero_pangolier = true,
    npc_dota_hero_tusk = true,
    npc_dota_hero_morphling = true,
    npc_dota_hero_visage = true,
    npc_dota_hero_void_spirit = true,
    npc_dota_hero_ember_spirit = true,
    npc_dota_hero_rubick = true,
    npc_dota_hero_brewmaster = true,
    npc_dota_hero_puck = true,
    npc_dota_hero_marci = true,
    npc_dota_hero_lone_druid = true,
    npc_dota_hero_primal_beast = true,
    npc_dota_hero_dark_willow = true,
    npc_dota_hero_hoodwink = true,
    npc_dota_hero_wisp = true,
}

-- OHA selects only among the best five (35/25/20/12/8). Overforged prioritizes
-- replay variety instead: score enough heroes to reject bad role fits, then
-- draw broadly from the best 30. The best five together account for 30%,
-- preserving a moderate counter/synergy preference while the other 25 heroes
-- retain 70% of the probability.
local RANK_FUZZ_WEIGHTS = {
    7, 6, 6, 6, 5,
    4, 4, 4, 4, 4,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
}
local WEAK_HERO_CAP = 1
local RANDOM_SCORE_JITTER = 30

local function Roll(minimum, maximum)
    if RandomInt ~= nil then return RandomInt(minimum, maximum) end
    return math.random(minimum, maximum)
end

local function Shuffle(values)
    for i = #values, 2, -1 do
        local j = Roll(1, i)
        values[i], values[j] = values[j], values[i]
    end
end

function Draft.IsWeakHero(heroName)
    return WEAK_HEROES[heroName] == true
end

function Draft.GetPositionWeight(heroName, position)
    local weights = POSITION_WEIGHTS[heroName]
    if weights == nil or position == nil then return 0 end
    return tonumber(weights[position]) or 0
end

function Draft.CountWeakHeroes(heroNames)
    local count = 0
    for key, value in pairs(heroNames or {}) do
        local heroName = type(key) == "number" and value or key
        local selected = type(key) == "number" or value == true
        if selected and Draft.IsWeakHero(heroName) then count = count + 1 end
    end
    return count
end

function Draft.HasOhaScoring()
    return MATCHUPS ~= nil and HERO_MATCHUPS ~= nil
end

function Draft.GetOhaScoringStatus()
    if Draft.HasOhaScoring() then return "matchups=loaded synergy=loaded" end
    return "matchups=" .. MATCHUP_STATUS .. " synergy=" .. SYNERGY_STATUS
end

local function HeroNames(values)
    local names = {}
    for key, value in pairs(values or {}) do
        local heroName = type(key) == "number" and value or key
        local selected = type(key) == "number" or value == true
        if selected and type(heroName) == "string" then table.insert(names, heroName) end
    end
    return names
end

local function CounterScore(candidate, enemyHeroes)
    if MATCHUPS == nil or MATCHUPS[candidate] == nil then return 0 end
    local score = 0
    for _, enemy in ipairs(HeroNames(enemyHeroes)) do
        local advantage = MATCHUPS[candidate][enemy]
        if advantage ~= nil then
            local counter = -1 * advantage
            if counter >= 0 then
                score = score + math.sqrt(counter)
            else
                score = score - math.sqrt(math.abs(counter))
            end
        end
    end
    return score
end

local function OhaScore(candidate, roleWeight, enemyHeroes, allyHeroes, weakHeroCount)
    local score = CounterScore(candidate, enemyHeroes)
    for _, ally in ipairs(HeroNames(allyHeroes)) do
        if ally ~= candidate then
            if HERO_MATCHUPS.IsSynergy ~= nil
                and HERO_MATCHUPS.IsSynergy(candidate, ally) then
                score = score + 1.5
            end
            if HERO_MATCHUPS.IsCounter ~= nil
                and HERO_MATCHUPS.IsCounter(ally, candidate) then
                score = score - 0.5
            end
        end
    end
    score = score * (roleWeight / 100)
    if Draft.IsWeakHero(candidate) then score = score * (0.6 ^ weakHeroCount) end
    return score
end

local function SelectFuzzyTopIndex(scored)
    local topCount = math.min(#scored, #RANK_FUZZ_WEIGHTS)
    if topCount == 0 then return nil end
    local total = 0
    for i = 1, topCount do total = total + RANK_FUZZ_WEIGHTS[i] end
    local roll = Roll(1, total)
    local cumulative = 0
    for i = 1, topCount do
        cumulative = cumulative + RANK_FUZZ_WEIGHTS[i]
        if roll <= cumulative then return i end
    end
    return 1
end

-- Return candidates in retry order for one OHA-style slot/position. The first
-- candidate is selected from a broadened best-30 rank lottery. OHA's matchup,
-- synergy and role inputs still decide the ranking; only final variety differs.
-- When selected human heroes and the host's OHA data are available, the score
-- also includes OHA counter and ally-synergy terms. Otherwise position jitter
-- preserves variety and keeps Workshop-only hosts functional.
function Draft.GetCandidateOrder(
    enabledHeroes, usedHeroes, position, weakHeroCount, enemyHeroes, allyHeroes)
    position = math.max(1, math.min(5, tonumber(position) or 1))
    weakHeroCount = tonumber(weakHeroCount) or 0
    usedHeroes = usedHeroes or {}

    local scored = {}
    local emergency = {}
    local blockedWeak = {}
    local seen = {}
    local useOhaScoring = Draft.HasOhaScoring() and #HeroNames(enemyHeroes) > 0
    for _, heroName in ipairs(enabledHeroes or {}) do
        if type(heroName) == "string" and not seen[heroName] and not usedHeroes[heroName] then
            seen[heroName] = true
            local isWeak = Draft.IsWeakHero(heroName)
            if isWeak and weakHeroCount >= WEAK_HERO_CAP then
                table.insert(blockedWeak, heroName)
            else
                local roleWeight = Draft.GetPositionWeight(heroName, position)
                if roleWeight > 0 then
                    local score
                    if useOhaScoring then
                        score = OhaScore(
                            heroName, roleWeight, enemyHeroes, allyHeroes, weakHeroCount)
                    else
                        score = roleWeight + Roll(1, RANDOM_SCORE_JITTER + 1) - 1
                        if isWeak then score = score * (0.6 ^ weakHeroCount) end
                    end
                    table.insert(scored, {name = heroName, score = score})
                else
                    -- Unknown/new heroes and zero-weight roles remain last-resort
                    -- options so a Dota patch cannot prevent the team from filling.
                    table.insert(emergency, heroName)
                end
            end
        end
    end

    table.sort(scored, function(a, b)
        if a.score == b.score then return a.name < b.name end
        return a.score > b.score
    end)

    local order = {}
    local selectedIndex = SelectFuzzyTopIndex(scored)
    if selectedIndex ~= nil then table.insert(order, scored[selectedIndex].name) end
    for index, candidate in ipairs(scored) do
        if index ~= selectedIndex then table.insert(order, candidate.name) end
    end
    Shuffle(emergency)
    Shuffle(blockedWeak)
    for _, heroName in ipairs(emergency) do table.insert(order, heroName) end
    -- Preserve liveness if a future patch leaves only weak candidates enabled.
    for _, heroName in ipairs(blockedWeak) do table.insert(order, heroName) end
    return order
end

return Draft
