---@class ZS_PoliceWindowVault_C:PESkillTemplate_Base_C
--Edit Below--
---@type ZS_WindowVault_C
local ZS_PoliceWindowVault = {}

function ZS_PoliceWindowVault:OnEnableSkill_BP()
    ZS_PoliceWindowVault.SuperClass.OnEnableSkill_BP(self)
end

function ZS_PoliceWindowVault:OnDisableSkill_BP()
    ZS_PoliceWindowVault.SuperClass.OnDisableSkill_BP(self)
end

function ZS_PoliceWindowVault:OnActivateSkill_BP()
    ZS_PoliceWindowVault.SuperClass.OnActivateSkill_BP(self)
end

function ZS_PoliceWindowVault:OnDeActivateSkill_BP()
    ZS_PoliceWindowVault.SuperClass.OnDeActivateSkill_BP(self)
end

function ZS_PoliceWindowVault:CanActivateSkill_BP()
    return ZS_PoliceWindowVault.SuperClass.CanActivateSkill_BP(self)
end

return ZS_PoliceWindowVault