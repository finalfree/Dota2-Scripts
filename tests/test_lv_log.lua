local entry = "game/dota_addons/overforged/scripts/vscripts/lv_log.lua"
local originalPrint = print
local lines = {}
Msg = function(line) lines[#lines + 1] = line end
local log = dofile(entry)
print = function() error("external print must not be used") end
Msg = function() error("must use captured engine Msg") end
log("[LV-MODE] after FretBots")
assert(lines[1] == "[LV-MODE] after FretBots\n")

Msg = nil
print = function(line) lines[#lines + 1] = line end
local fallback = dofile(entry)
print = function() error("must use captured fallback") end
fallback(42)
assert(lines[2] == "42")
print = originalPrint
print("PASS: logger captures engine Msg or print fallback without modifying external globals")
