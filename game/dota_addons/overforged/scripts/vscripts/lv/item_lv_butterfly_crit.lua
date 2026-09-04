-- Keep all client-visible behavior in the data-driven controller and the
-- built-in Daedalus modifier. Custom Lua modifiers in a dota_lv base override
-- cannot be resolved by ordinary custom-room clients and can crash them.
local NATIVE_CRIT_MODIFIER = "modifier_item_greater_crit"

local function valid(entity)
    return entity ~= nil and not entity:IsNull()
end

local function remove_modifier_for_item(hero, item)
    for _, modifier in ipairs(hero:FindAllModifiersByName(NATIVE_CRIT_MODIFIER)) do
        if valid(modifier) and modifier:GetAbility() == item then
            modifier:Destroy()
            return
        end
    end
end

function LVButterflyCritApplyModifier(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then return end

    -- Reads bonus_damage, crit_chance and crit_multiplier from this item.
    hero:AddNewModifier(hero, item, NATIVE_CRIT_MODIFIER, {})
end

function LVButterflyCritRemoveModifier(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) then return end

    remove_modifier_for_item(hero, item)
end
