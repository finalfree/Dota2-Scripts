-- Run from repository root with Lua 5.1/LuaJIT (or Lupa's lua51 runtime).
-- Engine doubles exercise server control flow, not Dota modifier behavior.
local output = print
local server = true
local particles = {}

function print(message) end
function IsServer() return server end
PATTACH_ABSORIGIN_FOLLOW = 1
ParticleManager = {}
function ParticleManager:CreateParticle(path, attach, owner)
    particles[#particles + 1] = { path = path, attach = attach, owner = owner }
    return #particles
end
function ParticleManager:ReleaseParticleIndex(index)
    particles[index].released = true
end

dofile("pak01_dir/scripts/vscripts/lv/item_lv_abyssal_skadi.lua")

local NATIVE_MODIFIERS = {
    "modifier_item_abyssal_blade",
    "modifier_item_skadi",
}

local function make_unit()
    local unit = { modifiers = {}, calls = {}, null = false, absorb = false }
    function unit:IsNull() return self.null end
    function unit:AddNewModifier(caster, ability, name, params)
        local modifier = {
            caster = caster, ability = ability, name = name,
            duration = params and params.duration, null = false,
        }
        function modifier:IsNull() return self.null end
        function modifier:Destroy() self.null = true end
        function modifier:GetAbility() return self.ability end
        self.modifiers[#self.modifiers + 1] = modifier
        self.calls[#self.calls + 1] = { op = "add", name = name }
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
    function unit:TriggerSpellAbsorb(ability)
        self.calls[#self.calls + 1] = { op = "absorb", ability = ability }
        return self.absorb
    end
    function unit:EmitSound(name)
        self.calls[#self.calls + 1] = { op = "sound", name = name }
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

local function make_item(owner, values)
    local item = { owner = owner, values = values or {}, null = false }
    function item:IsNull() return self.null end
    function item:GetCaster() return self.owner end
    function item:GetSpecialValueFor(key) return self.values[key] end
    return item
end

local function fixture(values)
    particles = {}
    server = true
    local hero, target = make_unit(), make_unit()
    local item = make_item(hero, values)
    return hero, target, item
end

local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    output("PASS: " .. name)
end

test("controller applies both engine-native passive modifiers", function()
    local hero, _, item = fixture()
    LVAbyssalSkadiApplyModifiers({ caster = hero, ability = item })
    assert(hero:live_names() ==
           "modifier_item_abyssal_blade,modifier_item_skadi", hero:live_names())
    for _, modifier in ipairs(hero.modifiers) do
        assert(modifier.caster == hero)
        assert(modifier.ability == item)
    end
end)

test("controller removes only modifiers sourced from its own item", function()
    local hero, _, item = fixture()
    local decoy = make_item(hero)
    for _, name in ipairs(NATIVE_MODIFIERS) do
        hero:AddNewModifier(hero, decoy, name, {})
    end
    LVAbyssalSkadiApplyModifiers({ caster = hero, ability = item })
    LVAbyssalSkadiRemoveModifiers({ caster = hero, ability = item })
    assert(hero:live_names() ==
           "modifier_item_abyssal_blade,modifier_item_skadi", hero:live_names())
    for _, modifier in ipairs(hero.modifiers) do
        if not modifier.null then assert(modifier.ability == decoy) end
    end
end)

test("Overwhelm checks spell absorption before producing effects", function()
    local hero, target, item = fixture({ stun_duration = 1.6 })
    target.absorb = true
    LVAbyssalSkadiOverwhelm({ caster = hero, target = target, ability = item })
    assert(#target.calls == 1 and target.calls[1].op == "absorb")
    assert(#target.modifiers == 0)
    assert(#particles == 0)
end)

test("Overwhelm applies native bash, particles and vanilla sound", function()
    local hero, target, item = fixture({ stun_duration = 2.25 })
    LVAbyssalSkadiOverwhelm({ caster = hero, target = target, ability = item })
    assert(#target.modifiers == 1)
    local stun = target.modifiers[1]
    assert(stun.name == "modifier_bashed")
    assert(stun.caster == hero and stun.ability == item)
    assert(stun.duration == 2.25)
    assert(#particles == 2)
    assert(particles[1].path == "particles/items_fx/abyssal_blink_start.vpcf")
    assert(particles[1].owner == hero and particles[1].released)
    assert(particles[2].path == "particles/items_fx/abyssal_blade.vpcf")
    assert(particles[2].owner == target and particles[2].released)
    local sound = target.calls[#target.calls]
    assert(sound.op == "sound")
    assert(sound.name == "DOTA_Item.AbyssalBlade.Activate")
end)

test("missing duration uses the vanilla 1.6 second fallback", function()
    local hero, target, item = fixture()
    LVAbyssalSkadiOverwhelm({ caster = hero, target = target, ability = item })
    assert(target.modifiers[1].duration == 1.6)
end)

test("client callbacks, missing keys and mismatched owners do nothing", function()
    local hero, target, item = fixture()
    server = false
    LVAbyssalSkadiApplyModifiers({ caster = hero, ability = item })
    LVAbyssalSkadiOverwhelm({ caster = hero, target = target, ability = item })
    assert(#hero.modifiers == 0 and #target.modifiers == 0 and #particles == 0)
    server = true

    LVAbyssalSkadiApplyModifiers({})
    LVAbyssalSkadiOverwhelm({})
    assert(#hero.modifiers == 0 and #target.modifiers == 0 and #particles == 0)

    item.owner = make_unit()
    LVAbyssalSkadiApplyModifiers({ caster = hero, ability = item })
    LVAbyssalSkadiOverwhelm({ caster = hero, target = target, ability = item })
    assert(#hero.modifiers == 0 and #target.modifiers == 0 and #particles == 0)
end)

print = output
print(tostring(passed) .. " Lua logic tests passed (engine doubles; not in-game verification).")
