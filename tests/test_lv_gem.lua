-- Run from repository root with Lua 5.1/LuaJIT (or Lupa's lua51 runtime).
-- Engine doubles exercise control flow, NOT Dota visibility or KV callbacks.
local output = print
local server = true
local BUFF = "modifier_lv_gem_consumed"
local logs = {}
function print(message) logs[#logs + 1] = message end
function IsServer() return server end
function class(base) return base end
LUA_MODIFIER_MOTION_NONE = 0
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_TARGET_ALL = 55
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 16
MODIFIER_PROPERTY_TOOLTIP = 999
function LinkLuaModifier(name, path, motion)
    assert(name == BUFF and path == "lv/modifier_lv_gem_consumed" and motion == 0)
end
function UTIL_Remove(entity) entity.null = true end
dofile("pak01_dir/scripts/vscripts/lv/modifier_lv_gem_consumed.lua")
dofile("pak01_dir/scripts/vscripts/lv/item_lv_gem.lua")

local function fixture()
    local hero = { slots = {}, tasks = {}, buffs = {}, alive = true, real = true, removed = 0 }
    function hero:IsNull() return self.null or false end
    function hero:IsRealHero() return self.real end
    function hero:IsIllusion() return self.illusion or false end
    function hero:IsTempestDouble() return self.double or false end
    function hero:IsClone() return self.clone or false end
    function hero:IsAlive() return self.alive end
    function hero:GetItemInSlot(slot) return self.slots[slot] end
    function hero:HasModifier(name) return self.buffs[name] ~= nil end
    function hero:SetContextThink(name, callback, delay)
        assert(delay > 0, "must defer until inventory assembly finishes")
        self.tasks[name] = callback
    end
    function hero:AddNewModifier(caster, ability, name, params)
        assert(caster == self and ability == nil and name == BUFF)
        if self.fail == "throw" then error("simulated unavailable modifier") end
        if self.fail == "nil" then return nil end
        local buff = setmetatable({ parent = self, stack = 0 }, { __index = modifier_lv_gem_consumed })
        function buff:IsNull() return self.null or false end
        function buff:GetParent() return self.parent end
        function buff:SetStackCount(value) self.stack = value end
        function buff:GetStackCount() return self.stack end
        function buff:SetHasCustomTransmitterData(enabled)
            assert(IsServer() and enabled)
            self.transmitted = self:AddCustomTransmitterData()
        end
        buff:OnCreated(params)
        if self.fail == "null" then buff.null = true; return buff end
        if self.fail ~= "not_attached" then self.buffs[name] = buff end
        return buff
    end
    function hero:RemoveItem(item)
        assert(self:HasModifier(BUFF), "must attach buff before consuming")
        for slot, candidate in pairs(self.slots) do
            if candidate == item then self.slots[slot] = nil end
        end
        self.removed = self.removed + 1
        if self.remove_destroys then item.null = true end
    end
    function hero:flush()
        local tasks = self.tasks
        self.tasks = {}
        for _, callback in pairs(tasks) do assert(callback() == nil) end
    end
    local function make_item(id, slot)
        local item = { owner = hero, radius = 1800, id = id }
        function item:IsNull() return self.null or false end
        function item:GetCaster() return self.owner end
        function item:entindex() return self.id end
        function item:GetSpecialValueFor(name) assert(name == "radius"); return self.radius end
        hero.slots[slot] = item
        return item
    end
    return hero, make_item(1, 0), make_item
end

local function trigger(hero, item) LVGemTryAbsorb({ caster = hero, ability = item }) end
local passed = 0
local function test(name, fn)
    server = true
    fn()
    passed = passed + 1
    output("PASS: " .. name)
end

test("automatic, deferred, idempotent absorption; buff independent of removed item", function()
    local hero, item = fixture()
    trigger(hero, item)
    trigger(hero, item)
    assert(hero.removed == 0 and not hero:HasModifier(BUFF))
    hero:flush()
    assert(hero.removed == 1 and item:IsNull() and hero.slots[0] == nil)
    local buff = hero.buffs[BUFF]
    item.radius = 1
    assert(buff:GetAuraRadius() == 1800 and buff:OnTooltip() == 1800)
    assert(buff:GetStackCount() == 0 and not buff:IsHidden())
    trigger(hero, item)
    hero:flush()
    assert(hero.removed == 1)
end)

test("radius reaches client tooltip without stack numbers or a live item", function()
    local hero, item = fixture()
    -- Non-default input ensures transmission does not hardcode the item KV value.
    item.radius = 1440
    trigger(hero, item)
    hero:flush()
    assert(item:IsNull())
    local source = hero.buffs[BUFF]
    assert(source:GetStackCount() == 0 and source.transmitted.radius == 1440)
    server = false
    local client = setmetatable({}, { __index = modifier_lv_gem_consumed })
    client:OnCreated({})
    assert(client:OnTooltip() == 0)
    client:HandleCustomTransmitterData(source.transmitted)
    assert(client:GetAuraRadius() == 1440 and client:OnTooltip() == 1440)
    assert(not client:IsHidden() and client:GetTexture() == "item_gem")
end)

test("couriers, illusions, clones, Tempest Doubles and dead heroes cannot absorb", function()
    for _, field in ipairs({ "real", "illusion", "clone", "double", "alive" }) do
        local hero, item = fixture()
        hero[field] = not (field == "real" or field == "alive")
        trigger(hero, item)
        hero:flush()
        assert(hero.removed == 0 and not hero:HasModifier(BUFF), field)
    end
end)

test("stash/backpack/neutral/ground excluded; automatic retry on entering main inventory", function()
    for _, slot in ipairs({ 6, 9, 16, 99 }) do
        local hero, item = fixture()
        hero.slots[0], hero.slots[slot] = nil, item
        trigger(hero, item)
        hero:flush()
        assert(hero.removed == 0)
        hero.slots[slot], hero.slots[0] = nil, item
        trigger(hero, item)
        hero:flush()
        assert(hero.removed == 1)
    end
end)

test("deferred callback revalidates death, transfer, slot and entity lifetime", function()
    for _, change in ipairs({ "death", "transfer", "slot", "item_null", "hero_null" }) do
        local hero, item = fixture()
        trigger(hero, item)
        if change == "death" then hero.alive = false end
        if change == "transfer" then item.owner = {} end
        if change == "slot" then hero.slots[0] = nil end
        if change == "item_null" then item.null = true end
        if change == "hero_null" then hero.null = true end
        hero:flush()
        assert(hero.removed == 0 and not hero:HasModifier(BUFF), change)
    end
end)

test("purchase while dead retries after respawn", function()
    local hero, item = fixture()
    hero.alive = false
    trigger(hero, item)
    hero:flush()
    assert(hero.removed == 0)
    hero.alive = true
    trigger(hero, item)
    hero:flush()
    assert(hero.removed == 1)
end)

test("duplicate effect, including between scheduling and execution, preserves item", function()
    for _, deferred in ipairs({ false, true }) do
        local hero, item = fixture()
        if deferred then trigger(hero, item) end
        hero.buffs[BUFF] = {}
        trigger(hero, item)
        hero:flush()
        assert(hero.removed == 0 and not item:IsNull())
    end
end)

test("two simultaneous items consume exactly one", function()
    local hero, first, make_item = fixture()
    local second = make_item(2, 1)
    trigger(hero, first)
    trigger(hero, second)
    hero:flush()
    assert(hero.removed == 1 and first:IsNull() ~= second:IsNull())
end)

test("modifier failures retain item and allow retry", function()
    for _, failure in ipairs({ "throw", "nil", "null", "not_attached" }) do
        local hero, item = fixture()
        hero.fail = failure
        trigger(hero, item)
        hero:flush()
        assert(hero.removed == 0 and not item:IsNull(), failure)
        hero.fail = nil
        trigger(hero, item)
        hero:flush()
        assert(hero.removed == 1, failure)
    end
end)

test("invalid radius does not destroy item", function()
    local hero, item = fixture()
    item.radius = 0
    trigger(hero, item)
    hero:flush()
    assert(hero.removed == 0 and not hero:HasModifier(BUFF))
end)

test("RemoveItem implementations that already delete the entity are supported", function()
    local hero, item = fixture()
    hero.remove_destroys = true
    trigger(hero, item)
    hero:flush()
    assert(hero.removed == 1 and item:IsNull())
end)

test("permanent aura pauses during death and resumes; no illusion/clone duplication", function()
    local hero, item = fixture()
    trigger(hero, item)
    hero:flush()
    local buff = hero.buffs[BUFF]
    assert(not buff:RemoveOnDeath() and not buff:IsPurgable() and not buff:IsPurgeException())
    assert(not buff:AllowIllusionDuplicate() and buff:IsAura())
    hero.alive = false
    assert(not buff:IsAura())
    hero.alive = true
    assert(buff:IsAura())
    for _, field in ipairs({ "illusion", "clone", "double" }) do
        hero[field] = true
        assert(not buff:IsAura())
        hero[field] = false
    end
    assert(buff:GetModifierAura() == "modifier_truesight")
    assert(buff:GetAuraSearchTeam() == DOTA_UNIT_TARGET_TEAM_ENEMY)
    assert(buff:GetAuraSearchType() == DOTA_UNIT_TARGET_ALL)
end)

test("client callback has no gameplay mutations", function()
    local hero, item = fixture()
    server = false
    trigger(hero, item)
    hero:flush()
    assert(hero.removed == 0 and not hero:HasModifier(BUFF))
end)

print = output
print(tostring(passed) .. " Lua logic tests passed (engine doubles; not in-game verification).")
