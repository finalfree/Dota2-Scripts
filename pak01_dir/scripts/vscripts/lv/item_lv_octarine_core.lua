-- Health and cooldown use the data-driven Properties block.  The native Aether
-- Lens modifier supplies this item's mana, mana regeneration and cast range;
-- data-driven MODIFIER_PROPERTY_CAST_RANGE_BONUS is unsupported.
local NATIVE_RANGE_MODIFIER = "modifier_item_aether_lens"

local function valid(entity)
    return entity ~= nil and not entity:IsNull()
end

function LVOctarineApplyNativeRange(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then return end

    -- The native modifier reads bonus_mana, bonus_mana_regen and
    -- cast_range_bonus from this item's AbilityValues and participates in the
    -- engine's normal client HUD refresh lifecycle.
    hero:AddNewModifier(hero, item, NATIVE_RANGE_MODIFIER, {})
end

function LVOctarineRemoveNativeRange(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) then return end

    -- Remove only the native modifier attached by this exact item instance.
    for _, modifier in ipairs(hero:FindAllModifiersByName(NATIVE_RANGE_MODIFIER)) do
        if valid(modifier) and modifier:GetAbility() == item then
            modifier:Destroy()
            return
        end
    end
end
