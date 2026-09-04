-- Run from repository root with Lua 5.1/LuaJIT (or Lupa's lua51 runtime):
--   python -c "import sys; sys.path.insert(0, 'bin/lua-test-runtime'); \
--     from lupa.lua51 import LuaRuntime; \
--     LuaRuntime().execute(open('tests/test_lv_satanic_heart.lua', encoding='utf-8').read())"
-- Engine doubles exercise control flow, NOT Dota visibility or event delivery.
local output = print
local server = true

function print(message) end
function IsServer() return server end

dofile("game/dota_addons/overforged/scripts/vscripts/lv/item_lv_satanic_heart.lua")

local NATIVE_MODIFIERS = { "modifier_item_satanic", "modifier_item_heart" }
local UNHOLY = "modifier_item_satanic_unholy"

local function make_hero()
    local hero = { modifiers = {}, null = false, calls = {} }
    function hero:IsNull() return self.null end
    function hero:AddNewModifier(caster, ability, name, params)
        assert(caster == self, "native modifiers must be sourced from the owner")
        assert(ability ~= nil, "modifiers must be sourced from the item")
        local modifier = {
            name = name, ability = ability, caster = caster,
            duration = params and params.duration or nil, null = false,
        }
        function modifier:IsNull() return self.null end
        function modifier:Destroy() self.null = true end
        function modifier:GetAbility() return self.ability end
        self.modifiers[#self.modifiers + 1] = modifier
        self.calls[#self.calls + 1] = { op = "add", name = name }
        return modifier
    end
    function hero:Purge(...)
        self.calls[#self.calls + 1] = { op = "purge", args = { ... } }
    end
    function hero:EmitSound(name)
        self.calls[#self.calls + 1] = { op = "sound", name = name }
    end
    -- Index of the first recorded call of a given op, or nil.
    function hero:first(op)
        for index, call in ipairs(self.calls) do
            if call.op == op then return index, call end
        end
        return nil, nil
    end
    function hero:FindAllModifiersByName(name)
        local found = {}
        for _, modifier in ipairs(self.modifiers) do
            if modifier.name == name and not modifier.null then
                found[#found + 1] = modifier
            end
        end
        return found
    end
    function hero:live()
        local live = {}
        for _, modifier in ipairs(self.modifiers) do
            if not modifier.null then live[#live + 1] = modifier end
        end
        return live
    end
    function hero:live_names()
        local names = {}
        for _, modifier in ipairs(self:live()) do
            names[#names + 1] = modifier.name
        end
        table.sort(names)
        return table.concat(names, ",")
    end
    return hero
end

local function make_item(hero, values)
    local item = { owner = hero, null = false, values = values or {} }
    function item:IsNull() return self.null end
    function item:GetCaster() return self.owner end
    function item:GetSpecialValueFor(key) return self.values[key] end
    return item
end

local function fixture(values)
    server = true
    local hero = make_hero()
    local item = make_item(hero, values)
    return hero, item
end

local function keys(hero)
    return { caster = hero, ability = hero.item }
end

local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    output("PASS: " .. name)
end

test("OnCreated applies both native modifiers sourced from the item", function()
    local hero, item = fixture()
    LVSatanicHeartApplyModifiers({ caster = hero, ability = item })
    assert(#hero:live() == 2, hero:live_names())
    assert(hero:live_names() == "modifier_item_heart,modifier_item_satanic",
           hero:live_names())
    for _, modifier in ipairs(hero:live()) do
        assert(modifier.ability == item)
        assert(modifier.caster == hero)
    end
end)

test("OnDestroy removes only the modifiers that this item created", function()
    local hero, item = fixture()

    -- Decoys are registered FIRST on purpose: a "destroy the first name match"
    -- implementation would hit them instead of this item's own modifiers.
    local decoy = { name = "decoy item" }
    function decoy:IsNull() return false end
    function decoy:GetAbility() return decoy end
    for _, name in ipairs(NATIVE_MODIFIERS) do
        local other = { name = name, ability = decoy, null = false }
        function other:IsNull() return self.null end
        function other:Destroy() self.null = true end
        function other:GetAbility() return self.ability end
        hero.modifiers[#hero.modifiers + 1] = other
    end
    LVSatanicHeartApplyModifiers({ caster = hero, ability = item })
    assert(#hero:live() == 4)

    LVSatanicHeartRemoveModifiers({ caster = hero, ability = item })
    for _, modifier in ipairs(hero:live()) do
        assert(modifier.ability == decoy, "decoy modifier was destroyed: " .. modifier.name)
    end
    for _, modifier in ipairs(hero.modifiers) do
        if modifier.ability == item then
            assert(modifier:IsNull(), "own modifier survived: " .. modifier.name)
        end
    end
    assert(#hero:live() == 2, hero:live_names())
end)

test("OnSpellStart applies Unholy Rage with the duration from AbilityValues", function()
    -- Deliberately not 6.0: the fallback constant is also 6.0, so a value equal
    -- to it could not tell a real KV lookup apart from the fallback.
    local hero, item = fixture({ unholy_duration = 4.0 })
    LVSatanicHeartUnholyRage({ caster = hero, ability = item })
    local applied = hero:FindAllModifiersByName(UNHOLY)
    assert(#applied == 1)
    assert(applied[1].duration == 4.0, "expected 4.0, got " .. tostring(applied[1].duration))
    assert(applied[1].ability == item)
end)

test("a missing or zero unholy_duration falls back to the hardcoded default", function()
    for _, value in ipairs({ nil, 0, -1 }) do
        local hero, item = fixture({ unholy_duration = value })
        LVSatanicHeartUnholyRage({ caster = hero, ability = item })
        local applied = hero:FindAllModifiersByName(UNHOLY)
        assert(#applied == 1)
        assert(applied[1].duration == 6.0,
               "bad duration " .. tostring(value) .. " -> " .. tostring(applied[1].duration))
    end
end)

test("OnSpellStart applies a basic dispel before the buff", function()
    local hero, item = fixture()
    LVSatanicHeartUnholyRage({ caster = hero, ability = item })

    local purge_index, purge = hero:first("purge")
    local add_index = hero:first("add")
    assert(purge ~= nil, "no Purge call was made")
    assert(add_index ~= nil, "no buff was applied")

    -- Vanilla dispels on cast, before the lifesteal buff goes up. A late purge
    -- would leave the debuffs able to cancel the freshly applied buff.
    assert(purge_index < add_index,
           "purge ran after the buff (" .. purge_index .. " >= " .. add_index .. ")")

    -- Basic dispel = remove debuffs only. No positive buffs, no stuns, no
    -- exceptions, and not restricted to buffs created this frame.
    local expected = { false, true, false, false, false }
    assert(#purge.args == 5, "expected 5 Purge arguments, got " .. #purge.args)
    for i, want in ipairs(expected) do
        -- `== false` on purpose: 0 is truthy in Lua, so a caller using the old
        -- (..., float duration, bool) signature would silently remove stuns.
        assert(purge.args[i] == want,
               "Purge arg " .. i .. " = " .. tostring(purge.args[i]) .. ", want " .. tostring(want))
    end
end)

test("OnSpellStart plays the vanilla activation sound", function()
    local hero, item = fixture()
    LVSatanicHeartUnholyRage({ caster = hero, ability = item })
    local index, sound = hero:first("sound")
    assert(sound ~= nil, "no sound was emitted")
    assert(sound.name == "DOTA_Item.Satanic.Activate",
           "unexpected sound: " .. tostring(sound.name))
end)

test("client callbacks and missing keys never mutate state", function()
    local hero, item = fixture()
    server = false
    LVSatanicHeartApplyModifiers({ caster = hero, ability = item })
    LVSatanicHeartUnholyRage({ caster = hero, ability = item })
    assert(#hero:live() == 0)
    assert(#hero.calls == 0, "client ran server-only effects")
    server = true

    LVSatanicHeartApplyModifiers({})
    LVSatanicHeartUnholyRage({})
    assert(#hero:live() == 0)
    assert(#hero.calls == 0, "missing keys still triggered effects")
end)

test("a null caster or item is ignored instead of raising", function()
    local hero, item = fixture()
    LVSatanicHeartApplyModifiers({ caster = hero, ability = nil })
    LVSatanicHeartUnholyRage({ caster = hero, ability = nil })
    assert(#hero:live() == 0)
    assert(#hero.calls == 0)

    hero.null = true
    LVSatanicHeartApplyModifiers({ caster = hero, ability = item })
    LVSatanicHeartUnholyRage({ caster = hero, ability = item })
    assert(#hero:live() == 0)
    assert(#hero.calls == 0)
    hero.null = false

    item.null = true
    LVSatanicHeartApplyModifiers({ caster = hero, ability = item })
    LVSatanicHeartUnholyRage({ caster = hero, ability = item })
    assert(#hero:live() == 0)
    assert(#hero.calls == 0)
end)

test("the controller ignores an item whose caster is not the modifier owner", function()
    local hero, item = fixture()
    local impostor = make_hero()
    item.owner = impostor
    LVSatanicHeartApplyModifiers({ caster = hero, ability = item })
    assert(#hero:live() == 0, "modifier applied to a non-owner")
end)

print = output
print(tostring(passed) .. " Lua logic tests passed (engine doubles; not in-game verification).")
