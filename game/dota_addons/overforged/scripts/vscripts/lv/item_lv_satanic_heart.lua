-- Keep all client-visible behavior in the data-driven item and the built-in
-- Satanic / Heart modifiers. Custom Lua modifiers in a dota_lv base override
-- cannot be resolved by ordinary custom-room clients and can crash them.
local NATIVE_MODIFIERS = {
    "modifier_item_satanic",
    "modifier_item_heart",
}

local NATIVE_UNHOLY_MODIFIER = "modifier_item_satanic_unholy"

-- Sound name read out of CDOTA_Item_Satanic::OnSpellStart in server.dll.
local UNHOLY_SOUND = "DOTA_Item.Satanic.Activate"

-- Vanilla Satanic's OnSpellStart does three things that a data-driven item
-- never runs: it applies a basic dispel to the caster, plays the activation
-- sound, then adds the buff. All three have to be re-implemented by
-- LVSatanicHeartUnholyRage below.
--
-- Purge's Lua signature, per the binding description in server.dll, is:
--   Purge(bool RemovePositiveBuffs, bool RemoveDebuffs,
--         bool BuffsCreatedThisFrameOnly, bool RemoveStuns, bool RemoveExceptions)
-- It is NOT the (bool, bool, handle, float, bool) form that older docs quote --
-- there the 4th argument is a float duration, and passing 0 for it would be
-- truthy in Lua and remove stuns, which a basic dispel must never do.
local function basic_dispel(hero)
    hero:Purge(false, true, false, false, false)
end

-- Mirrors the `unholy_duration` AbilityValues entry. CDOTA_Item_Satanic reads
-- that key inside OnSpellStart, which a data-driven item does not run, so the
-- duration has to be supplied explicitly here.
local DEFAULT_UNHOLY_DURATION = 6.0

local function valid(entity)
    return entity ~= nil and not entity:IsNull()
end

local function remove_modifier_for_item(hero, item, name)
    for _, modifier in ipairs(hero:FindAllModifiersByName(name)) do
        if valid(modifier) and modifier:GetAbility() == item then
            modifier:Destroy()
            return
        end
    end
end

local function unholy_duration(item)
    local duration = item:GetSpecialValueFor("unholy_duration")
    if duration ~= nil and duration > 0 then
        return duration
    end
    return DEFAULT_UNHOLY_DURATION
end

function LVSatanicHeartApplyModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then return end

    for _, name in ipairs(NATIVE_MODIFIERS) do
        hero:AddNewModifier(hero, item, name, {})
    end
end

function LVSatanicHeartRemoveModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) then return end

    for _, name in ipairs(NATIVE_MODIFIERS) do
        remove_modifier_for_item(hero, item, name)
    end
end

function LVSatanicHeartUnholyRage(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) then return end

    -- Order matches vanilla Satanic: the dispel fires on cast, before the
    -- lifesteal buff goes up.
    basic_dispel(hero)
    hero:EmitSound(UNHOLY_SOUND)

    hero:AddNewModifier(hero, item, NATIVE_UNHOLY_MODIFIER,
                        { duration = unholy_duration(item) })
end
