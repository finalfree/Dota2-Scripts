-- The native Trident modifier continues to provide every stat that exists on
-- item_trident. This extra modifier supplies only the three new upgrade stats.
local NATIVE_MODIFIER = "modifier_item_trident"
local EXTRA_MODIFIER = "modifier_item_lv_trident_extras"

LinkLuaModifier(EXTRA_MODIFIER, "lv/item_lv_trident", LUA_MODIFIER_MOTION_NONE)

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
    hero:AddNewModifier(hero, item, EXTRA_MODIFIER, {})
end

function LVTridentRemoveModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) then return end

    remove_modifier_for_item(hero, item, NATIVE_MODIFIER)
    remove_modifier_for_item(hero, item, EXTRA_MODIFIER)
end

modifier_item_lv_trident_extras = class({})

function modifier_item_lv_trident_extras:IsHidden() return true end
function modifier_item_lv_trident_extras:IsPurgable() return false end
function modifier_item_lv_trident_extras:RemoveOnDeath() return false end

function modifier_item_lv_trident_extras:OnCreated()
    local item = self:GetAbility()
    if not valid(item) then return end

    self.slow_resistance = item:GetSpecialValueFor("slow_resistance")
    self.manacost_reduction = item:GetSpecialValueFor("manacost_reduction")
    self.cast_speed_pct = item:GetSpecialValueFor("cast_speed_pct")
end

function modifier_item_lv_trident_extras:OnRefresh()
    self:OnCreated()
end

function modifier_item_lv_trident_extras:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_SLOW_RESISTANCE_STACKING,
        MODIFIER_PROPERTY_MANACOST_PERCENTAGE_STACKING,
        MODIFIER_PROPERTY_CASTTIME_PERCENTAGE,
    }
end

function modifier_item_lv_trident_extras:GetModifierSlowResistance_Stacking()
    return self.slow_resistance or 0
end

function modifier_item_lv_trident_extras:GetModifierPercentageManacostStacking()
    return self.manacost_reduction or 0
end

function modifier_item_lv_trident_extras:GetModifierPercentageCasttime()
    return self.cast_speed_pct or 0
end
