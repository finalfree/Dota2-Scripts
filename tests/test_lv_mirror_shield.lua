-- Server-side control-flow test for item_lv_mirror_shield.lua.
-- Dota entities are mocks; this does not prove native modifier behavior.
function IsServer() return true end

local next_entindex = 500

local function new_modifier(ability, owner, name)
    local modifier = {
        ability = ability,
        owner = owner,
        name = name,
        destroyed = false,
    }
    function modifier:IsNull() return self.destroyed end
    function modifier:GetAbility() return self.ability end
    function modifier:Destroy()
        self.destroyed = true
    end
    return modifier
end

local function new_hero()
    next_entindex = next_entindex + 1
    local hero = {
        index = next_entindex,
        slots = {},
        modifiers = {},
        tasks = {},
        alive = true,
        taken = 0,
        added = 0,
    }
    function hero:IsNull() return false end
    function hero:entindex() return self.index end
    function hero:IsRealHero() return true end
    function hero:IsIllusion() return false end
    function hero:IsAlive() return self.alive end
    function hero:IsTempestDouble() return false end
    function hero:IsClone() return false end
    function hero:GetItemInSlot(slot) return self.slots[slot] end
    function hero:SetContextThink(name, callback, delay)
        assert(delay == 0.1)
        self.tasks[name] = callback
    end
    function hero:FindAllModifiersByName(name)
        local found = {}
        for _, modifier in ipairs(self.modifiers) do
            if modifier.name == name and not modifier:IsNull() then
                table.insert(found, modifier)
            end
        end
        return found
    end
    function hero:AddNewModifier(caster, ability, name, args)
        if self.fail_native then return nil end
        assert(caster == self and args.duration == -1)
        local modifier = new_modifier(ability, self, name)
        table.insert(self.modifiers, modifier)
        return modifier
    end
    function hero:TakeItem(item)
        if self.fail_take then error("take failed") end
        self.taken = self.taken + 1
        for slot = 0, 5 do
            if self.slots[slot] == item then self.slots[slot] = nil end
        end
        item.caster = nil
        if self.remove_native_on_take then
            for _, modifier in ipairs(self.modifiers) do
                if modifier.name == "modifier_item_mirror_shield" then
                    modifier:Destroy()
                end
            end
        end
    end
    function hero:AddItem(item)
        self.added = self.added + 1
        self.slots[0] = item
        item.caster = self
    end
    function hero:run_absorb()
        for name, callback in pairs(self.tasks) do
            if string.sub(name, 1, 24) == "lv_mirror_shield_absorb_" then
                self.tasks[name] = nil
                callback()
                return
            end
        end
        error("absorb task missing")
    end
    return hero
end

local function new_item(hero, slot)
    next_entindex = next_entindex + 1
    local item = { index = next_entindex, caster = hero, destroyed = false }
    function item:IsNull() return self.destroyed end
    function item:entindex() return self.index end
    function item:GetCaster() return self.caster end
    function item:ApplyDataDrivenModifier(caster, target, name, args)
        if self.fail_status then return nil end
        assert(caster == hero and target == hero and args.duration == -1)
        local modifier = new_modifier(self, hero, name)
        table.insert(hero.modifiers, modifier)
        return modifier
    end
    hero.slots[slot or 0] = item
    return item
end

dofile("game/dota_addons/overforged/scripts/vscripts/lv/item_lv_mirror_shield.lua")

-- Successful absorption retains the item entity, frees the slot and installs
-- both the native gameplay modifier and pure-KV status modifier.
do
    local hero = new_hero()
    hero.remove_native_on_take = true
    local item = new_item(hero)
    LVMirrorShieldTryAbsorb({ caster = hero, ability = item })
    hero:run_absorb()
    assert(hero.slots[0] == nil and hero.taken == 1)
    assert(item._lv_mirror_shield_consumed and not item:IsNull())
    assert(hero._lv_mirror_shield_item == item)
    assert(LV_MIRROR_SHIELD_STATE.items[hero:entindex()] == item)
    assert(#hero:FindAllModifiersByName("modifier_item_mirror_shield") == 1)
    assert(#hero:FindAllModifiersByName(
        "modifier_item_lv_mirror_shield_consumed_status") == 1)

    -- A second result is retained instead of stacking another permanent shield.
    local duplicate = new_item(hero, 1)
    LVMirrorShieldTryAbsorb({ caster = hero, ability = duplicate })
    assert(hero.slots[1] == duplicate and hero.taken == 1)
end

-- Native modifier initialization failure leaves the result in its slot.
do
    local hero = new_hero()
    hero.fail_native = true
    local item = new_item(hero)
    LVMirrorShieldTryAbsorb({ caster = hero, ability = item })
    hero:run_absorb()
    assert(hero.slots[0] == item and hero.taken == 0)
    assert(not item._lv_mirror_shield_consumed)
    assert(hero._lv_mirror_shield_item == nil)
end

-- A TakeItem failure rolls both permanent modifiers back and retains the item.
do
    local hero = new_hero()
    hero.fail_take = true
    local item = new_item(hero)
    LVMirrorShieldTryAbsorb({ caster = hero, ability = item })
    hero:run_absorb()
    assert(hero.slots[0] == item and not item._lv_mirror_shield_consumed)
    assert(#hero:FindAllModifiersByName("modifier_item_mirror_shield") == 0)
    assert(#hero:FindAllModifiersByName(
        "modifier_item_lv_mirror_shield_consumed_status") == 0)
end

print("item_lv_mirror_shield Lua tests passed")
