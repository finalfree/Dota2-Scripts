-- Local addon startup. OHA/FretBots remain an external host installation.
-- Published Workshop compatibility still needs separate verification.
local AUTO_FILL_BOTS = true
local AUTO_ENABLE_FRETBOTS = true -- Runs sv_cheats 1; difficulty voting is unchanged.
local BOT_HUMAN_CONTROL_CONVAR = "dota_bot_allow_human_control"
local DEFAULT_TEAM_CAPACITY = 5
local Log = require("lv_log")
local StandardRules = require("lv_standard_rules")
local ModeProbe = require("lv_mode_probe")

-- Tutorial:AddBot requires an explicit hero. Keep the order roughly aligned
-- with OHA's position 1-5 slot convention and retain fallbacks for collisions
-- with heroes already selected by human players.
local BOT_HERO_CANDIDATES = {
    "npc_dota_hero_juggernaut",
    "npc_dota_hero_nevermore",
    "npc_dota_hero_axe",
    "npc_dota_hero_lion",
    "npc_dota_hero_crystal_maiden",
    "npc_dota_hero_luna",
    "npc_dota_hero_viper",
    "npc_dota_hero_tidehunter",
    "npc_dota_hero_witch_doctor",
    "npc_dota_hero_lich",
}

-- Smeevil's Penance style 4 (Gold) still remained nonresident after the
-- generic player-aware unit precache experiment. Keep this as a narrow
-- control-group fallback; the assets themselves remain Valve-owned content.
local SMEEVIL_GOLD_WARD_MODEL =
    "models/items/wards/smeevil_ward/smeevil_ward_gold.vmdl"
local SMEEVIL_GOLD_WARD_PARTICLE =
    "particles/econ/wards/smeevil/smeevil_ward/smeevil_ward_yellow_ambient.vpcf"

local UNIT_SHARE_HEROES = 1
local UNIT_SHARE_UNITS = 2

local UTILITY_ITEM_NAMES = {
    "item_ward_observer",
    "item_ward_sentry",
    "item_ward_dispenser",
}

local UTILITY_UNIT_NAMES = {
    "npc_dota_observer_wards",
    "npc_dota_sentry_wards",
    "npc_dota_courier",
}

local function InBotSetupWindow()
    local state = GameRules:State_Get()
    return state >= DOTA_GAMERULES_STATE_HERO_SELECTION
        and state < DOTA_GAMERULES_STATE_PRE_GAME
end

local function InAutomaticBotSetupWindow()
    local state = GameRules:State_Get()
    return state >= DOTA_GAMERULES_STATE_STRATEGY_TIME
        and state < DOTA_GAMERULES_STATE_PRE_GAME
end

local function DisableHumanBotControl(startup)
    local ok, err = pcall(function()
        Convars:SetBool(BOT_HUMAN_CONTROL_CONVAR, false)
    end)
    if not ok then
        if not startup.botControlConvarWarning then
            startup.botControlConvarWarning = true
            Log("[LV] Could not disable human bot control through Convars: " .. tostring(err))
        end
        return false
    end

    local readOK, value = pcall(function()
        return Convars:GetBool(BOT_HUMAN_CONTROL_CONVAR)
    end)
    if not startup.botControlConvarLogged then
        startup.botControlConvarLogged = true
        Log("[LV] Human bot control disabled; " .. BOT_HUMAN_CONTROL_CONVAR .. "="
            .. (readOK and tostring(value) or "unavailable") .. ".")
    end
    return true
end

