-- Only engine-owned boolean settings: no manual spawns, schedules or balance overrides.
package.path = "game/dota_addons/overforged/scripts/vscripts/?.lua;" .. package.path
local lines = {}
Msg = function(line) table.insert(lines, line) end
local Rules = require("lv_standard_rules")
local methods = {
    "SetFreeCourierModeEnabled", "SetUseDefaultDOTARuneSpawnLogic", "SetTowerBackdoorProtectionEnabled",
}
local calls = {}
local mode = setmetatable({}, {__index = function(_, name) error("unexpected API: " .. name) end})
for _, method in ipairs(methods) do
    local name = method
    mode[name] = function(self, value)
        assert(self == mode and value == true)
        calls[#calls + 1] = name
    end
end
local status = Rules.Apply(mode)
assert(status.free_couriers == "requested" and status.default_runes == "requested"
    and status.tower_backdoor == "requested")
assert(#calls == 3 and table.concat(calls, ",") == table.concat(methods, ","))
Rules.Apply(mode)
assert(#calls == 6, "reapplication only repeats three boolean setters")

mode.SetFreeCourierModeEnabled = nil
mode.SetUseDefaultDOTARuneSpawnLogic = function() error("simulated engine failure") end
status = Rules.Apply(mode)
assert(status.free_couriers == "failed" and status.default_runes == "failed"
    and status.tower_backdoor == "requested")
assert(#calls == 7, "one bad setting must not prevent other requests")
assert(string.find(table.concat(lines, "\n"), "simulated engine failure", 1, true))
status = Rules.Apply({})
assert(status.free_couriers == "failed" and status.default_runes == "failed"
    and status.tower_backdoor == "failed")
print("PASS: baseline flags only, safe reapplication, missing/throwing APIs reported without aborting startup")
