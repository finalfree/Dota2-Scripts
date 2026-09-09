-- Like the upgraded Gem, TakeItem frees the slot while retaining the value source.
-- KV supplies health and cooldown reduction; native Lens supplies cast range,
-- mana and mana regeneration. Rubick's native Curiosity modifier supplies AoE
-- and buff/debuff duration amplification from its built-in base stack.
-- All engine modifier names were checked in server.dll and client.dll.
local CURIOSITY = "modifier_rubick_curiosity"
local NATIVES = { "modifier_item_aether_lens", CURIOSITY }
local STATUS = "modifier_item_lv_octarine_core_consumed_status"

LV_OCTARINE_STATE = LV_OCTARINE_STATE or { items = {} }
local state = LV_OCTARINE_STATE

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
    local item = hero._lv_octarine_core_item
    return valid(item) and item._lv_octarine_core_consumed
end

local function apply(hero, item, name)
    local existing = own_modifier(hero, item, name)
    if existing then return existing end
    local ok, modifier = pcall(function()
        local applied
        if name ~= STATUS then
            applied = hero:AddNewModifier(hero, item, name, { duration = -1 })
        else
            applied = item:ApplyDataDrivenModifier(hero, hero, name, { duration = -1 })
        end
        return applied
    end)
    if not ok then return nil end
    return own_modifier(hero, item, name)
end

local function rollback(hero, item)
    for _, name in ipairs({ NATIVES[1], NATIVES[2], STATUS }) do
        local modifier = own_modifier(hero, item, name)
        if modifier then modifier:Destroy() end
    end
    if valid(item) and not in_main_inventory(hero, item) then
        local ok = pcall(function() hero:AddItem(item) end)
        if not ok or not in_main_inventory(hero, item) then
            print("[lv_octarine_core] ERROR: could not restore item to inventory")
        end
    end
end

local function apply_all(hero, item)
    for _, name in ipairs({ NATIVES[1], NATIVES[2], STATUS }) do
        if not valid(apply(hero, item, name)) then return false end
    end
    return true
end

-- KV status survives death. Restore our native modifiers once alive again.
function LVOctarineEnsureActive(keys)
    if not IsServer() then return end
    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or not hero:IsAlive()
        or hero._lv_octarine_core_item ~= item
        or not item._lv_octarine_core_consumed then return end
    if not apply_all(hero, item) then
        if not item._lv_octarine_core_restore_failed then
            print("[lv_octarine_core] native restoration failed; will retry")
        end
        item._lv_octarine_core_restore_failed = true
    else
        item._lv_octarine_core_restore_failed = nil
    end
end

function LVOctarineTryAbsorb(keys)
    if not IsServer() then return end
    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(item) or item._lv_octarine_core_pending
        or item._lv_octarine_core_consumed or not eligible(hero, item)
        or already_consumed(hero) then return end

    -- Wait for recipe assembly and intrinsic modifier creation to finish.
    item._lv_octarine_core_pending = true
    hero:SetContextThink("lv_octarine_core_absorb_" .. item:entindex(), function()
        if not valid(item) then return nil end
        item._lv_octarine_core_pending = false
        if item._lv_octarine_core_consumed or not eligible(hero, item)
            or already_consumed(hero) then return nil end

        if not apply_all(hero, item) then
            rollback(hero, item)
            if not item._lv_octarine_core_init_failed then
                print("[lv_octarine_core] initialization failed; item retained")
            end
            item._lv_octarine_core_init_failed = true
            return nil
        end

        local ok = pcall(function() hero:TakeItem(item) end)
        if not ok or not valid(item) or in_main_inventory(hero, item) then
            rollback(hero, item)
            print("[lv_octarine_core] item hiding failed; rolled back")
            return nil
        end

        -- TakeItem may remove item-sourced modifiers. Rebuild them from the
        -- retained entity and restore the item on any initialization failure.
        if not apply_all(hero, item) then
            rollback(hero, item)
            print("[lv_octarine_core] effects lost on hiding; rolled back")
            return nil
        end

        item._lv_octarine_core_consumed = true
        hero._lv_octarine_core_item = item
        state.items[hero:entindex()] = item
        print("[lv_octarine_core] absorbed; permanent 80% cooldown reduction, +600 cast range, +400 AoE and +20 mana regen enabled")
        return nil
    end, 0.1)
end
