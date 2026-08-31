-- The native Trident modifier continues to provide every stat that exists on
-- item_trident. The data-driven controller supplies the additional stats and
-- dispatches landed attacks here for the custom pure-damage bonus.
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

function LVTridentApplyPureAttackDamage(keys)
    if not IsServer() then return end

    local hero = keys and keys.caster
    local attacker = keys and keys.attacker
    local target = keys and keys.target
    local item = keys and keys.ability
    if not valid(hero) or not valid(target) or not valid(item) then return end
    if attacker ~= nil and attacker ~= hero then return end
    if item:GetCaster() ~= hero then return end

    local damage = item:GetSpecialValueFor("pure_damage_attack")
    if damage <= 0 then return end

    ApplyDamage({
        victim = target,
        attacker = hero,
        damage = damage,
        damage_type = DAMAGE_TYPE_PURE,
        ability = item,
    })
end
