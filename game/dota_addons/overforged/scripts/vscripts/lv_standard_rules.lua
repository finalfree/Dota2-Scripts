-- Enable engine-owned normal-map mechanics, not a native AP mode switch.
-- Current API/source references and in-game acceptance: docs/workshop-addon.md.
local Log = require("lv_log")
local Rules = {}
local settings = {
    {"free_couriers", "SetFreeCourierModeEnabled"},
    {"default_runes", "SetUseDefaultDOTARuneSpawnLogic"},
    {"tower_backdoor", "SetTowerBackdoorProtectionEnabled"},
}

function Rules.Apply(mode)
    local status = {}
    for _, setting in ipairs(settings) do
        local key, method = setting[1], setting[2]
        local ok, err = pcall(function()
            assert(type(mode[method]) == "function", method .. " unavailable")
            mode[method](mode, true)
        end)
        -- A successful setter is a request, not proof of in-game behavior.
        status[key] = ok and "requested" or "failed"
        Log("[LV-RULES] " .. key .. "=" .. status[key]
            .. (ok and "" or (" error=" .. tostring(err))))
    end
    return status
end

return Rules
