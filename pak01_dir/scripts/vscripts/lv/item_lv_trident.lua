-- The native Trident modifier continues to provide every stat that exists on
-- item_trident. The three additional stats are declared in the data-driven
-- controller modifier; this file only bridges the native modifier lifecycle.
local NATIVE_MODIFIER = "modifier_item_trident"

local function valid(entity)
    return entity ~= nil and not entity:IsNull()
end

local function remove_modifier_for_item(hero, item, modifier_name)
    for _, modifier in ipairs(hero:FindAllModifiersByName(modifier_name)) do
        if valid(modifier) and modifier:GetAbility() == item then
            modifier:Destroy()
            return
        end
    end
end

function LVTridentApplyModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then return end

    hero:AddNewModifier(hero, item, NATIVE_MODIFIER, {})
end

function LVTridentRemoveModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) then return end

    remove_modifier_for_item(hero, item, NATIVE_MODIFIER)
end
