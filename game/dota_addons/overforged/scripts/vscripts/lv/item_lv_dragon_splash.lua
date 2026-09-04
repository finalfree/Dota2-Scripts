-- Automatic absorption for Battle Fury + upgrade scroll.
--
-- The private data-driven ability is added to the absorbing hero and hidden.
-- Its AbilityValues provide the source for Valve's native
-- modifier_black_dragon_splash_attack.  No custom Lua modifier is linked or
-- networked, and the official Black Dragon ability remains unchanged.
local SKILL_NAME = "lv_black_dragon_splash_attack"
local NATIVE_MODIFIER = "modifier_black_dragon_splash_attack"
local STATUS_MODIFIER = "modifier_lv_black_dragon_splash_status"

local function valid(entity)
    return entity ~= nil and entity.IsNull ~= nil and not entity:IsNull()
end

local function in_main_inventory(hero, item)
    for slot = 0, 5 do
        if hero:GetItemInSlot(slot) == item then return true end
    end
    return false
end

local function eligible(hero, item)
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then
        return false
    end
    if not hero:IsRealHero() or hero:IsIllusion() or not hero:IsAlive()
        or hero:IsTempestDouble() or (hero.IsClone and hero:IsClone()) then
        return false
    end
    return in_main_inventory(hero, item)
end

local function own_modifier(hero, ability, name)
    if not valid(hero) or not hero.FindAllModifiersByName then return nil end
    for _, modifier in ipairs(hero:FindAllModifiersByName(name)) do
        if valid(modifier) and modifier.GetAbility
            and modifier:GetAbility() == ability then
            return modifier
        end
    end
    return nil
end

local function find_skill(hero)
    local skill = hero._lv_dragon_splash_skill
    if valid(skill) then return skill end
    if hero.FindAbilityByName then
        local ok, found = pcall(function() return hero:FindAbilityByName(SKILL_NAME) end)
        if ok and valid(found) then return found end
    end
    return nil
end

local function add_private_skill(hero)
    local existing = find_skill(hero)
    if existing then return existing, false end
    if not hero.AddAbility then return nil, false end
    local ok, skill = pcall(function() return hero:AddAbility(SKILL_NAME) end)
    if not ok or not valid(skill) then return nil, false end

    if skill.SetLevel then skill:SetLevel(1) end
    if skill.SetHidden then skill:SetHidden(true) end
    if skill.SetActivated then skill:SetActivated(false) end
    hero._lv_dragon_splash_skill = skill
    return skill, true
end

local function remove_private_skill(hero, skill, created)
    if not valid(hero) then return end
    if created and hero.RemoveAbility then
        pcall(function() hero:RemoveAbility(SKILL_NAME) end)
    end
    if hero._lv_dragon_splash_skill == skill then
        hero._lv_dragon_splash_skill = nil
    end
end

local function apply_status(hero, skill)
    local existing = own_modifier(hero, skill, STATUS_MODIFIER)
    if existing then return existing end
    if not skill.ApplyDataDrivenModifier then return nil end
    local ok = pcall(function()
        skill:ApplyDataDrivenModifier(hero, hero, STATUS_MODIFIER, { duration = -1 })
    end)
    if not ok then return nil end
    return own_modifier(hero, skill, STATUS_MODIFIER)
end

-- The status modifier survives death, but the engine-native Black Dragon
-- modifier does not on every build. Its interval callback restores the native
-- effect after respawn while keeping the same private ability/item as source.
function LVDragonSplashEnsureActive(keys)
    if not IsServer() then return end
    local hero = keys and (keys.caster or keys.target)
    local source = keys and keys.ability
    if not valid(hero) or not hero.IsAlive or not hero:IsAlive() then return end
    if not valid(source) then source = find_skill(hero) end
    if not valid(source) then source = hero._lv_dragon_splash_item end
    if not valid(source) or own_modifier(hero, source, NATIVE_MODIFIER) then return end

    local ok, result = pcall(function()
        return hero:AddNewModifier(hero, source, NATIVE_MODIFIER, { duration = -1 })
    end)
    local restored = own_modifier(hero, source, NATIVE_MODIFIER) or (ok and result or nil)
    if valid(restored) and not hero._lv_dragon_splash_restore_reported then
        hero._lv_dragon_splash_restore_reported = true
        print("[lv_dragon_splash] restored native splash modifier after respawn")
    end
end

