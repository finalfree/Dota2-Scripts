-- Engine substitutes test lifecycle only, not native property calculations.
function IsServer() return true end
-- Actual engine-registered name; do not derive this from the item/class name.
local NATIVE = "modifier_item_aether_lens"
local CURIOSITY = "modifier_rubick_curiosity"
local STATUS = "modifier_item_lv_octarine_core_consumed_status"
local next_id = 1000
local function fixture()
    next_id = next_id + 1
    local hero = { id = next_id, slots = {}, mods = {}, tasks = {}, alive = true, taken = 0 }
    function hero:IsNull() return false end
    function hero:entindex() return self.id end
    function hero:IsRealHero() return not self.nonhero end
    function hero:IsAlive() return self.alive end
    function hero:IsIllusion() return self.illusion end
    function hero:IsTempestDouble() return self.double end
    function hero:IsClone() return self.clone end
    function hero:GetItemInSlot(slot) return self.slots[slot] end
    function hero:FindAllModifiersByName(name)
        local out = {}
        for _, m in ipairs(self.mods) do
            if not m:IsNull() and m.name == name then out[#out + 1] = m end
        end
        return out
    end
    local function modifier(item, name)
        if hero.fail == name or (hero.taken > 0 and hero.fail_after_take == name) then return nil end
        local m = { item = item, name = name }
        function m:IsNull() return self.destroyed end
        function m:GetAbility() return self.item end
        function m:Destroy() self.destroyed = true end
        hero.mods[#hero.mods + 1] = m
        return m
    end
    function hero:AddNewModifier(caster, item, name, args)
        assert(caster == self and (name == NATIVE or name == CURIOSITY)
            and args.duration == -1)
        return modifier(item, name)
    end
    function hero:SetContextThink(name, callback, delay)
        assert(delay == 0.1)
        self.tasks[#self.tasks + 1] = callback
    end
    function hero:run()
        local tasks = self.tasks
        self.tasks = {}
        for _, callback in ipairs(tasks) do callback() end
    end
    function hero:TakeItem(item)
        if self.fail_take then error("locked") end
        self.taken = self.taken + 1
        for slot = 0, 5 do
            if self.slots[slot] == item then self.slots[slot] = nil end
        end
        item.caster = nil
        -- Exercise the cleanup path, including rebuilding the KV status.
        for _, m in ipairs(self.mods) do
            if m.item == item then m:Destroy() end
        end
    end
    function hero:AddItem(item)
        self.slots[0] = item
        item.caster = self
    end
    function hero:item(slot)
        next_id = next_id + 1
        local item = { id = next_id, caster = self }
        function item:IsNull() return false end
        function item:entindex() return self.id end
        function item:GetCaster() return self.caster end
        function item:ApplyDataDrivenModifier(caster, target, name, args)
            assert(caster == hero and target == hero and name == STATUS and args.duration == -1)
            return modifier(self, name)
        end
        self.slots[slot or 0] = item
        return item
    end
    return hero, hero:item()
end

dofile("game/dota_addons/overforged/scripts/vscripts/lv/item_lv_octarine_core.lua")
local function absorb(hero, item)
    LVOctarineTryAbsorb({ caster = hero, ability = item })
    hero:run()
end

-- Successful absorption, no extra instances on repeated callbacks, and respawn.
do
    local hero, item = fixture()
    absorb(hero, item)
    assert(hero.slots[0] == nil and hero.taken == 1 and not item:IsNull())
    assert(item._lv_octarine_core_consumed and hero._lv_octarine_core_item == item)
    assert(LV_OCTARINE_STATE.items[hero.id] == item)
    assert(#hero:FindAllModifiersByName(NATIVE) == 1)
    assert(#hero:FindAllModifiersByName(CURIOSITY) == 1)
    assert(#hero:FindAllModifiersByName(STATUS) == 1)
    absorb(hero, item)
    assert(hero.taken == 1)
    hero:FindAllModifiersByName(NATIVE)[1]:Destroy()
    hero:FindAllModifiersByName(CURIOSITY)[1]:Destroy()
    hero.alive = false
    LVOctarineEnsureActive({ caster = hero, ability = item })
    assert(#hero:FindAllModifiersByName(NATIVE) == 0)
    hero.alive = true
    -- A missing native modifier must not allow a second permanent absorption.
    local duplicate = hero:item(1)
    absorb(hero, duplicate)
    assert(hero.slots[1] == duplicate and hero.taken == 1)
    for _ = 1, 3 do LVOctarineEnsureActive({ caster = hero, ability = item }) end
    assert(#hero:FindAllModifiersByName(NATIVE) == 1)
    assert(#hero:FindAllModifiersByName(CURIOSITY) == 1)
    assert(#hero:FindAllModifiersByName(STATUS) == 1)
end

-- Initialization failure, hiding failure, and failure after TakeItem all roll back.
for _, failure in ipairs({ "native", "curiosity", "status", "take",
        "late_native", "late_curiosity", "late_status" }) do
    local hero, item = fixture()
    if failure == "native" then hero.fail = NATIVE end
    if failure == "curiosity" then hero.fail = CURIOSITY end
    if failure == "status" then hero.fail = STATUS end
    if failure == "take" then hero.fail_take = true end
    if failure == "late_native" then hero.fail_after_take = NATIVE end
    if failure == "late_curiosity" then hero.fail_after_take = CURIOSITY end
    if failure == "late_status" then hero.fail_after_take = STATUS end
    absorb(hero, item)
    assert(hero.slots[0] == item and not item._lv_octarine_core_consumed, failure)
    assert(#hero:FindAllModifiersByName(NATIVE) == 0, failure)
    assert(#hero:FindAllModifiersByName(CURIOSITY) == 0, failure)
    assert(#hero:FindAllModifiersByName(STATUS) == 0, failure)
    assert(hero._lv_octarine_core_item == nil, failure)
end

-- Eligibility and changes during the recipe delay.
for _, flag in ipairs({ "nonhero", "illusion", "double", "clone", "dead", "stash", "backpack", "neutral", "moved", "transferred" }) do
    local hero, item = fixture()
    if flag == "dead" then hero.alive = false
    elseif flag == "stash" then hero.slots[0] = nil; hero.slots[9] = item
    elseif flag == "backpack" then hero.slots[0] = nil; hero.slots[6] = item
    elseif flag == "neutral" then hero.slots[0] = nil; hero.slots[16] = item
    elseif flag ~= "moved" and flag ~= "transferred" then hero[flag] = true end
    LVOctarineTryAbsorb({ caster = hero, ability = item })
    if flag == "moved" then hero.slots[0] = nil; hero.slots[9] = item end
    if flag == "transferred" then item.caster = {} end
    hero:run()
    assert(hero.taken == 0 and not item._lv_octarine_core_consumed, flag)
end

-- Two recipes queued in one frame: only the first may be consumed.
do
    local hero, item = fixture()
    local duplicate = hero:item(1)
    LVOctarineTryAbsorb({ caster = hero, ability = item })
    LVOctarineTryAbsorb({ caster = hero, ability = duplicate })
    hero:run()
    assert(hero.taken == 1 and hero.slots[1] == duplicate)
end
-- Restoration retries after a transient failure; other item sources survive rollback.
do
    local hero, item = fixture()
    absorb(hero, item)
    hero:FindAllModifiersByName(CURIOSITY)[1]:Destroy()
    hero.fail = CURIOSITY
    LVOctarineEnsureActive({ caster = hero, ability = item })
    assert(#hero:FindAllModifiersByName(CURIOSITY) == 0)
    assert(hero._lv_octarine_core_item == item)
    hero.fail = nil
    LVOctarineEnsureActive({ caster = hero, ability = item })
    assert(#hero:FindAllModifiersByName(CURIOSITY) == 1)
end
do
    local hero, item = fixture()
    local ordinary = hero:item(1)
    local lens = hero:AddNewModifier(hero, ordinary, NATIVE, { duration = -1 })
    local curiosity = hero:AddNewModifier(hero, ordinary, CURIOSITY, { duration = -1 })
    hero.fail = STATUS
    absorb(hero, item)
    assert(not lens:IsNull() and not curiosity:IsNull())
    assert(#hero:FindAllModifiersByName(NATIVE) == 1)
    assert(#hero:FindAllModifiersByName(CURIOSITY) == 1)
    assert(hero.slots[0] == item)
end
print("item_lv_octarine_core lifecycle tests passed")
