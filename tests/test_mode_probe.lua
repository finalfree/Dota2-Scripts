-- Diagnostics must stay read-only and must not confuse a convar with actual mode.
package.path = "game/dota_addons/overforged/scripts/vscripts/?.lua;" .. package.path
local originalPrint = print
local lines = {}
Msg = function(line) table.insert(lines, line) end
local probe = require("lv_mode_probe")
-- Simulate FretBots silencing global print after addon activation.
print = function() error("probe must not use the replaced global print") end
local function Contains(text)
    return string.find(table.concat(lines, "\n"), text, 1, true) ~= nil
end
GameRules = {
    State_Get = function() return 7 end,
    LVStandardRules = {free_couriers = "requested", default_runes = "failed", tower_backdoor = "requested"},
    GetGameModeEntity = function()
        return {GetTowerBackdoorProtectionEnabled = function() return true end}
    end,
}
Convars = {
    GetInt = function(_, name) assert(name == "dota_force_gamemode"); return 1 end,
    GetBool = function(_, name) assert(name == "dota_bot_allow_human_control"); return false end,
}
GetGameMode = nil
Entities = {FindAllByClassname = function(_, name)
    assert(name == "npc_dota_courier")
    return {{}, {}}
end}
HeroList = {GetAllHeroes = function()
    return {{GetItemInSlot = function(_, slot)
        if slot == 0 then return {GetAbilityName = function() return "item_lv_octarine_core" end} end
        if slot == 1 then return {GetAbilityName = function() return "item_blink" end} end
    end}}
end}
Flags = {isFretBotsInitialized = true}
probe.Report("test")
assert(Contains("actual_game_mode=unavailable"))
assert(Contains("requested_force_mode=1"))
assert(Contains("couriers=2 heroes=1 fretbots_initialized=true"))
assert(Contains("bot_human_control=false"))
assert(Contains("lv_items_in_inventory=1"))
assert(Contains("free_couriers=requested default_runes=failed tower_backdoor=requested"))
assert(Contains("tower_backdoor_enabled=true"))
lines = {}
GetGameMode = function() return 15 end
probe.Report("custom-despite-request")
assert(Contains("actual_game_mode=15"))
lines = {}
GetGameMode = nil
GameRules.GetGameMode = function() return 1 end
probe.Report("AP")
assert(Contains("actual_game_mode=1"))
lines = {}
GameRules, Convars, Entities, HeroList, Flags = {}, {}, {}, {}, nil
probe.Report("missing-APIs")
assert(Contains("couriers=unavailable") and Contains("actual_game_mode=unavailable"))
assert(Contains("lv_items_in_inventory=unavailable"))
assert(Contains("free_couriers=not_requested"))
assert(Contains("tower_backdoor_enabled=unavailable"))
assert(Contains("bot_human_control=unavailable"))
print = originalPrint
print("PASS: read-only probe survives replaced print, distinguishes requests/readbacks, tolerates missing APIs")