local function RestrictBotHeroControl(startup, hero)
    local ownerID = hero:GetPlayerOwnerID()
    if ownerID == nil or ownerID < 0 then return end

    local ownerIsBot = false
    local ownerCheckOK, ownerCheckError = pcall(function()
        ownerIsBot = PlayerResource:IsValidPlayerID(ownerID)
            and PlayerResource:IsFakeClient(ownerID)
    end)
    if not ownerCheckOK then
        if not startup.botControlApiWarning then
            startup.botControlApiWarning = true
            Log("[LV] Could not inspect bot ownership: " .. tostring(ownerCheckError))
        end
        return
    end

    if ownerIsBot then
        local unitOK, unitError = pcall(function()
            hero:SetControllableByAllPlayers(false)
        end)
        if not unitOK and not startup.botUnitControlWarning then
            startup.botUnitControlWarning = true
            Log("[LV] Could not clear all-player control on a bot hero: " .. tostring(unitError))
        end
    end

    -- Reconcile every known bot/human pair whenever any real hero spawns.
    -- This also covers a human joining after bot heroes already exist.
    local shareOK, shareError = pcall(function()
        local maxPlayers = DOTA_MAX_PLAYERS or 24
        for botID = 0, maxPlayers - 1 do
            if PlayerResource:IsValidPlayerID(botID)
                and PlayerResource:IsFakeClient(botID) then
                for humanID = 0, maxPlayers - 1 do
                    if PlayerResource:IsValidPlayerID(humanID)
                        and not PlayerResource:IsFakeClient(humanID) then
                        PlayerResource:SetUnitShareMaskForPlayer(
                            botID, humanID, UNIT_SHARE_HEROES, false)
                        PlayerResource:SetUnitShareMaskForPlayer(
                            botID, humanID, UNIT_SHARE_UNITS, false)
                    end
                end
            end
        end
    end)
    if not shareOK and not startup.botShareControlWarning then
        startup.botShareControlWarning = true
        Log("[LV] Could not clear bot-to-human unit sharing: " .. tostring(shareError))
    elseif shareOK and not startup.botShareControlLogged then
        startup.botShareControlLogged = true
        Log("[LV] Bot hero/unit sharing to human players disabled.")
    end
end

local function AllowExecuteOrder(startup, event)
    if event == nil then return true end
    local issuerID = event.issuer_player_id_const
    if issuerID == nil then issuerID = event.issuer_player_id end
    if issuerID == nil or issuerID < 0 then return true end

    local issuerIsHuman = false
    local issuerOK, issuerError = pcall(function()
        issuerIsHuman = PlayerResource:IsValidPlayerID(issuerID)
            and not PlayerResource:IsFakeClient(issuerID)
    end)
    if not issuerOK then
        if not startup.orderFilterWarning then
            startup.orderFilterWarning = true
            Log("[LV] Bot-control order filter could not inspect issuer: "
                .. tostring(issuerError))
        end
        return true
    end
    if not issuerIsHuman or type(event.units) ~= "table" then return true end

    for _, entindex in pairs(event.units) do
        local blocked = false
        local botOwnerID = -1
        local unitOK, unitError = pcall(function()
            local unit = EntIndexToHScript(entindex)
            if unit == nil or unit:IsNull() then return end
            botOwnerID = unit:GetPlayerOwnerID()
            blocked = botOwnerID ~= nil and botOwnerID >= 0
                and PlayerResource:IsValidPlayerID(botOwnerID)
                and PlayerResource:IsFakeClient(botOwnerID)
        end)
        if not unitOK then
            if not startup.orderFilterWarning then
                startup.orderFilterWarning = true
                Log("[LV] Bot-control order filter could not inspect a unit: "
                    .. tostring(unitError))
            end
        elseif blocked then
            startup.blockedHumanBotOrders = (startup.blockedHumanBotOrders or 0) + 1
            if startup.blockedHumanBotOrders <= 3 then
                Log("[LV] Blocked human order to bot-owned unit; issuer="
                    .. tostring(issuerID) .. " bot_owner=" .. tostring(botOwnerID) .. ".")
            end
            return false
        end
    end
    return true
end

local function GetTeamPopulation()
    local population = {
        [DOTA_TEAM_GOODGUYS] = {humans = 0, bots = 0, total = 0},
        [DOTA_TEAM_BADGUYS] = {humans = 0, bots = 0, total = 0},
    }
    local usedHeroes = {}
    local maxPlayers = DOTA_MAX_PLAYERS or 24
    for playerID = 0, maxPlayers - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            local team = PlayerResource:GetTeam(playerID)
            local teamPopulation = population[team]
            if teamPopulation ~= nil then
                teamPopulation.total = teamPopulation.total + 1
                if PlayerResource:IsFakeClient(playerID) then
                    teamPopulation.bots = teamPopulation.bots + 1
                else
                    teamPopulation.humans = teamPopulation.humans + 1
                end
                local heroOK, heroName = pcall(function()
                    return PlayerResource:GetSelectedHeroName(playerID)
                end)
                if heroOK and heroName ~= nil and heroName ~= "" then
                    usedHeroes[heroName] = true
                end
            end
        end
    end
    return population, usedHeroes