local function rollback(hero, source, skill, created)
    local native = own_modifier(hero, source, NATIVE_MODIFIER)
    if native and native.Destroy then native:Destroy() end
    local status = own_modifier(hero, source, STATUS_MODIFIER)
    if status and status.Destroy then status:Destroy() end
    remove_private_skill(hero, skill, created)
end

function LVDragonSplashTryAbsorb(keys)
    if not IsServer() then return end
    local hero, item = keys and keys.caster, keys and keys.ability
    if not valid(item) then return end

    if not item._lv_dragon_splash_callback_seen then
        item._lv_dragon_splash_callback_seen = true
        print("[lv_dragon_splash] automatic absorption callback reached")
    end
    if item._lv_dragon_splash_pending or item._lv_dragon_splash_consumed
        or not eligible(hero, item) then
        return
    end

    local existing = find_skill(hero)
    if (existing and own_modifier(hero, existing, NATIVE_MODIFIER))
        or (hero._lv_dragon_splash_item
            and own_modifier(hero, hero._lv_dragon_splash_item, NATIVE_MODIFIER)) then
        if not item._lv_dragon_splash_duplicate_reported then
            item._lv_dragon_splash_duplicate_reported = true
            print("[lv_dragon_splash] permanent effect already active; duplicate item retained")
        end
        return
    end

    -- Defer past recipe assembly and intrinsic data-driven modifier creation.
    item._lv_dragon_splash_pending = true
    hero:SetContextThink("lv_dragon_splash_absorb_" .. item:entindex(), function()
        if not valid(item) then return nil end
        item._lv_dragon_splash_pending = false
        if item._lv_dragon_splash_consumed or not eligible(hero, item) then
            return nil
        end

        local skill, created = add_private_skill(hero)
        local source = valid(skill) and skill or item
        local native = own_modifier(hero, source, NATIVE_MODIFIER)
        if not native then
            local ok, result = pcall(function()
                return hero:AddNewModifier(hero, source, NATIVE_MODIFIER, { duration = -1 })
            end)
            native = own_modifier(hero, source, NATIVE_MODIFIER) or (ok and result or nil)
        end
        local status = apply_status(hero, source)

        -- Some builds expose the native modifier but only accept the item
        -- entity as its AbilityValues provider.  Retry once with the retained
        -- item before giving up on the private-skill path.
        if (not valid(native) or not valid(status)) and source ~= item then
            rollback(hero, source, skill, created)
            skill, created = nil, false
            source = item
            local ok, result = pcall(function()
                return hero:AddNewModifier(hero, source, NATIVE_MODIFIER, { duration = -1 })
            end)
            native = own_modifier(hero, source, NATIVE_MODIFIER) or (ok and result or nil)
            status = apply_status(hero, source)
        end
        if not valid(native) or not valid(status) then
            rollback(hero, source, skill, created)
            if not item._lv_dragon_splash_error_reported then
                item._lv_dragon_splash_error_reported = true
                print("[lv_dragon_splash] native splash initialization failed; item retained")
            end
            return nil
        end

        local hidden_ok, hidden_error = pcall(function() hero:TakeItem(item) end)
        local still_equipped = in_main_inventory(hero, item)
        if not hidden_ok or not valid(item) or still_equipped then
            rollback(hero, source, skill, created)
            print("[lv_dragon_splash] item hiding failed; absorption rolled back: "
                .. tostring(hidden_error))
            return nil
        end

        -- Removing an item can also remove modifiers whose Ability is that
        -- item.  The fallback provider is intentionally retained hidden, so
        -- rebuild its native/status modifiers if the engine cleaned them up.
        if source == item then
            native = own_modifier(hero, source, NATIVE_MODIFIER)
            if not native then
                local ok, result = pcall(function()
                    return hero:AddNewModifier(hero, source, NATIVE_MODIFIER, { duration = -1 })
                end)
                native = own_modifier(hero, source, NATIVE_MODIFIER) or (ok and result or nil)
            end
            status = apply_status(hero, source)
            if not valid(native) or not valid(status) then
                rollback(hero, source, skill, created)
                print("[lv_dragon_splash] fallback provider did not survive item hiding")
                return nil
            end
        end

        item._lv_dragon_splash_consumed = true
        if source == item then hero._lv_dragon_splash_item = item end
        print("[lv_dragon_splash] absorbed; private 500-radius splash enabled")
        return nil
    end, 0.1)
end
