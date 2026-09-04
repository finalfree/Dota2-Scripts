-- Engine doubles: verify startup ordering/team policy/idempotence, not actual AI behavior.
local entry = "game/dota_addons/overforged/scripts/vscripts/addon_game_mode.lua"
package.path = "game/dota_addons/overforged/scripts/vscripts/?.lua;" .. package.path
FCVAR_CHEAT = 16384
DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_GAMERULES_STATE_HERO_SELECTION = 3
DOTA_GAMERULES_STATE_STRATEGY_TIME = 4
DOTA_GAMERULES_STATE_PRE_GAME = 7
DOTA_MAX_PLAYERS = 10

local function NewMatch(initialState)
    local ctx = {
        state = initialState, commands = {}, events = {}, addBotCalls = {},
        listeners = {}, nextListener = 0, thinking = false, failAdd = false,
        failConsole = false, rules = {}, ruleCalls = 0, players = {},
        itemPrecache = {}, unitPrecache = {}, asyncPrecache = {}, entities = {},
        modelPrecache = {}, resourcePrecache = {}, shares = {},
        botControlConvar = true,
    }
    Flags = nil
    local gameMode = {}
    for _, method in ipairs({"SetFreeCourierModeEnabled", "SetUseDefaultDOTARuneSpawnLogic",
                             "SetTowerBackdoorProtectionEnabled"}) do
        local name = method
        gameMode[name] = function(self, enabled)
            assert(self == gameMode and enabled == true)
            ctx.rules[name] = enabled
            ctx.ruleCalls = ctx.ruleCalls + 1
        end
    end
    function gameMode:SetBotThinkingEnabled(enabled)
        assert(self == gameMode and enabled == true)
        assert(ctx.rules.SetFreeCourierModeEnabled and ctx.rules.SetUseDefaultDOTARuneSpawnLogic
            and ctx.rules.SetTowerBackdoorProtectionEnabled, "configure rules before bot setup")
        ctx.thinking = enabled
        table.insert(ctx.events, "thinking")
    end
    function gameMode:SetExecuteOrderFilter(callback, context)
        assert(self == gameMode and type(callback) == "function" and type(context) == "table")
        ctx.orderFilter = callback
        ctx.orderFilterContext = context
    end
    GameRules = {
        GetGameModeEntity = function() return gameMode end,
        State_Get = function() return ctx.state end,
        GetCustomGameTeamMaxPlayers = function(self, team)
            assert(self == GameRules and (team == DOTA_TEAM_GOODGUYS or team == DOTA_TEAM_BADGUYS))
            return 5
        end,
    }
    PlayerResource = {
        IsValidPlayerID = function(self, playerID)
            assert(self == PlayerResource)
            return ctx.players[playerID] ~= nil
        end,
        IsFakeClient = function(self, playerID)
            assert(self == PlayerResource and ctx.players[playerID] ~= nil)
            return ctx.players[playerID].isBot
        end,
        GetTeam = function(self, playerID)
            assert(self == PlayerResource and ctx.players[playerID] ~= nil)
            return ctx.players[playerID].team
        end,
        GetSelectedHeroName = function(self, playerID)
            assert(self == PlayerResource and ctx.players[playerID] ~= nil)
            return ctx.players[playerID].heroName or ""
        end,
        SetUnitShareMaskForPlayer = function(self, ownerID, otherID, flag, state)
            assert(self == PlayerResource and ctx.players[ownerID].isBot)
            assert(not ctx.players[otherID].isBot and (flag == 1 or flag == 2) and state == false)
            ctx.shares[ownerID .. ":" .. otherID .. ":" .. flag] = state
        end,
    }
    Tutorial = {}
    function Tutorial:AddBot(heroName, lane, difficulty, radiant)
        assert(self == Tutorial and lane == "" and difficulty == "unfair")
        assert(ctx.thinking and ctx.state >= 3 and ctx.state < 7)
        if ctx.failAdd then return false end
        local team = radiant and DOTA_TEAM_GOODGUYS or DOTA_TEAM_BADGUYS
        table.insert(ctx.addBotCalls, {heroName = heroName, team = team})
        local playerID = 0
        while ctx.players[playerID] ~= nil do playerID = playerID + 1 end
        assert(playerID < DOTA_MAX_PLAYERS)
        ctx.players[playerID] = {isBot = true, team = team, heroName = heroName}
        table.insert(ctx.events, "addbot")
        if ctx.reenterAdd then
            ctx:Transition(ctx.state)
            assert(#ctx.commands == 0, "do not enable FretBots inside Tutorial:AddBot")
        end
        if ctx.advanceDuringAdd then ctx.state = 7 end
        return true
    end
    PrecacheItemByNameSync = function(name, context)
        table.insert(ctx.itemPrecache, {name = name, context = context})
    end
    PrecacheUnitByNameSync = function(name, context, playerID)
        table.insert(ctx.unitPrecache, {name = name, context = context, playerID = playerID})
    end
    PrecacheUnitByNameAsync = function(name, callback, playerID)
        table.insert(ctx.asyncPrecache, {name = name, callback = callback, playerID = playerID})
    end
    PrecacheModel = function(name, context)
        table.insert(ctx.modelPrecache, {name = name, context = context})
    end
    PrecacheResource = function(kind, name, context)
        table.insert(ctx.resourcePrecache, {kind = kind, name = name, context = context})
    end
    EntIndexToHScript = function(entindex) return ctx.entities[entindex] end
    Convars = {
        SetBool = function(self, name, value)
            assert(self == Convars and name == "dota_bot_allow_human_control" and value == false)
            ctx.botControlConvar = value
        end,
        GetBool = function(self, name)
            assert(self == Convars and name == "dota_bot_allow_human_control")
            return ctx.botControlConvar
        end,
        RegisterCommand = function(self, name, callback, description, flags)
            if name == "lv_mode_status" then
                assert(flags == 0)
                ctx.modeStatus = callback
                return
            end
            assert(name == "lv_fill_bots" and flags == FCVAR_CHEAT and ctx.thinking)
            ctx.manual = callback
        end,
    }
    ListenToGameEvent = function(name, callback)
        assert(name == "game_rules_state_change" or name == "npc_spawned")
        ctx.nextListener = ctx.nextListener + 1
        ctx.listeners[ctx.nextListener] = {name = name, callback = callback}
        return ctx.nextListener
    end
    StopListeningToGameEvent = function(id)
        assert(ctx.listeners[id])
        ctx.listeners[id] = nil
    end
    SendToServerConsole = function(command)
        assert(#ctx.addBotCalls > 0, "add opposing bots before enabling FretBots")
        assert(ctx.state >= 3 and ctx.state < 7)
        assert(command == "sv_cheats 1; dota_bot_allow_human_control 0; script_reload_code bots/fretbots")
        if ctx.failConsole then error("console unavailable") end
        table.insert(ctx.commands, command)
        table.insert(ctx.events, "fretbots")
    end
    function ctx:AddPlayer(playerID, team, isBot, heroName)
        self.players[playerID] = {team = team, isBot = isBot == true, heroName = heroName or ""}
    end
    function ctx:Transition(state)
        self.state = state
        self:Emit("game_rules_state_change", {})
    end
    function ctx:Emit(name, event)
        for _, listener in pairs(self.listeners) do
            if listener.name == name then listener.callback(event) end
        end
    end
    function ctx:SpawnHero(playerID, entindex, isBot, team, heroName)
        entindex = entindex or (1000 + playerID)
        self:AddPlayer(playerID, team or DOTA_TEAM_GOODGUYS, isBot, heroName)
        local hero = {}
        function hero:IsNull() return false end
        function hero:IsRealHero() return true end
        function hero:GetPlayerOwnerID() return playerID end
        function hero:SetControllableByAllPlayers(value)
            assert(isBot and value == false)
            hero.controllableByAllPlayers = value
        end
        self.entities[entindex] = hero
        self:Emit("npc_spawned", {entindex = entindex})
        return hero
    end
    function ctx:IssueOrder(issuerID, units)
        return self.orderFilter(self.orderFilterContext, {
            issuer_player_id_const = issuerID,
            units = units,
        })
    end

    dofile(entry)
    local precacheContext = {}
    Precache(precacheContext)
    assert(#ctx.itemPrecache == 3 and #ctx.unitPrecache == 3)
    assert(#ctx.modelPrecache == 1 and #ctx.resourcePrecache == 1)
    assert(not ctx.thinking and #ctx.addBotCalls == 0 and #ctx.commands == 0)
    Activate()
    assert(ctx.thinking and ctx.ruleCalls == 3)
    return ctx
end

local ctx = NewMatch(2)
ctx:SpawnHero(0, nil, false, DOTA_TEAM_GOODGUYS, "npc_dota_hero_juggernaut")
assert(#ctx.asyncPrecache == 3)
ctx:SpawnHero(0, nil, false, DOTA_TEAM_GOODGUYS, "npc_dota_hero_juggernaut")
assert(#ctx.asyncPrecache == 3, "do not repeat cosmetic precache on respawn")
local botHero = ctx:SpawnHero(1, nil, true, DOTA_TEAM_BADGUYS, "npc_dota_hero_sven")
assert(botHero.controllableByAllPlayers == false)
assert(ctx.shares["1:0:1"] == false and ctx.shares["1:0:2"] == false)
assert(ctx:IssueOrder(0, {1001}) == false, "block a human order to a bot hero")
assert(ctx:IssueOrder(1, {1001}) == true, "allow an order issued by the owning bot")
assert(ctx:IssueOrder(0, {1000}) == true, "allow a human to order their own hero")
ctx:Transition(3)
assert(#ctx.addBotCalls == 0, "automatic setup waits until human selection is complete")
ctx:Transition(4)
assert(#ctx.addBotCalls == 4 and #ctx.commands == 1)
for _, call in ipairs(ctx.addBotCalls) do
    assert(call.team == DOTA_TEAM_BADGUYS, "only fill the humans' opposing team")
    assert(call.heroName ~= "npc_dota_hero_juggernaut", "avoid an already selected hero")
end
ctx:Transition(4)
ctx.manual()
assert(#ctx.addBotCalls == 4 and #ctx.commands == 1, "bot setup is idempotent")
print("PASS: AddBot fills only the opposing team after hero selection and starts FretBots once")

ctx = NewMatch(2)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
ctx:AddPlayer(1, DOTA_TEAM_BADGUYS, false)
ctx:Transition(4)
assert(#ctx.addBotCalls == 0 and #ctx.commands == 0)
assert(GameRules.LVBotStartup.botSetupComplete)
print("PASS: human players on both teams suppress all automatic bots and FretBots")

ctx = NewMatch(2)
ctx:AddPlayer(0, DOTA_TEAM_BADGUYS, false)
ctx:Transition(4)
assert(#ctx.addBotCalls == 5 and #ctx.commands == 1)
for _, call in ipairs(ctx.addBotCalls) do assert(call.team == DOTA_TEAM_GOODGUYS) end
print("PASS: Dire-only humans receive a full Radiant bot opponent team")

ctx = NewMatch(2)
ctx:Transition(4)
assert(#ctx.addBotCalls == 0 and #ctx.commands == 0)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
ctx.manual()
assert(#ctx.addBotCalls == 5 and #ctx.commands == 1)
print("PASS: no-human setup waits and the manual fallback can retry")

ctx = NewMatch(2)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
ctx.failAdd = true
ctx:Transition(4)
assert(#ctx.addBotCalls == 0 and #ctx.commands == 0)
assert(not GameRules.LVBotStartup.botSetupComplete)
ctx.failAdd = false
ctx.manual()
assert(#ctx.addBotCalls == 5 and #ctx.commands == 1)
print("PASS: failed AddBot setup skips FretBots and permits retry")

ctx = NewMatch(2)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
ctx.reenterAdd = true
ctx:Transition(4)
assert(#ctx.addBotCalls == 5 and #ctx.commands == 1)
print("PASS: reentrant AddBot events do not duplicate bots or start FretBots early")

ctx = NewMatch(2)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
ctx.advanceDuringAdd = true
ctx:Transition(4)
assert(#ctx.addBotCalls == 1 and #ctx.commands == 0)
assert(not GameRules.LVBotStartup.botSetupComplete)
print("PASS: transition to pregame during AddBot setup stops cleanly without late FretBots")

ctx = NewMatch(2)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
Flags = {isFretBotsInitialized = true}
ctx:Transition(4)
assert(#ctx.addBotCalls == 5 and #ctx.commands == 0)
assert(GameRules.LVBotStartup.fretBotsRequested)
print("PASS: already initialized FretBots is not reloaded")

ctx = NewMatch(2)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
ctx.failConsole = true
ctx:Transition(4)
assert(#ctx.addBotCalls == 5 and #ctx.commands == 0)
assert(not GameRules.LVBotStartup.fretBotsRequested)
ctx.failConsole = false
ctx.manual()
assert(#ctx.addBotCalls == 5 and #ctx.commands == 1)
print("PASS: FretBots queue failure retries without duplicating bots")

dofile(entry)
Activate()
local listenerCount = 0
for _ in pairs(ctx.listeners) do listenerCount = listenerCount + 1 end
assert(listenerCount == 2 and #ctx.addBotCalls == 5 and #ctx.commands == 1)
assert(ctx.ruleCalls == 6, "reload only reapplies engine flags")
print("PASS: repeated activation preserves per-match setup guards and replaces listeners")

ctx = NewMatch(7)
ctx:AddPlayer(0, DOTA_TEAM_GOODGUYS, false)
ctx.manual()
ctx:Transition(8)
assert(#ctx.addBotCalls == 0 and #ctx.commands == 0)
print("PASS: activation or commands at/after pregame do not add bots")