end

local function GetTeamCapacity(team)
    local ok, capacity = pcall(function()
        return GameRules:GetCustomGameTeamMaxPlayers(team)
    end)
    if ok and type(capacity) == "number" and capacity > 0 then return capacity end
    return DEFAULT_TEAM_CAPACITY
end

local function FillOpponentBotsOnce(startup)
    if startup.botsPopulating then return false end
    if startup.botSetupComplete then return startup.botSetupHasBots == true end

    local population, usedHeroes = GetTeamPopulation()
    local radiantHumans = population[DOTA_TEAM_GOODGUYS].humans
    local direHumans = population[DOTA_TEAM_BADGUYS].humans
    if radiantHumans == 0 and direHumans == 0 then
        Log("[LV] Bot setup waiting for a human player to join Radiant or Dire.")
        return false
    end
    if radiantHumans > 0 and direHumans > 0 then
        startup.botSetupComplete = true
        startup.botSetupHasBots = false
        startup.botsPopulated = false
        Log("[LV] Human players are present on both teams; no bots were added.")
        return false
    end

    local targetTeam = radiantHumans > 0 and DOTA_TEAM_BADGUYS or DOTA_TEAM_GOODGUYS
    local target = population[targetTeam]
    local needed = math.max(0, GetTeamCapacity(targetTeam) - target.total)
    if needed == 0 then
        startup.botSetupComplete = true
        startup.botSetupHasBots = target.bots > 0
        startup.botsPopulated = startup.botSetupHasBots
        Log("[LV] Opposing team already has no empty slots; no bots were added.")
        return startup.botSetupHasBots
    end
    if Tutorial == nil or Tutorial.AddBot == nil then
        Log("[LV] Tutorial:AddBot is unavailable; retry lv_fill_bots before pregame.")
        return false
    end

    -- Adding a bot can emit further state/spawn events. Do not start FretBots
    -- from those nested callbacks; wait until this whole team is complete.
    startup.botsPopulating = true
    local added = 0
    local radiant = targetTeam == DOTA_TEAM_GOODGUYS
    local lastError = nil
    for _, heroName in ipairs(BOT_HERO_CANDIDATES) do
        if added >= needed then break end
        if not usedHeroes[heroName] then
            local ok, result = pcall(function()
                return Tutorial:AddBot(heroName, "", "unfair", radiant)
            end)
            if ok and result == true then
                added = added + 1
                usedHeroes[heroName] = true
            elseif not ok then
                lastError = result
            end
        end
    end
    startup.botsPopulating = false

    if added < needed then
        Log("[LV] Tutorial:AddBot added " .. tostring(added) .. "/" .. tostring(needed)
            .. " opposing bots; retry lv_fill_bots before pregame"
            .. (lastError ~= nil and (": " .. tostring(lastError)) or "."))
        return false
    end
    startup.botSetupComplete = true
    startup.botSetupHasBots = target.bots + added > 0
    startup.botsPopulated = true
    DisableHumanBotControl(startup)
    Log("[LV] Added " .. tostring(added) .. " bots to the human players' opposing team via "
        .. "Tutorial:AddBot. Bot behavior scripts are still selected by the engine.")
    return true
end

local function EnableFretBotsOnce(startup)
    if not AUTO_ENABLE_FRETBOTS or startup.fretBotsRequested then return end
    if not InBotSetupWindow() then return end
    -- A host may already have enabled it manually in this server Lua VM.
    if Flags and Flags.isFretBotsInitialized then
        startup.fretBotsRequested = true
        Log("[LV] FretBots is already initialized; skipping reload.")
        return
    end
    startup.fretBotsRequested = true
    local ok, err = pcall(function()
        -- Same command as the host's working manual flow; never require bot_generic.
        SendToServerConsole("sv_cheats 1; dota_bot_allow_human_control 0; "
            .. "script_reload_code bots/fretbots")
    end)
    if not ok then
        startup.fretBotsRequested = false
        Log("[LV] Could not queue FretBots startup: " .. tostring(err))
        return
    end
    -- Console commands are queued; this does not assert that FretBots loaded.
    Log("[LV] FretBots enable command queued (sv_cheats 1). Check its welcome/vote messages.")
end

