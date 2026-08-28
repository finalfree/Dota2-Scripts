modifier_lv_gem_consumed = class({})

function modifier_lv_gem_consumed:IsHidden() return false end
function modifier_lv_gem_consumed:IsDebuff() return false end
function modifier_lv_gem_consumed:IsPurgable() return false end
function modifier_lv_gem_consumed:IsPurgeException() return false end
function modifier_lv_gem_consumed:RemoveOnDeath() return false end
function modifier_lv_gem_consumed:AllowIllusionDuplicate() return false end
function modifier_lv_gem_consumed:GetTexture() return "item_gem" end
function modifier_lv_gem_consumed:DeclareFunctions() return { MODIFIER_PROPERTY_TOOLTIP } end
function modifier_lv_gem_consumed:OnTooltip() return self.radius or 0 end

function modifier_lv_gem_consumed:OnCreated(params)
    if IsServer() then
        -- Transmit the radius without exposing it as a number on the buff icon.
        self.radius = tonumber(params.radius) or 0
        self:SetHasCustomTransmitterData(true)
    end
end

function modifier_lv_gem_consumed:AddCustomTransmitterData()
    return { radius = self.radius or 0 }
end

function modifier_lv_gem_consumed:HandleCustomTransmitterData(data)
    self.radius = tonumber(data.radius) or 0
end

function modifier_lv_gem_consumed:IsAura()
    local hero = self:GetParent()
    return hero:IsAlive() and hero:IsRealHero() and not hero:IsIllusion()
        and not hero:IsTempestDouble() and not (hero.IsClone and hero:IsClone())
end

function modifier_lv_gem_consumed:GetAuraRadius() return self.radius or 0 end
function modifier_lv_gem_consumed:GetAuraDuration() return 0.1 end
function modifier_lv_gem_consumed:GetAuraSearchTeam() return DOTA_UNIT_TARGET_TEAM_ENEMY end
-- ALL includes wards. Do not filter on visibility: invisible enemies need detection.
function modifier_lv_gem_consumed:GetAuraSearchType() return DOTA_UNIT_TARGET_ALL end
function modifier_lv_gem_consumed:GetAuraSearchFlags() return DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES end
function modifier_lv_gem_consumed:GetModifierAura() return "modifier_truesight" end
-- Use the native True Sight recipient modifier, not global INVISIBLE=false or
-- AddFOWViewer. Actual fog/ward/immunity behavior still requires in-game testing.
