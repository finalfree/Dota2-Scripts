-- Retain a hidden data-driven item as the native Hydra modifier's value source.
-- The permanent KV status supplies range only; Valve handles stats and attacks.
-- No client-side Lua modifier is linked or networked.
-- Engine registration omits "item_" here despite the C++ class being named
-- CDOTA_Modifier_Item_HydrasBreath. Verified in both server.dll and client.dll.
local NATIVE = "modifier_hydras_breath"
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
    -- Use the retained item, not a removable native modifier, for uniqueness.
    local item = hero._lv_hydras_breath_item
    return valid(item) and item._lv_hydras_breath_consumed
end

local function apply(hero, item, name)
    local existing = own_modifier(hero, item, name)
    if existing then return existing end
    local ok, modifier = pcall(function()
        if name == NATIVE then
            return hero:AddNewModifier(hero, item, name, { duration = -1 })
        end
        return item:ApplyDataDrivenModifier(hero, hero, name, { duration = -1 })
    end)
    if not ok then return nil end
    return own_modifier(hero, item, name) or modifier
end

local function rollback(hero, item)
    for _, name in ipairs({ NATIVE, STATUS }) do
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

-- KV status survives death. Restore only our native modifier once alive again.
function LVHydrasBreathEnsureActive(keys)
    if not IsServer() then return end
    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or not hero:IsAlive()
        or hero._lv_hydras_breath_item ~= item
        or not item._lv_hydras_breath_consumed then return end
    if not valid(apply(hero, item, NATIVE)) then
        if not item._lv_hydras_breath_restore_failed then
            print("[lv_hydras_breath] native restoration failed; will retry")
        end
        item._lv_hydras_breath_restore_failed = true
    else
        item._lv_hydras_breath_restore_failed = nil
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

        if not valid(apply(hero, item, NATIVE)) or not valid(apply(hero, item, STATUS)) then
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
        if not valid(apply(hero, item, NATIVE)) or not valid(apply(hero, item, STATUS)) then
            rollback(hero, item)
            print("[lv_hydras_breath] effects lost on hiding; rolled back")
            return nil
        end

        item._lv_hydras_breath_consumed = true
        hero._lv_hydras_breath_item = item
        state.items[hero:entindex()] = item
        print("[lv_hydras_breath] absorbed; permanent +800 range and native Hydra enabled")
        return nil
    end, 0.1)
end
