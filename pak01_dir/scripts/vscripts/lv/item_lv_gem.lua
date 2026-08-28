-- Invoked by the item's data-driven passive; no addon_game_mode dependency.
local BUFF = "modifier_lv_gem_consumed"

local function valid(entity)
    return entity ~= nil and not entity:IsNull()
end

local function eligible(hero, item)
    if not valid(hero) or not valid(item) or item:GetCaster() ~= hero then
        return false
    end
    if not hero:IsRealHero() or hero:IsIllusion() or not hero:IsAlive()
        or hero:IsTempestDouble() or (hero.IsClone and hero:IsClone()) then
        return false
    end
    -- Never consume in a courier, stash, backpack, neutral slot or on the ground.
    for slot = 0, 5 do
        if hero:GetItemInSlot(slot) == item then
            return true
        end
    end
    return false
end

function LVGemTryAbsorb(keys)
    if not IsServer() then return end
    local hero, item = keys.caster, keys.ability
    if not valid(item) then return end
    if not item._lv_gem_callback_seen then
        item._lv_gem_callback_seen = true
        print("[lv_gem] automatic absorption callback reached")
    end
    if item._lv_gem_pending or item._lv_gem_consumed or not eligible(hero, item) then
        return
    end
    if hero:HasModifier(BUFF) then
        if not item._lv_gem_duplicate_reported then
            item._lv_gem_duplicate_reported = true
            print("[lv_gem] already absorbed; duplicate item retained")
        end
        return
    end

    -- Defer past inventory assembly / intrinsic modifier creation.
    item._lv_gem_pending = true
    hero:SetContextThink("lv_gem_absorb_" .. item:entindex(), function()
        if not valid(item) then return nil end
        item._lv_gem_pending = false
        if item._lv_gem_consumed or not eligible(hero, item) or hero:HasModifier(BUFF) then
            return nil
        end
        local radius = item:GetSpecialValueFor("radius")
        if radius <= 0 then
            if not item._lv_gem_error_reported then
                item._lv_gem_error_reported = true
                print("[lv_gem] invalid radius; item retained")
            end
            return nil
        end
        local ok, modifier = pcall(function()
            LinkLuaModifier(BUFF, "lv/modifier_lv_gem_consumed", LUA_MODIFIER_MOTION_NONE)
            -- No ability handle: deleting the item must not invalidate the buff.
            return hero:AddNewModifier(hero, nil, BUFF, { radius = radius })
        end)
        if not ok or not valid(modifier) or not hero:HasModifier(BUFF) then
            if not item._lv_gem_error_reported then
                item._lv_gem_error_reported = true
                print("[lv_gem] permanent modifier failed; item retained: " .. tostring(modifier))
            end
            return nil
        end
        item._lv_gem_consumed = true
        hero:RemoveItem(item)
        if valid(item) then UTIL_Remove(item) end
        print("[lv_gem] absorbed; permanent True Sight radius=" .. tostring(radius))
        return nil
    end, 0.1)
end
