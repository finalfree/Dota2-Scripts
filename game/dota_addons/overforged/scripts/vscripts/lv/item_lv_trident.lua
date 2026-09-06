-- The native Trident modifier continues to provide every stat that exists on
-- item_trident. A separate value source gives the native Kaya/Sange modifier
-- only slow resistance and mana cost reduction, without duplicating stats.
-- No client-loaded Lua modifiers are used (also supports the base VPK target).
local NATIVE_MODIFIER = "modifier_item_trident"
local EXTRAS_MODIFIER = "modifier_item_kaya_and_sange"
local EXTRAS_ABILITY = "lv_trident_extras"

local function valid(entity)
    return entity ~= nil and not entity:IsNull()
end

local function find_modifier(hero, item, modifier_name)
    for _, modifier in ipairs(hero:FindAllModifiersByName(modifier_name)) do
        if valid(modifier) and modifier:GetAbility() == item then
            return modifier
        end
    end
end

local function remove_modifier_for_item(hero, item, modifier_name)
    local modifier = find_modifier(hero, item, modifier_name)
    if modifier then modifier:Destroy() end
end

local function release_extras(hero, state)
    if valid(state.source) then
        remove_modifier_for_item(hero, state.source, EXTRAS_MODIFIER)
        if state.created and hero:FindAbilityByName(EXTRAS_ABILITY) == state.source then
            hero:RemoveAbility(EXTRAS_ABILITY)
        end
    end
    state.source = nil
    state.created = false
end

local function sync_extras(hero, state)
    -- Controller callbacks can repeat. Track handles, not a numeric refcount.
    for item in pairs(state.items) do
        if not valid(item) or item:GetCaster() ~= hero then
            state.items[item] = nil
        end
    end
    if next(state.items) == nil then
        release_extras(hero, state)
        hero._lv_trident_extras = nil
        return
    end

    -- A hidden ability does not inherit inventory mute/backpack rules.
    -- Only one active Trident is required; extras do not stack per copy.
    local active = false
    for slot = 0, 5 do
        local item = hero:GetItemInSlot(slot)
        if item and state.items[item] and not item:IsMuted() and not hero:IsMuted() then
            active = true
            break
        end
    end
    if not active then
        if valid(state.source) then
            remove_modifier_for_item(hero, state.source, EXTRAS_MODIFIER)
        end
        return
    end
    -- Restore a native modifier lost on death only after the hero respawns.
    if not hero:IsAlive() then return end

    local ok, err = pcall(function()
        if not valid(state.source) then
            state.source = hero:FindAbilityByName(EXTRAS_ABILITY)
            state.created = not valid(state.source)
            if state.created then state.source = hero:AddAbility(EXTRAS_ABILITY) end
            assert(valid(state.source), "private ability unavailable")
            state.source:SetLevel(1)
            state.source:SetHidden(true)
            state.source:SetActivated(false)
        end
        if not find_modifier(hero, state.source, EXTRAS_MODIFIER) then
            local modifier = hero:AddNewModifier(hero, state.source, EXTRAS_MODIFIER, {})
            assert(valid(modifier), "native Kaya/Sange modifier unavailable")
        end
    end)
    if not ok and not state.failure_reported then
        -- Msg avoids the host FretBots print override. Do not fall back to the
        -- item as source: that would silently double strength/intellect/etc.
        Msg("[lv_trident] extras failed: " .. tostring(err) .. "\n")
        state.failure_reported = true
    elseif ok then
        state.failure_reported = false
    end
end

function LVTridentApplyModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then return end

    if not find_modifier(hero, item, NATIVE_MODIFIER) then
        hero:AddNewModifier(hero, item, NATIVE_MODIFIER, {})
    end
    local state = hero._lv_trident_extras
    if not state then
        state = { items = {} }
        hero._lv_trident_extras = state
    end
    state.items[item] = true
    sync_extras(hero, state)
end

function LVTridentRefreshModifiers(keys)
    if not IsServer() then return end
    local hero = keys and keys.caster
    if not valid(hero) then return end
    local state = hero._lv_trident_extras
    if not state then return end
    -- Each controller has a timer, but a hero needs only one scan per tick.
    local now = GameRules:GetGameTime()
    if state.last_check == now then return end
    state.last_check = now
    sync_extras(hero, state)
end

function LVTridentRemoveModifiers(keys)
    if not IsServer() then return end

    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(hero) then return end

    remove_modifier_for_item(hero, item, NATIVE_MODIFIER)
    local state = hero._lv_trident_extras
    if state and item then
        state.items[item] = nil
        sync_extras(hero, state)
    end
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
