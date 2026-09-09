-- Engine doubles cover server control flow, not Dota's native modifier behavior.
local output = print
local server = true

function print(message) end
function IsServer() return server end

dofile("game/dota_addons/overforged/scripts/vscripts/lv/item_lv_radiance_shivas_guard.lua")

local function make_unit()
    local unit = { modifiers = {}, calls = {}, null = false }
    function unit:IsNull() return self.null end
    function unit:AddNewModifier(caster, ability, name, params)
        local modifier = { caster = caster, ability = ability, name = name, null = false }
        function modifier:IsNull() return self.null end
        function modifier:Destroy() self.null = true end
        function modifier:GetAbility() return self.ability end
        self.modifiers[#self.modifiers + 1] = modifier
        self.calls[#self.calls + 1] = { op = "add", name = name, params = params }
        return modifier
    end
    function unit:FindAllModifiersByName(name)
        local found = {}
        for _, modifier in ipairs(self.modifiers) do
            if modifier.name == name and not modifier.null then
                found[#found + 1] = modifier
            end
        end
        return found
    end
    function unit:live_names()
        local names = {}
        for _, modifier in ipairs(self.modifiers) do
            if not modifier.null then names[#names + 1] = modifier.name end
        end
        table.sort(names)
        return table.concat(names, ",")
    end
    return unit
end

local function make_item(owner)
    local item = { owner = owner, null = false }
    function item:IsNull() return self.null end
    function item:GetCaster() return self.owner end
    return item
end

local function fixture()
    server = true
    local hero = make_unit()
    return hero, make_item(hero)
end

local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    output("PASS: " .. name)
end

test("controller mounts both native passive packages once", function()
    local hero, item = fixture()
    LVRadianceShivasGuardApplyModifiers({ caster = hero, ability = item })
    LVRadianceShivasGuardApplyModifiers({ caster = hero, ability = item })
    assert(hero:live_names() == "modifier_item_radiance,modifier_item_shivas_guard")
    assert(#hero.modifiers == 2)
    for _, modifier in ipairs(hero.modifiers) do
        assert(modifier.caster == hero and modifier.ability == item)
    end
end)

test("controller removes only modifiers sourced from its own item", function()
    local hero, item = fixture()
    local decoy = make_item(hero)
    hero:AddNewModifier(hero, decoy, "modifier_item_radiance", {})
    hero:AddNewModifier(hero, decoy, "modifier_item_shivas_guard", {})
    LVRadianceShivasGuardApplyModifiers({ caster = hero, ability = item })
    LVRadianceShivasGuardRemoveModifiers({ caster = hero, ability = item })
    assert(hero:live_names() == "modifier_item_radiance,modifier_item_shivas_guard")
    for _, modifier in ipairs(hero.modifiers) do
        if not modifier.null then assert(modifier.ability == decoy) end
    end
end)

test("client calls, missing keys and mismatched owners do nothing", function()
    local hero, item = fixture()
    server = false
    LVRadianceShivasGuardApplyModifiers({ caster = hero, ability = item })
    assert(#hero.modifiers == 0 and #hero.calls == 0)
    server = true

    LVRadianceShivasGuardApplyModifiers({})
    item.owner = make_unit()
    LVRadianceShivasGuardApplyModifiers({ caster = hero, ability = item })
    assert(#hero.modifiers == 0 and #hero.calls == 0)
end)

print = output
print(tostring(passed) .. " Radiance-Shiva Lua logic tests passed (not in-game verification).")
