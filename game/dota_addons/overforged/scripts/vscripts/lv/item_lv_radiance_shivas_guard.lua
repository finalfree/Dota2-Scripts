-- Keep the fusion data-driven so one item can mount both engine-native passive
-- packages. The original Radiance toggle is intentionally absent: Burn stays on.
local NATIVE_MODIFIERS = {
    "modifier_item_radiance",
    "modifier_item_shivas_guard",
}

local function valid(entity)
    return entity ~= nil and not entity:IsNull()
end

local function has_modifier_for_item(hero, item, name)
    for _, modifier in ipairs(hero:FindAllModifiersByName(name)) do
        if valid(modifier) and modifier:GetAbility() == item then
            return true
        end
    end
    return false
end

local function remove_modifiers_for_item(hero, item, name)
    for _, modifier in ipairs(hero:FindAllModifiersByName(name)) do
        if valid(modifier) and modifier:GetAbility() == item then
            modifier:Destroy()
        end
    end
end

function LVRadianceShivasGuardApplyModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then return end

    for _, name in ipairs(NATIVE_MODIFIERS) do
        if not has_modifier_for_item(hero, item, name) then
            hero:AddNewModifier(hero, item, name, {})
        end
    end
end

function LVRadianceShivasGuardRemoveModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) then return end

    for _, name in ipairs(NATIVE_MODIFIERS) do
        remove_modifiers_for_item(hero, item, name)
    end
end
