-- Automatic absorption for Linken's Sphere + Lotus Orb fusion.
--
-- Gameplay uses Valve's native C++ modifier_item_mirror_shield. The custom
-- item entity is hidden rather than destroyed so the native modifier retains a
-- stable AbilityValues provider. No custom Lua modifier is linked or networked.
local NATIVE_MODIFIER = "modifier_item_mirror_shield"
local CONSUMED_STATUS = "modifier_item_lv_mirror_shield_consumed_status"

LV_MIRROR_SHIELD_STATE = LV_MIRROR_SHIELD_STATE or { items = {} }
local state = LV_MIRROR_SHIELD_STATE
state.items = state.items or {}

local function valid(entity)
    return entity ~= nil and entity.IsNull ~= nil and not entity:IsNull()
end

local function own_modifier(hero, item, name)
    if not valid(hero) or not hero.FindAllModifiersByName then return nil end
    for _, modifier in ipairs(hero:FindAllModifiersByName(name)) do
        if valid(modifier) and modifier.GetAbility and modifier:GetAbility() == item then
            return modifier
        end
    end
    return nil
end

local function destroy_own_modifier(hero, item, name)
    local modifier = own_modifier(hero, item, name)
    if modifier and modifier.Destroy then modifier:Destroy() end
end

local function in_main_inventory(hero, item)
    for slot = 0, 5 do
        if hero:GetItemInSlot(slot) == item then return true end
    end
    return false
end

local function eligible(hero, item)
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then
        return false
    end
    if not hero:IsRealHero() or hero:IsIllusion() or not hero:IsAlive()
        or hero:IsTempestDouble() or (hero.IsClone and hero:IsClone()) then
        return false
    end
    return in_main_inventory(hero, item)
end

local function permanent_effect_active(hero)
    local item = hero and hero._lv_mirror_shield_item
    return valid(item) and valid(own_modifier(hero, item, NATIVE_MODIFIER))
end

local function apply_native(hero, item)
    local existing = own_modifier(hero, item, NATIVE_MODIFIER)
    if existing then return existing end
    local ok, modifier = pcall(function()
        return hero:AddNewModifier(hero, item, NATIVE_MODIFIER, { duration = -1 })
    end)
    if not ok then return nil end
    return own_modifier(hero, item, NATIVE_MODIFIER) or modifier
end

local function apply_status(hero, item)
    local existing = own_modifier(hero, item, CONSUMED_STATUS)
    if existing then return existing end
    local ok, modifier = pcall(function()
        return item:ApplyDataDrivenModifier(
            hero, hero, CONSUMED_STATUS, { duration = -1 })
    end)
    if not ok then return nil end
    return own_modifier(hero, item, CONSUMED_STATUS) or modifier
end

local function restore_item(hero, item)
    if not valid(hero) or not valid(item) or in_main_inventory(hero, item) then
        return
    end
    pcall(function() hero:AddItem(item) end)
end

local function rollback(hero, item)
    destroy_own_modifier(hero, item, NATIVE_MODIFIER)
    destroy_own_modifier(hero, item, CONSUMED_STATUS)
    hero._lv_mirror_shield_item = nil
    if valid(hero) and hero.entindex then state.items[hero:entindex()] = nil end
    restore_item(hero, item)
end

function LVMirrorShieldTryAbsorb(keys)
    if not IsServer() then return end
    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(item) then return end

    if not item._lv_mirror_shield_callback_seen then
        item._lv_mirror_shield_callback_seen = true
        print("[lv_mirror_shield] automatic absorption callback reached")
    end
    if item._lv_mirror_shield_pending or item._lv_mirror_shield_consumed
        or not eligible(hero, item) then
        return
    end
    if permanent_effect_active(hero) then
        if not item._lv_mirror_shield_duplicate_reported then
            item._lv_mirror_shield_duplicate_reported = true
            print("[lv_mirror_shield] permanent effect already active; duplicate item retained")
        end
        return
    end

    -- Defer past recipe assembly and intrinsic data-driven modifier creation.
    item._lv_mirror_shield_pending = true
    hero:SetContextThink("lv_mirror_shield_absorb_" .. item:entindex(), function()
        if not valid(item) then return nil end
        item._lv_mirror_shield_pending = false
        if item._lv_mirror_shield_consumed or not eligible(hero, item)
            or permanent_effect_active(hero) then
            return nil
        end

        local native = apply_native(hero, item)
        local status = apply_status(hero, item)
        if not valid(native) or not valid(status) then
            rollback(hero, item)
            if not item._lv_mirror_shield_error_reported then
                item._lv_mirror_shield_error_reported = true
                print("[lv_mirror_shield] native modifier initialization failed; item retained")
            end
            return nil
        end

        local hidden_ok, hidden_error = pcall(function() hero:TakeItem(item) end)
        if not hidden_ok or not valid(item) or in_main_inventory(hero, item) then
            rollback(hero, item)
            print("[lv_mirror_shield] item hiding failed; absorption rolled back: "
                .. tostring(hidden_error))
            return nil
        end

        -- Some item modifiers are removed automatically by TakeItem. Reapply
        -- from the retained, client-known item entity if that happened.
        native = apply_native(hero, item)
        status = apply_status(hero, item)
        if not valid(native) or not valid(status) then
            rollback(hero, item)
            print("[lv_mirror_shield] permanent modifier did not survive item hiding; rolled back")
            return nil
        end

        item._lv_mirror_shield_consumed = true
        hero._lv_mirror_shield_item = item
        state.items[hero:entindex()] = item
        print("[lv_mirror_shield] absorbed; permanent native Mirror Shield enabled with zero cooldown")
        return nil
    end, 0.1)
end
