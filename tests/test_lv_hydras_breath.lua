-- Engine substitutes verify lifecycle and attack dispatch, not engine procs.
function IsServer() return true end
local STATUS = "modifier_item_lv_hydras_breath_consumed_status"
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

dofile("game/dota_addons/overforged/scripts/vscripts/lv/item_lv_hydras_breath.lua")
local function absorb(hero, item)
    LVHydrasBreathTryAbsorb({ caster = hero, ability = item })
    hero:run()
end

-- Successful absorption, no extra instances on repeated callbacks, and respawn.
do
    local hero, item = fixture()
    absorb(hero, item)
    assert(hero.slots[0] == nil and hero.taken == 1 and not item:IsNull())
    assert(item._lv_hydras_breath_consumed and hero._lv_hydras_breath_item == item)
    assert(LV_HYDRAS_BREATH_STATE.items[hero.id] == item)
    assert(#hero:FindAllModifiersByName(STATUS) == 1)
    absorb(hero, item)
    assert(hero.taken == 1)
    hero.alive = false
    assert(#hero:FindAllModifiersByName(STATUS) == 1)
    hero.alive = true
    -- Death does not discard the absorbed item or its permanent KV status.
    local duplicate = hero:item(1)
    absorb(hero, duplicate)
    assert(hero.slots[1] == duplicate and hero.taken == 1)
    assert(#hero:FindAllModifiersByName(STATUS) == 1)
end

-- Initialization failure, hiding failure, and failure after TakeItem all roll back.
for _, failure in ipairs({ "status", "take", "late_status" }) do
    local hero, item = fixture()
    if failure == "status" then hero.fail = STATUS end
    if failure == "take" then hero.fail_take = true end
    if failure == "late_status" then hero.fail_after_take = STATUS end
    absorb(hero, item)
    assert(hero.slots[0] == item and not item._lv_hydras_breath_consumed, failure)
    assert(#hero:FindAllModifiersByName(STATUS) == 0, failure)
    assert(hero._lv_hydras_breath_item == nil, failure)
end

-- Eligibility and changes during the recipe delay.
for _, flag in ipairs({ "nonhero", "illusion", "double", "clone", "dead", "stash", "moved" }) do
    local hero, item = fixture()
    if flag == "dead" then hero.alive = false
    elseif flag == "stash" then hero.slots[0] = nil; hero.slots[9] = item
    elseif flag ~= "moved" then hero[flag] = true end
    LVHydrasBreathTryAbsorb({ caster = hero, ability = item })
    if flag == "moved" then hero.slots[0] = nil; hero.slots[9] = item end
    hero:run()
    assert(hero.taken == 0 and not item._lv_hydras_breath_consumed, flag)
end

-- Two recipes queued in one frame: only the first may be consumed.
do
    local hero, item = fixture()
    local duplicate = hero:item(1)
    LVHydrasBreathTryAbsorb({ caster = hero, ability = item })
    LVHydrasBreathTryAbsorb({ caster = hero, ability = duplicate })
    hero:run()
    assert(hero.taken == 1 and hero.slots[1] == duplicate)
end
print("item_lv_hydras_breath lifecycle tests passed")

DOTA_UNIT_TARGET_TEAM_ENEMY=1
DOTA_UNIT_TARGET_HERO=1
DOTA_UNIT_TARGET_BASIC=2
DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE=1
DOTA_UNIT_TARGET_FLAG_NO_INVIS=2
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=4
DOTA_UNIT_TARGET_FLAG_NOT_ATTACK_IMMUNE=8
FIND_CLOSEST=0
local function position(x)
    return setmetatable({x=x}, {__sub=function(a,b)
        return {Length2D=function() return math.abs(a.x-b.x) end}
    end})
end
local function target()
    local t={}
    function t:IsNull() return false end
    function t:IsAlive() return not self.dead end
    function t:GetTeamNumber() return 3 end
    function t:IsInvulnerable() return self.invulnerable end
    function t:IsAttackImmune() return self.immune end
    function t:IsInvisible() return self.invisible end
    function t:GetAbsOrigin() return position(self.x or 100) end
    return t
end
do
    local hero,item=fixture()
    absorb(hero,item)
    hero.attacks=0
    function hero:IsRangedAttacker() return not self.melee end
    function hero:GetTeamNumber() return 2 end
    function hero:GetAbsOrigin() return position(0) end
    function hero:Script_GetAttackRange() return 1400 end
    function hero:CanEntityBeSeenByMyTeam(t) return not t.fog end
    function item:GetSpecialValueFor(k) return ({count=10,secondary_target_range_bonus=150})[k] end
    local primary=target()
    local targets={primary}
    for i=1,12 do targets[#targets+1]=target() end
    table.insert(targets,3,targets[2])
    function FindUnitsInRadius(team,pos,cache,radius,teams,types,flags)
        assert(radius==1550 and types==3 and flags==15)
        return targets
    end
    function hero:PerformAttack(t,orb,procs,skip,invis,projectile,fake,nevermiss)
        assert(t~=primary and orb and procs and skip and not invis and projectile and not fake and not nevermiss)
        self.attacks=self.attacks+1
        LVHydrasBreathAttack({caster=self,attacker=self,ability=item,target=t})
        if self.fail_attack then error('test attack failure') end
    end
    local keys={caster=hero,attacker=hero,ability=item,target=primary}
    LVHydrasBreathAttack(keys)
    assert(hero.attacks==10 and not hero._lv_hydras_breath_attacking)
    hero.melee=true
    LVHydrasBreathAttack(keys)
    assert(hero.attacks==10)
    hero.melee=false
    hero.fail_attack=true
    LVHydrasBreathAttack(keys)
    assert(hero.attacks==11 and not hero._lv_hydras_breath_attacking)
    hero.fail_attack=false
    LVHydrasBreathAttack(keys)
    assert(hero.attacks==21)
    targets={primary}
    for _,flag in ipairs({'dead','invulnerable','immune','invisible','fog'}) do
        local t=target(); t[flag]=true; targets[#targets+1]=t
    end
    local far=target(); far.x=1600; targets[#targets+1]=far
    LVHydrasBreathAttack(keys)
    assert(hero.attacks==21)
    targets[#targets+1]=target()
    LVHydrasBreathAttack(keys)
    assert(hero.attacks==22)
end
print('Hydra PerformAttack dispatch tests passed (engine substitutes)')