local function PrecachePlayerUtilityCosmetics(startup, playerID)
    if playerID == nil or playerID < 0 then return false end
    startup.precachedUtilityLoadouts = startup.precachedUtilityLoadouts or {}
    if startup.precachedUtilityLoadouts[playerID] then return true end

    -- Retain the generic player-aware path for equipped ward/courier cosmetics;
    -- the Gold ward below is the narrow fallback proven necessary by ablation.
    startup.precachedUtilityLoadouts[playerID] = true
    local ok, err = pcall(function()
        for _, unitName in ipairs(UTILITY_UNIT_NAMES) do
            PrecacheUnitByNameAsync(unitName, function() end, playerID)
        end
    end)
    if not ok then
        startup.precachedUtilityLoadouts[playerID] = nil
        Log("[LV] Player utility cosmetic precache failed for player "
            .. tostring(playerID) .. ": " .. tostring(err))
        return false
    end
    Log("[LV] Player utility cosmetic precache queued for player " .. tostring(playerID) .. ".")
    return true
end

function Precache(context)
    -- Register the base item/unit dependency graphs during level loading.
    -- Player-specific cosmetics are resolved later, once a real hero proves
    -- that its PlayerID is connected. The known crashing Gold style is also
    -- registered explicitly as the current control-group experiment.
    for _, itemName in ipairs(UTILITY_ITEM_NAMES) do
        PrecacheItemByNameSync(itemName, context)
    end
    for _, unitName in ipairs(UTILITY_UNIT_NAMES) do
        PrecacheUnitByNameSync(unitName, context, -1)
    end
    PrecacheModel(SMEEVIL_GOLD_WARD_MODEL, context)
    PrecacheResource("particle", SMEEVIL_GOLD_WARD_PARTICLE, context)
end

function Activate()
    -- Configure before hero creation/population; never manually spawn duplicates.
    local mode = GameRules:GetGameModeEntity()
    GameRules.LVStandardRules = StandardRules.Apply(mode)
    -- Populating slots alone does not enable custom-game bot thinking.
    mode:SetBotThinkingEnabled(true)
    Log("[LV] Bot thinking enable requested.")
    Log("[LV] overforged addon loaded (Workshop prototype)")

    -- Keep once-per-match guards across script reloads/repeated Activate calls.
    local startup = GameRules.LVBotStartup or {}
    GameRules.LVBotStartup = startup
    DisableHumanBotControl(startup)
    mode:SetExecuteOrderFilter(function(filterStartup, event)
        return AllowExecuteOrder(filterStartup, event)
    end, startup)
    if startup.listener ~= nil then
        StopListeningToGameEvent(startup.listener)
    end
    if startup.cosmeticListener ~= nil then
        StopListeningToGameEvent(startup.cosmeticListener)
    end
    local function OnStateChanged()
        ModeProbe.Report("state_changed")
        -- Wait for human teams to be chosen; never fill during custom-game setup.
        if not InAutomaticBotSetupWindow() then return end
        if AUTO_FILL_BOTS and not FillOpponentBotsOnce(startup) then return end
        EnableFretBotsOnce(startup)
    end
    startup.listener = ListenToGameEvent("game_rules_state_change", OnStateChanged, nil)
    startup.cosmeticListener = ListenToGameEvent("npc_spawned", function(event)
        if event == nil or event.entindex == nil then return end
        local unit = EntIndexToHScript(event.entindex)
        if unit == nil or unit:IsNull() or not unit:IsRealHero() then return end
        RestrictBotHeroControl(startup, unit)
        PrecachePlayerUtilityCosmetics(startup, unit:GetPlayerOwnerID())
    end, nil)

    Convars:RegisterCommand("lv_mode_status", function()
        ModeProbe.Report("manual")
    end, "LV read-only mode/addon/courier diagnostics; does not switch modes", 0)

    -- Retained as an idempotent fallback; normal startup needs no console input.
    Convars:RegisterCommand("lv_fill_bots", function()
        if not InBotSetupWindow() then
            Log("[LV] Fill bots after hero selection begins, before pregame.")
            return
        end
        if FillOpponentBotsOnce(startup) then EnableFretBotsOnce(startup) end
    end, "LV fallback: fill only the human side's opponent team and request FretBots", FCVAR_CHEAT)
    OnStateChanged() -- Also handles activation after the selection event already fired.
end
