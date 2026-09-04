-- Read-only diagnostics. Never enable native rules or create test units/items here.
local Probe = {}
local Log = require("lv_log")

local function Read(callback)
    local ok, value = pcall(callback)
    if not ok or value == nil then return "unavailable" end
    return tostring(value)
end

function Probe.Report(checkpoint)
    Log("[LV-MODE] checkpoint=" .. tostring(checkpoint) .. " addon=overforged")
    Log("[LV-MODE] state=" .. Read(function() return GameRules:State_Get() end)
        .. " requested_force_mode=" .. Read(function() return Convars:GetInt("dota_force_gamemode") end))
    -- GetGameMode is exposed in the bot VM, but may not exist in the addon VM.
    -- Do not replace an unavailable actual mode with the requested convar value.
    Log("[LV-MODE] actual_game_mode=" .. Read(function()
        if type(GetGameMode) == "function" then return GetGameMode() end
        if GameRules.GetGameMode then return GameRules:GetGameMode() end
    end))
    local rules = GameRules.LVStandardRules or {}
    Log("[LV-MODE] free_couriers=" .. tostring(rules.free_couriers or "not_requested")
        .. " default_runes=" .. tostring(rules.default_runes or "not_requested")
        .. " tower_backdoor=" .. tostring(rules.tower_backdoor or "not_requested"))
    Log("[LV-MODE] tower_backdoor_enabled=" .. Read(function()
        return GameRules:GetGameModeEntity():GetTowerBackdoorProtectionEnabled()
    end))
    Log("[LV-MODE] couriers=" .. Read(function()
        return #Entities:FindAllByClassname("npc_dota_courier")
    end) .. " heroes=" .. Read(function() return #HeroList:GetAllHeroes() end)
        .. " fretbots_initialized=" .. tostring(Flags ~= nil and Flags.isFretBotsInitialized == true))
    Log("[LV-MODE] bot_human_control=" .. Read(function()
        return Convars:GetBool("dota_bot_allow_human_control")
    end))
    Log("[LV-MODE] lv_items_in_inventory=" .. Read(function()
        local count = 0
        for _, hero in pairs(HeroList:GetAllHeroes()) do
            for slot = 0, 16 do
                local item = hero:GetItemInSlot(slot)
                if item and string.find(item:GetAbilityName(), "^item_lv_") then count = count + 1 end
            end
        end
        return count
    end))
    Log("[LV-MODE] CUSTOM addon with baseline rules; requested flags do not prove behavior or native AP.")
end

return Probe
