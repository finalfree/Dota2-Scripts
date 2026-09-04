-- Invoked by the item's data-driven passive; no addon_game_mode dependency.
-- Gameplay state stays server-side so no custom Lua modifier is networked.
local TRUESIGHT = "modifier_truesight"
local CONSUMED_STATUS = "modifier_item_lv_gem_consumed_status"
local AUDIT_INTERVAL = 2.0
local SPAWN_APPLY_DELAY = 0.03

LV_GEM_GLOBAL_TRUESIGHT = LV_GEM_GLOBAL_TRUESIGHT or {
    sources = {},
    audits = {},
    status_items = {},
    listeners_registered = false,
    listener_ids = {},
}

local state = LV_GEM_GLOBAL_TRUESIGHT
state.status_items = state.status_items or {}

local function valid(entity)
    return entity ~= nil and entity.IsNull ~= nil and not entity:IsNull()
end

local function source_valid(hero)
    return valid(hero) and hero._lv_gem_consumed == true
        and hero:IsRealHero() and not hero:IsIllusion()
        and not hero:IsTempestDouble() and not (hero.IsClone and hero:IsClone())
end

local function eligible(hero, item)
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then
        return false
    end
    if not hero:IsRealHero() or hero:IsIllusion() or not hero:IsAlive()
        or hero:IsTempestDouble() or (hero.IsClone and hero:IsClone()) then
        return false
    end
    -- Never consume in a courier, stash, backpack, neutral slot or on the ground.
    for slot = 0, 5 do
        if hero:GetItemInSlot(slot) == item then
            return true
        end
    end
    return false
end

local function team_source(team)
    local hero = state.sources[team]
    if source_valid(hero) then return hero end
    state.sources[team] = nil
    return nil
end

local function own_truesight(unit, source)
    if not valid(unit) or not unit.FindModifierByNameAndCaster then return nil end
    local modifier = unit:FindModifierByNameAndCaster(TRUESIGHT, source)
    if valid(modifier) then return modifier end
    return nil
end

local function own_consumed_status(hero)
    if not valid(hero) or not hero.FindModifierByNameAndCaster then return nil end
    local modifier = hero:FindModifierByNameAndCaster(CONSUMED_STATUS, hero)
    if valid(modifier) then return modifier end
    return nil
end

local function apply_consumed_status(hero, item)
    local ok, result = pcall(function()
        return item:ApplyDataDrivenModifier(
            hero, hero, CONSUMED_STATUS, { duration = -1 })
    end)
    local modifier = own_consumed_status(hero)
    if not ok or not modifier then
        print("[lv_gem] consumed status icon failed: " .. tostring(result))
        return nil
    end
    return modifier
end

local function is_enemy(unit, source)
    if not valid(unit) or not unit.GetTeamNumber then return false end
    local unit_team = unit:GetTeamNumber()
    if unit_team == source:GetTeamNumber() then return false end
    if DOTA_TEAM_NEUTRALS ~= nil and unit_team == DOTA_TEAM_NEUTRALS then return false end
    if DOTA_TEAM_NOTEAM ~= nil and unit_team == DOTA_TEAM_NOTEAM then return false end
    return true
end

local function reconcile_unit(unit, source)
    if not valid(unit) then return false end
    local existing = own_truesight(unit, source)
    if not is_enemy(unit, source) then
        -- A dominated or replaced unit may have changed teams without spawning.
        if existing and existing.Destroy then existing:Destroy() end
        return false
    end
    if existing then return true end

    local ok, modifier = pcall(function()
        return unit:AddNewModifier(source, nil, TRUESIGHT, { duration = -1 })
    end)
    if not ok or not valid(modifier) then
        print("[lv_gem] native True Sight failed for unit "
            .. tostring(unit.entindex and unit:entindex() or "?") .. ": " .. tostring(modifier))
        return false
    end
    return true
end

local function reconcile_all_sources_for_unit(unit)
    for team in pairs(state.sources) do
        local source = team_source(team)
        if source then reconcile_unit(unit, source) end
    end
end

local function find_all_for_team(source)
    return FindUnitsInRadius(
        source:GetTeamNumber(),
        source:GetAbsOrigin(),
        nil,
        FIND_UNITS_EVERYWHERE,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_ALL,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES + DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
        FIND_ANY_ORDER,
        false
    )
end

local function audit_team(team)
    local source = team_source(team)
    if not source then return false end
    local ok, units = pcall(find_all_for_team, source)
    if not ok or type(units) ~= "table" then
        print("[lv_gem] global unit scan failed: " .. tostring(units))
        return false
    end
    for _, unit in pairs(units) do reconcile_unit(unit, source) end
    return true
end

local function defer_reconcile(entindex)
    entindex = tonumber(entindex)
    if not entindex then return end
    local scheduler = nil
    for team in pairs(state.sources) do
        scheduler = team_source(team)
        if scheduler then break end
    end
    if not scheduler then return end

    local ok = pcall(function()
        scheduler:SetContextThink("lv_gem_spawn_" .. tostring(entindex), function()
            local resolved, unit = pcall(EntIndexToHScript, entindex)
            if resolved and valid(unit) then reconcile_all_sources_for_unit(unit) end
            return nil
        end, SPAWN_APPLY_DELAY)
    end)
    if not ok then
        print("[lv_gem] deferred spawn processing failed; periodic audit will retry")
    end
