-- Run from repository root with Lua 5.1/LuaJIT (or Lupa's lua51 runtime).
-- Engine doubles exercise control flow, NOT Dota visibility or event delivery.
local output = print
local server = true
local logs = {}
local listeners = {}
local entities = {}
local world = {}
local listen_fail = false
local scan_fail = false

function print(message) logs[#logs + 1] = message end
function IsServer() return server end
function UTIL_Remove(entity) entity.null = true end

DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_TEAM_NEUTRALS = 4
DOTA_TEAM_NOTEAM = 5
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_TARGET_ALL = 55
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 16
DOTA_UNIT_TARGET_FLAG_INVULNERABLE = 64
FIND_UNITS_EVERYWHERE = 99999
FIND_ANY_ORDER = 0

function ListenToGameEvent(name, callback, context)
    if listen_fail then error("simulated listener failure") end
    assert(name == "npc_spawned" or name == "npc_replaced")
    assert(context == nil)
    listeners[name] = callback
    return name == "npc_spawned" and 1 or 2
end

function EntIndexToHScript(index)
    return entities[index]
end

function FindUnitsInRadius(team, origin, cache, radius, team_filter, type_filter,
        flags, order, can_grow_cache)
    if scan_fail then error("simulated scan failure") end
    assert(team == DOTA_TEAM_GOODGUYS)
    assert(origin.x == 10 and cache == nil and radius == FIND_UNITS_EVERYWHERE)
    assert(team_filter == DOTA_UNIT_TARGET_TEAM_ENEMY)
    assert(type_filter == DOTA_UNIT_TARGET_ALL)
    assert(flags == DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES
        + DOTA_UNIT_TARGET_FLAG_INVULNERABLE)
    assert(order == FIND_ANY_ORDER and can_grow_cache == false)
    return world
end

dofile("game/dota_addons/overforged/scripts/vscripts/lv/item_lv_gem.lua")

local next_entindex = 100

local function reset_state()
    LV_GEM_GLOBAL_TRUESIGHT.sources = {}
    LV_GEM_GLOBAL_TRUESIGHT.audits = {}
    LV_GEM_GLOBAL_TRUESIGHT.status_items = {}
    LV_GEM_GLOBAL_TRUESIGHT.listeners_registered = false
    LV_GEM_GLOBAL_TRUESIGHT.listener_ids = {}
    listeners, entities, world, logs = {}, {}, {}, {}
    listen_fail, scan_fail, server = false, false, true
    next_entindex = 100
end

local function make_unit(team, name)
    next_entindex = next_entindex + 1
    local unit = {
        team = team,
        name = name or "unit",
        id = next_entindex,
        modifiers = {},
        add_count = 0,
    }
    entities[unit.id] = unit
    function unit:IsNull() return self.null or false end
    function unit:GetTeamNumber() return self.team end
    function unit:entindex() return self.id end
    function unit:FindModifierByNameAndCaster(modifier_name, caster)
        for _, modifier in ipairs(self.modifiers) do
            if not modifier.null and modifier.name == modifier_name
                and modifier.caster == caster then return modifier end
        end
        return nil
    end
    function unit:AddNewModifier(caster, ability, modifier_name, params)
        assert(ability == nil and modifier_name == "modifier_truesight")
        assert(params.duration == -1)
        if self.fail == "throw" then error("simulated native modifier failure") end
        if self.fail == "nil" then return nil end
        local modifier = { caster = caster, name = modifier_name, parent = self }
        function modifier:IsNull() return self.null or false end
        function modifier:Destroy() self.null = true end
        self.modifiers[#self.modifiers + 1] = modifier
        self.add_count = self.add_count + 1
        return modifier
    end
    return unit
end

local function make_hero(team)
    local hero = make_unit(team or DOTA_TEAM_GOODGUYS, "hero")
    hero.slots, hero.tasks = {}, {}
    hero.alive, hero.real, hero.taken = true, true, 0
    function hero:IsRealHero() return self.real end
    function hero:IsIllusion() return self.illusion or false end
    function hero:IsTempestDouble() return self.double or false end
    function hero:IsClone() return self.clone or false end
    function hero:IsAlive() return self.alive end
    function hero:GetItemInSlot(slot) return self.slots[slot] end
    function hero:GetAbsOrigin() return { x = 10, y = 20, z = 30 } end
    function hero:SetContextThink(name, callback, delay)
        if self.think_fail and string.sub(name, 1, 20) == "lv_gem_global_audit_" then
            error("simulated thinker failure")
        end
        assert(delay > 0)
        self.tasks[name] = { callback = callback, delay = delay }
    end
    function hero:run_tasks(prefix)
        local names = {}
        for name in pairs(self.tasks) do
            if not prefix or string.sub(name, 1, #prefix) == prefix then
                names[#names + 1] = name
            end
        end
        for _, name in ipairs(names) do
            local task = self.tasks[name]
            if task then
                local next_delay = task.callback()
                if next_delay == nil then self.tasks[name] = nil
                else task.delay = next_delay end
            end
        end
    end
    function hero:TakeItem(item)
        if self.take_fail == "throw" then error("simulated TakeItem failure") end
        if self.take_fail == "retain" then return end
        for slot, candidate in pairs(self.slots) do
            if candidate == item then self.slots[slot] = nil end
        end
        self.taken = self.taken + 1
    end
    return hero
end

local function make_item(hero, id, slot)
    local item = { owner = hero, id = id or 1 }
    function item:IsNull() return self.null or false end
    function item:GetCaster() return self.owner end
    function item:entindex() return self.id end
    function item:ApplyDataDrivenModifier(caster, target, modifier_name, params)
        assert(caster == hero and target == hero)
        assert(modifier_name == "modifier_item_lv_gem_consumed_status")
        assert(params.duration == -1)
        if self.status_fail == "throw" then error("simulated status failure") end
        if self.status_fail == "nil" then return nil end
        local modifier = {
            ability = self,
            caster = caster,
            name = modifier_name,
            parent = target,
        }
        function modifier:IsNull() return self.null or false end
        function modifier:Destroy() self.null = true end
        target.modifiers[#target.modifiers + 1] = modifier
        return modifier
    end
    hero.slots[slot or 0] = item
    return item
end

local function fixture()
    reset_state()
    local hero = make_hero()
    local item = make_item(hero)
    return hero, item
end

local function trigger(hero, item)
    LVGemTryAbsorb({ caster = hero, ability = item })
end

local function absorb(hero, item)
    trigger(hero, item)
    hero:run_tasks("lv_gem_absorb_")
end

local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    output("PASS: " .. name)
end

test("absorption scans existing heroes, summons and wards with native True Sight", function()
    local hero, item = fixture()
    local enemy_hero = make_unit(DOTA_TEAM_BADGUYS, "enemy hero")
    local wolf = make_unit(DOTA_TEAM_BADGUYS, "lycan wolf")
    local observer = make_unit(DOTA_TEAM_BADGUYS, "observer ward")
    local sentry = make_unit(DOTA_TEAM_BADGUYS, "sentry ward")
    local ally = make_unit(DOTA_TEAM_GOODGUYS, "ally")
    local neutral = make_unit(DOTA_TEAM_NEUTRALS, "neutral")
    world = { enemy_hero, wolf, observer, sentry, ally, neutral }

    absorb(hero, item)
    assert(hero._lv_gem_consumed and hero.taken == 1 and not item:IsNull())
    assert(hero.slots[0] == nil and item._lv_gem_consumed)
    local status = hero:FindModifierByNameAndCaster(
        "modifier_item_lv_gem_consumed_status", hero)
    assert(status and status.ability == item)
    assert(LV_GEM_GLOBAL_TRUESIGHT.sources[DOTA_TEAM_GOODGUYS] == hero)
    assert(LV_GEM_GLOBAL_TRUESIGHT.status_items[DOTA_TEAM_GOODGUYS] == item)
    assert(listeners.npc_spawned and listeners.npc_replaced)
    for _, unit in ipairs({ enemy_hero, wolf, observer, sentry }) do
        assert(unit.add_count == 1, unit.name)
        assert(unit.modifiers[1].name == "modifier_truesight")
    end
    assert(ally.add_count == 0 and neutral.add_count == 0)
end)

test("npc_spawned immediately covers later wolves, illusions and both ward types", function()
    local hero, item = fixture()
    absorb(hero, item)
    for _, name in ipairs({ "lycan wolf", "illusion", "observer ward", "sentry ward" }) do
        local unit = make_unit(DOTA_TEAM_BADGUYS, name)
        listeners.npc_spawned({ entindex = unit.id, is_respawn = 0 })
        assert(unit.add_count == 0, "spawn processing must defer until initialization")
        hero:run_tasks("lv_gem_spawn_")
        assert(unit.add_count == 1, name)
    end
end)

test("npc_replaced covers replacement entities", function()
    local hero, item = fixture()
    absorb(hero, item)
    local replacement = make_unit(DOTA_TEAM_BADGUYS, "replacement")
    listeners.npc_replaced({ old_entindex = 12, new_entindex = replacement.id })
    hero:run_tasks("lv_gem_spawn_")
    assert(replacement.add_count == 1)
end)

test("two-second audit catches missed units and does not duplicate modifiers", function()
    local hero, item = fixture()
    absorb(hero, item)
    local missed = make_unit(DOTA_TEAM_BADGUYS, "missed summon")
    world = { missed }
    hero:run_tasks("lv_gem_global_audit_")
    assert(missed.add_count == 1)
    hero:run_tasks("lv_gem_global_audit_")
    assert(missed.add_count == 1)
    local audit = hero.tasks["lv_gem_global_audit_2"]
    assert(audit and audit.delay == 2.0)
end)

test("temporary native modifier failure is retried by the audit", function()
    local hero, item = fixture()
    local unit = make_unit(DOTA_TEAM_BADGUYS, "temporarily failing unit")
    unit.fail = "nil"
    world = { unit }
    absorb(hero, item)
    assert(hero.taken == 1 and unit.add_count == 0)
    unit.fail = nil
    hero:run_tasks("lv_gem_global_audit_")
    assert(unit.add_count == 1)
end)

test("listener failure falls back to periodic audit", function()
    local hero, item = fixture()
    listen_fail = true
    absorb(hero, item)
    assert(hero.taken == 1 and not LV_GEM_GLOBAL_TRUESIGHT.listeners_registered)
    local unit = make_unit(DOTA_TEAM_BADGUYS, "fallback summon")
    world = { unit }
    hero:run_tasks("lv_gem_global_audit_")
    assert(unit.add_count == 1)
end)

test("tracker initialization failures retain the item and permit retry", function()
    for _, failure in ipairs({ "scan", "think" }) do
        local hero, item = fixture()
        if failure == "scan" then scan_fail = true else hero.think_fail = true end
        absorb(hero, item)
        assert(hero.taken == 0 and not item:IsNull() and not hero._lv_gem_consumed)
        assert(not hero:FindModifierByNameAndCaster(
            "modifier_item_lv_gem_consumed_status", hero))
        scan_fail, hero.think_fail = false, false
        absorb(hero, item)
        assert(hero.taken == 1, failure)
    end
end)

test("status icon failure retains the item without enabling True Sight", function()
    for _, failure in ipairs({ "throw", "nil" }) do
        local hero, item = fixture()
        local enemy = make_unit(DOTA_TEAM_BADGUYS, "enemy")
        world = { enemy }
        item.status_fail = failure
        absorb(hero, item)
        assert(hero.taken == 0 and hero.slots[0] == item)
        assert(not hero._lv_gem_consumed and enemy.add_count == 0)
        assert(LV_GEM_GLOBAL_TRUESIGHT.sources[DOTA_TEAM_GOODGUYS] == nil)
    end
end)

test("couriers, illusions, clones, Tempest Doubles and dead heroes cannot absorb", function()
    for _, field in ipairs({ "real", "illusion", "clone", "double", "alive" }) do
        local hero, item = fixture()
        hero[field] = not (field == "real" or field == "alive")
        absorb(hero, item)
        assert(hero.taken == 0 and not hero._lv_gem_consumed, field)
    end
end)

test("stash, backpack, neutral slot and ground are excluded but main inventory retries", function()
    for _, slot in ipairs({ 6, 9, 16, 99 }) do
        local hero, item = fixture()
        hero.slots[0], hero.slots[slot] = nil, item
        absorb(hero, item)
        assert(hero.taken == 0)
        hero.slots[slot], hero.slots[0] = nil, item
        absorb(hero, item)
        assert(hero.taken == 1)
    end
end)

test("deferred absorption revalidates death, transfer, slot and entity lifetime", function()
    for _, change in ipairs({ "death", "transfer", "slot", "item_null", "hero_null" }) do
        local hero, item = fixture()
        trigger(hero, item)
        if change == "death" then hero.alive = false end
        if change == "transfer" then item.owner = make_hero() end
        if change == "slot" then hero.slots[0] = nil end
        if change == "item_null" then item.null = true end
        if change == "hero_null" then hero.null = true end
        hero:run_tasks("lv_gem_absorb_")
        assert(hero.taken == 0 and not hero._lv_gem_consumed, change)
    end
end)

test("only one absorption per team and simultaneous duplicates are retained", function()
    local hero, first = fixture()
    local second = make_item(hero, 2, 1)
    trigger(hero, first)
    trigger(hero, second)
    hero:run_tasks("lv_gem_absorb_")
    assert(hero.taken == 1)
    assert((first._lv_gem_consumed == true) ~= (second._lv_gem_consumed == true))

    local ally = make_hero(DOTA_TEAM_GOODGUYS)
    local duplicate = make_item(ally, 3, 0)
    absorb(ally, duplicate)
    assert(ally.taken == 0 and not duplicate:IsNull())
end)

test("TakeItem failures roll back status and initial True Sight", function()
    for _, failure in ipairs({ "throw", "retain" }) do
        local hero, item = fixture()
        local enemy = make_unit(DOTA_TEAM_BADGUYS, "enemy")
        world = { enemy }
        hero.take_fail = failure
        absorb(hero, item)
        assert(hero.taken == 0 and hero.slots[0] == item)
        assert(not hero._lv_gem_consumed and not item._lv_gem_consumed)
        assert(not hero:FindModifierByNameAndCaster(
            "modifier_item_lv_gem_consumed_status", hero))
        assert(not enemy:FindModifierByNameAndCaster("modifier_truesight", hero))
        assert(LV_GEM_GLOBAL_TRUESIGHT.status_items[DOTA_TEAM_GOODGUYS] == nil)
    end
end)

test("client callback has no gameplay mutations", function()
    local hero, item = fixture()
    server = false
    absorb(hero, item)
    assert(hero.taken == 0 and not hero._lv_gem_consumed)
end)

print = output
print(tostring(passed) .. " Lua logic tests passed (engine doubles; not in-game verification).")
