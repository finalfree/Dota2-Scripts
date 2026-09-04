-- Capture engine output before external FretBots replaces the global print.
-- Do not change its debug setting or restore print globally.
local engineMsg = Msg
local enginePrint = print

return function(message)
    if type(engineMsg) == "function" then
        engineMsg(tostring(message) .. "\n")
    else
        enginePrint(tostring(message))
    end
end
