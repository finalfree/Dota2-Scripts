-- Server lifecycle doubles only: native values/stacking require Dota testing.
local output = print
local server, time, messages, damage = true, 0, {}, nil
function IsServer() return server end
function Msg(message) messages[#messages + 1] = message end
function ApplyDamage(args) damage = args end
DAMAGE_TYPE_PURE = 4
GameRules = { GetGameTime = function() return time end }
dofile('game/dota_addons/overforged/scripts/vscripts/lv/item_lv_trident.lua')
local EXTRA = 'modifier_item_kaya_and_sange'
local NATIVE = 'modifier_item_trident'
local SKILL = 'lv_trident_extras'

local function fixture()
    server, time, messages, damage = true, 0, {}, nil
    local hero = { inventory = {}, modifiers = {}, skills = {}, alive = true, muted = false }
    function hero:IsNull() return false end
    function hero:IsAlive() return self.alive end
    function hero:IsMuted() return self.muted end
    function hero:GetItemInSlot(slot) return self.inventory[slot] end
    function hero:FindAbilityByName(name) return self.skills[name] end
    function hero:AddAbility(name)
        if self.fail_skill then return nil end
        local ability = { null = false }
        function ability:IsNull() return self.null end
        function ability:SetLevel(level) self.level = level end
        function ability:SetHidden(hidden) self.hidden = hidden end
        function ability:SetActivated(active) self.active = active end
        self.skills[name] = ability
        return ability
    end
    function hero:RemoveAbility(name)
        self.skills[name].null = true
        self.skills[name] = nil
    end
    function hero:FindAllModifiersByName(name)
        local found = {}
        for _, mod in ipairs(self.modifiers) do
            if mod.name == name and not mod.null then found[#found + 1] = mod end
        end
        return found
    end
    function hero:AddNewModifier(caster, source, name, params)
        if name == EXTRA and self.fail_modifier then return nil end
        local mod = { name = name, source = source }
        function mod:IsNull() return self.null == true end
        function mod:GetAbility() return self.source end
        function mod:Destroy() self.null = true end
        self.modifiers[#self.modifiers + 1] = mod
        return mod
    end
    local function item(slot)
        local value = { owner = hero, muted = false }
        function value:IsNull() return self.null == true end
        function value:GetCaster() return self.owner end
        function value:IsMuted() return self.muted end
        function value:GetSpecialValueFor(key) assert(key == 'pure_damage_attack'); return 100 end
        hero.inventory[slot] = value
        return value
    end
    local first = item(0)
    return hero, first, item
end
local function apply(hero, item) LVTridentApplyModifiers({ caster = hero, ability = item }) end
local function remove(hero, item) LVTridentRemoveModifiers({ caster = hero, ability = item }) end
local function refresh(hero)
    time = time + 0.25
    LVTridentRefreshModifiers({ caster = hero })
end
local function count(hero, name) return #hero:FindAllModifiersByName(name) end
local function extras(hero) return hero:FindAllModifiersByName(EXTRA)[1] end
local passed = 0
local function test(name, fn)
    fn(); passed = passed + 1; output('PASS: ' .. name)
end

test('two copies share one isolated source; repeated callbacks are idempotent', function()
    local hero, first, item = fixture()
    apply(hero, first); apply(hero, first)
    local source = extras(hero).source
    assert(source ~= first and source == hero.skills[SKILL])
    assert(source.hidden and source.level == 1 and not source.active)
    local second = item(1)
    apply(hero, second)
    assert(count(hero, NATIVE) == 2 and count(hero, EXTRA) == 1)
    refresh(hero); refresh(hero)
    assert(#hero.modifiers == 3, 'unchanged timers must not recreate modifiers')
    remove(hero, first); remove(hero, first)
    assert(count(hero, EXTRA) == 1 and extras(hero).source == source)
    assert(count(hero, NATIVE) == 1)
    remove(hero, second)
    assert(count(hero, EXTRA) == 0 and count(hero, NATIVE) == 0)
    assert(source.null and hero.skills[SKILL] == nil and hero._lv_trident_extras == nil)
end)

test('cleanup preserves ordinary Kaya/Sange and unowned hidden ability', function()
    local hero, first = fixture()
    local ordinary = {}
    local original = hero:AddNewModifier(hero, ordinary, EXTRA, {})
    local source = hero:AddAbility(SKILL)
    apply(hero, first); remove(hero, first)
    assert(not original.null and count(hero, EXTRA) == 1)
    assert(hero.skills[SKILL] == source and not source.null)
end)

test('inventory, item mute, hero mute and respawn govern extras', function()
    local hero, first = fixture()
    apply(hero, first)
    hero.inventory[0], hero.inventory[6] = nil, first
    refresh(hero); assert(count(hero, EXTRA) == 0)
    hero.inventory[0], hero.inventory[6], first.muted = first, nil, true
    refresh(hero); assert(count(hero, EXTRA) == 0)
    first.muted = false
    refresh(hero); assert(count(hero, EXTRA) == 1)
    hero.muted = true
    refresh(hero); assert(count(hero, EXTRA) == 0)
    hero.muted = false
    refresh(hero); assert(count(hero, EXTRA) == 1)
    extras(hero):Destroy(); hero.alive = false
    refresh(hero); assert(count(hero, EXTRA) == 0)
    hero.alive = true
    refresh(hero); assert(count(hero, EXTRA) == 1)
end)

test('one muted copy does not disable another; transfer and destroyed handles clean up', function()
    local hero, first, item = fixture()
    local second = item(1)
    apply(hero, first); apply(hero, second)
    first.muted = true
    refresh(hero); assert(count(hero, EXTRA) == 1)
    second.owner = {}
    refresh(hero); assert(count(hero, EXTRA) == 0)
    first.null = true
    refresh(hero)
    assert(hero.skills[SKILL] == nil and hero._lv_trident_extras == nil)
end)

test('creation failures preserve base stats, log once and retry safely', function()
    local hero, first = fixture()
    hero.fail_skill = true
    apply(hero, first); refresh(hero)
    assert(count(hero, NATIVE) == 1 and count(hero, EXTRA) == 0 and #messages == 1)
    hero.fail_skill, hero.fail_modifier = false, true
    refresh(hero); assert(count(hero, EXTRA) == 0)
    hero.fail_modifier = false
    refresh(hero); assert(count(hero, EXTRA) == 1)
    assert(extras(hero).source ~= first)
    remove(hero, first); assert(hero.skills[SKILL] == nil)
end)

test('client and invalid-owner callbacks do not install effects; pure damage is unchanged', function()
    local hero, first = fixture()
    server = false
    apply(hero, first); refresh(hero); remove(hero, first)
    assert(#hero.modifiers == 0)
    server = true
    LVTridentApplyModifiers(nil); LVTridentRefreshModifiers(nil); LVTridentRemoveModifiers(nil)
    first.owner = {}
    apply(hero, first); assert(#hero.modifiers == 0)
    first.owner = hero
    local target = { IsNull = function() return false end }
    LVTridentApplyPureAttackDamage({ caster = hero, ability = first, target = target })
    assert(damage.damage == 100 and damage.damage_type == DAMAGE_TYPE_PURE)
    assert(damage.ability == first and damage.victim == target and damage.damage_flags == nil)
end)
output('Trident lifecycle tests passed: ' .. passed)
