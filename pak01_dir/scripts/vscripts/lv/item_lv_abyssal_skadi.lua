-- The fusion is item_datadriven so it can install both passive packages. Keep
-- all client-visible modifiers engine-native: ordinary custom-room clients do
-- not have a reliable search path for custom Lua modifier classes in dota_lv.
local NATIVE_MODIFIERS = {
    "modifier_item_abyssal_blade",
    "modifier_item_skadi",
}

local ACTIVE_STUN_MODIFIER = "modifier_bashed"
local ACTIVE_SOUND = "DOTA_Item.AbyssalBlade.Activate"
local ACTIVE_START_PARTICLE = "particles/items_fx/abyssal_blink_start.vpcf"
local ACTIVE_TARGET_PARTICLE = "particles/items_fx/abyssal_blade.vpcf"
local DEFAULT_STUN_DURATION = 1.6

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

local function stun_duration(item)
    local duration = item:GetSpecialValueFor("stun_duration")
    if duration ~= nil and duration > 0 then
        return duration
    end
    return DEFAULT_STUN_DURATION
end

local function play_particle(path, owner)
    if ParticleManager == nil then return end
    local particle = ParticleManager:CreateParticle(
        path, PATTACH_ABSORIGIN_FOLLOW, owner)
    ParticleManager:ReleaseParticleIndex(particle)
end

function LVAbyssalSkadiApplyModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then return end

    for _, name in ipairs(NATIVE_MODIFIERS) do
        hero:AddNewModifier(hero, item, name, {})
    end
end

function LVAbyssalSkadiRemoveModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) then return end

    for _, name in ipairs(NATIVE_MODIFIERS) do
        remove_modifier_for_item(hero, item, name)
    end
end

function LVAbyssalSkadiOverwhelm(keys)
    if not IsServer() then return end

    local hero = keys and keys.caster
    local target = keys and keys.target
    local item = keys and keys.ability
    if not valid(hero) or not valid(target) or not valid(item)
        or item:GetCaster() ~= hero then return end

    -- CDOTA_Item_AbyssalBlade checks spell absorption before creating either
    -- particle, applying modifier_bashed, or playing the activation sound.
    if target:TriggerSpellAbsorb(item) then return end

    play_particle(ACTIVE_START_PARTICLE, hero)
    play_particle(ACTIVE_TARGET_PARTICLE, target)
    target:AddNewModifier(hero, item, ACTIVE_STUN_MODIFIER,
                          { duration = stun_duration(item) })
    target:EmitSound(ACTIVE_SOUND)
end