end

function LVGemOnNPCSpawned(event)
    if IsServer() and event then defer_reconcile(event.entindex) end
end

function LVGemOnNPCReplaced(event)
    if IsServer() and event then defer_reconcile(event.new_entindex) end
end

local function register_listeners()
    if state.listeners_registered then return true end
    if state.listener_ids.npc_spawned == nil then
        local ok, listener_id = pcall(
            ListenToGameEvent, "npc_spawned", LVGemOnNPCSpawned, nil)
        if ok then state.listener_ids.npc_spawned = listener_id end
    end
    if state.listener_ids.npc_replaced == nil then
        local ok, listener_id = pcall(
            ListenToGameEvent, "npc_replaced", LVGemOnNPCReplaced, nil)
        if ok then state.listener_ids.npc_replaced = listener_id end
    end
    state.listeners_registered = state.listener_ids.npc_spawned ~= nil
        and state.listener_ids.npc_replaced ~= nil
    if not state.listeners_registered then
        print("[lv_gem] spawn listener unavailable; periodic audit remains active")
    end
    return state.listeners_registered
end

local function start_audit(team, hero)
    if state.audits[team] then return true end
    local ok = pcall(function()
        hero:SetContextThink("lv_gem_global_audit_" .. tostring(team), function()
            if not team_source(team) then
                state.audits[team] = nil
                return nil
            end
            audit_team(team)
            return AUDIT_INTERVAL
        end, AUDIT_INTERVAL)
    end)
    if ok then state.audits[team] = true end
    return ok
end

local function clear_global_truesight(team, hero, status)
    state.sources[team] = nil
    state.audits[team] = nil
    state.status_items[team] = nil
    hero._lv_gem_consumed = nil
    hero._lv_gem_status = nil
    if valid(status) and status.Destroy then status:Destroy() end

    -- Best-effort rollback if hiding the consumed item fails after the initial scan.
    local ok, units = pcall(find_all_for_team, hero)
    if ok and type(units) == "table" then
        for _, unit in pairs(units) do
            local modifier = own_truesight(unit, hero)
            if modifier and modifier.Destroy then modifier:Destroy() end
        end
    end
end

local function enable_global_truesight(hero, item)
    local team = hero:GetTeamNumber()
    if team_source(team) then return false, "team already enabled" end

    local status = apply_consumed_status(hero, item)
    if not status then return false, "status icon initialization failed" end

    hero._lv_gem_consumed = true
    hero._lv_gem_status = status
    state.sources[team] = hero
    register_listeners()
    if not start_audit(team, hero) or not audit_team(team) then
        clear_global_truesight(team, hero, status)
        return false, "tracker initialization failed"
    end
    return true, status
end

function LVGemTryAbsorb(keys)
    if not IsServer() then return end
    local hero, item = keys.caster, keys.ability
    if not valid(item) then return end
    if not item._lv_gem_callback_seen then
        item._lv_gem_callback_seen = true
        print("[lv_gem] automatic absorption callback reached")
    end
    if item._lv_gem_pending or item._lv_gem_consumed or not eligible(hero, item) then
        return
    end
    if hero._lv_gem_consumed or team_source(hero:GetTeamNumber()) then
        if not item._lv_gem_duplicate_reported then
            item._lv_gem_duplicate_reported = true
            print("[lv_gem] global True Sight already enabled; duplicate item retained")
        end
        return
    end

    -- Defer past inventory assembly / intrinsic modifier creation.
    item._lv_gem_pending = true
    hero:SetContextThink("lv_gem_absorb_" .. item:entindex(), function()
        if not valid(item) then return nil end
        item._lv_gem_pending = false
        if item._lv_gem_consumed or not eligible(hero, item)
            or hero._lv_gem_consumed or team_source(hero:GetTeamNumber()) then
            return nil
        end

        local ok, enabled, status_or_reason = pcall(enable_global_truesight, hero, item)
        if not ok or not enabled then
            if not item._lv_gem_error_reported then
                item._lv_gem_error_reported = true
                print("[lv_gem] global True Sight failed; item retained: "
                    .. tostring(status_or_reason or enabled))
            end
            return nil
        end

        -- TakeItem hides the consumed item instead of deleting it.  Keeping this
        -- data-driven ability entity alive gives the permanent HUD modifier a
        -- stable, client-known icon/tooltip provider without a Lua modifier.
        item._lv_gem_consumed = true
        local hidden_ok, hidden_error = pcall(function() hero:TakeItem(item) end)
        local still_equipped = false
        for slot = 0, 5 do
            if hero:GetItemInSlot(slot) == item then still_equipped = true end
        end
        if not hidden_ok or not valid(item) or still_equipped then
            item._lv_gem_consumed = nil
            clear_global_truesight(
                hero:GetTeamNumber(), hero, status_or_reason)
            print("[lv_gem] item hiding failed; absorption rolled back: "
                .. tostring(hidden_error))
            return nil
        end
        state.status_items[hero:GetTeamNumber()] = item
        print("[lv_gem] absorbed; global native True Sight enabled for team "
            .. tostring(hero:GetTeamNumber()))
        return nil
    end, 0.1)
end
