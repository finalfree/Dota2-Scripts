-- Retain the absorbed item as the permanent KV status value source.
-- Extra attacks use the engine attack pipeline; no client Lua modifier.
local STATUS = "modifier_item_lv_hydras_breath_consumed_status"

LV_HYDRAS_BREATH_STATE = LV_HYDRAS_BREATH_STATE or { items = {} }
local state = LV_HYDRAS_BREATH_STATE

local function valid(entity)
    return entity ~= nil and entity.IsNull ~= nil and not entity:IsNull()
end

local function own_modifier(hero, item, name)
    for _, modifier in ipairs(hero:FindAllModifiersByName(name)) do
        if valid(modifier) and modifier:GetAbility() == item then return modifier end
    end
    return nil
end

local function in_main_inventory(hero, item)
    for slot = 0, 5 do
        if hero:GetItemInSlot(slot) == item then return true end
    end
    return false
end

local function eligible(hero, item)
    return valid(hero) and valid(item) and item:GetCaster() == hero
        and hero:IsRealHero() and hero:IsAlive() and not hero:IsIllusion()
        and not hero:IsTempestDouble() and not (hero.IsClone and hero:IsClone())
        and in_main_inventory(hero, item)
end

local function already_consumed(hero)
    -- Use the retained item, not a permanent status, for uniqueness.
    local item = hero._lv_hydras_breath_item
    return valid(item) and item._lv_hydras_breath_consumed
end

local function apply(hero, item, name)
    local existing = own_modifier(hero, item, name)
    if existing then return existing end
    local ok, modifier = pcall(function()
        return item:ApplyDataDrivenModifier(hero, hero, name, { duration = -1 })
    end)
    if not ok then return nil end
    return own_modifier(hero, item, name) or modifier
end

local function rollback(hero, item)
    for _, name in ipairs({ STATUS }) do
        local modifier = own_modifier(hero, item, name)
        if modifier then modifier:Destroy() end
    end
    if valid(item) and not in_main_inventory(hero, item) then
        local ok = pcall(function() hero:AddItem(item) end)
        if not ok or not in_main_inventory(hero, item) then
            print("[lv_hydras_breath] ERROR: could not restore item to inventory")
        end
    end
end

function LVHydrasBreathTryAbsorb(keys)
    if not IsServer() then return end
    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(item) or item._lv_hydras_breath_pending
        or item._lv_hydras_breath_consumed or not eligible(hero, item)
        or already_consumed(hero) then return end

    -- Wait for recipe assembly and intrinsic modifier creation to finish.
    item._lv_hydras_breath_pending = true
    hero:SetContextThink("lv_hydras_breath_absorb_" .. item:entindex(), function()
        if not valid(item) then return nil end
        item._lv_hydras_breath_pending = false
        if item._lv_hydras_breath_consumed or not eligible(hero, item)
            or already_consumed(hero) then return nil end

        if not valid(apply(hero, item, STATUS)) then
            rollback(hero, item)
            if not item._lv_hydras_breath_init_failed then
                print("[lv_hydras_breath] initialization failed; item retained")
            end
            item._lv_hydras_breath_init_failed = true
            return nil
        end

        local ok = pcall(function() hero:TakeItem(item) end)
        if not ok or not valid(item) or in_main_inventory(hero, item) then
            rollback(hero, item)
            print("[lv_hydras_breath] item hiding failed; rolled back")
            return nil
        end

        -- TakeItem may remove item-sourced modifiers. Rebuild them from the
        -- retained entity and restore the item on any initialization failure.
        if not valid(apply(hero, item, STATUS)) then
            rollback(hero, item)
            print("[lv_hydras_breath] effects lost on hiding; rolled back")
            return nil
        end

        item._lv_hydras_breath_consumed = true
        hero._lv_hydras_breath_item = item
        state.items[hero:entindex()] = item
        print("[lv_hydras_breath] absorbed; permanent +800 range and ranged multi-attack enabled")
        return nil
    end, 0.1)
end

-- OnAttack runs when the attack is issued, not when a projectile lands.
-- Keep the guard through the entire synchronous PerformAttack call chain:
-- our extra attacks (and nested proc attacks) must not split recursively.
function LVHydrasBreathAttack(keys)
    if not IsServer() then return end
    local hero, item = keys and keys.caster, keys and keys.ability
    local primary = keys and keys.target
    if not valid(hero) or not valid(item) or not valid(primary)
        or (keys.attacker ~= nil and keys.attacker ~= hero)
        or hero._lv_hydras_breath_item ~= item
        or not item._lv_hydras_breath_consumed
        or hero._lv_hydras_breath_attacking
        or not hero:IsAlive() or not hero:IsRangedAttacker()
        or primary:GetTeamNumber() == hero:GetTeamNumber() then return end

    local radius = hero:Script_GetAttackRange()
        + item:GetSpecialValueFor("secondary_target_range_bonus")
    local limit = math.max(0, math.floor(item:GetSpecialValueFor("count")))
    if limit == 0 then return end
    local targets = FindUnitsInRadius(hero:GetTeamNumber(), hero:GetAbsOrigin(), nil,
        radius, DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE + DOTA_UNIT_TARGET_FLAG_NO_INVIS
            + DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES
            + DOTA_UNIT_TARGET_FLAG_NOT_ATTACK_IMMUNE,
        FIND_CLOSEST, false)

    hero._lv_hydras_breath_attacking = true
    local ok, err = pcall(function()
        local count = 0
        local seen = { [primary] = true }
        for _, target in ipairs(targets) do
            if count >= limit or not hero:IsAlive() or not hero:IsRangedAttacker() then break end
            if valid(target) and not seen[target] and target:IsAlive()
                and target:GetTeamNumber() ~= hero:GetTeamNumber()
                and not target:IsInvulnerable() and not target:IsAttackImmune()
                and not target:IsInvisible() and hero:CanEntityBeSeenByMyTeam(target)
                and (target:GetAbsOrigin() - hero:GetAbsOrigin()):Length2D() <= radius then
                seen[target] = true
                count = count + 1
                -- Orb/procs on; skip attack cooldown; respect invisibility;
                -- use real attack projectiles; neither fake nor never-miss.
                hero:PerformAttack(target, true, true, true, false, true, false, false)
            end
        end
    end)
    hero._lv_hydras_breath_attacking = nil
    if not ok then
        print("[lv_hydras_breath] multi-attack failed: " .. tostring(err))
    end
end
