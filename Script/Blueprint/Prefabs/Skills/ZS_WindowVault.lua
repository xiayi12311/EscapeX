---@class ZS_WindowVault_C:PESkillTemplate_Base_C
--Edit Below--
---@type ZS_WindowVault_C
local ZS_WindowVault = {}

function ZS_WindowVault:OnEnableSkill_BP()
    ZS_WindowVault.SuperClass.OnEnableSkill_BP(self)
end

function ZS_WindowVault:OnDisableSkill_BP()
    ZS_WindowVault.SuperClass.OnDisableSkill_BP(self)
end

function ZS_WindowVault:OnActivateSkill_BP()
    ZS_WindowVault.SuperClass.OnActivateSkill_BP(self)
end

function ZS_WindowVault:OnDeActivateSkill_BP()
    ZS_WindowVault.SuperClass.OnDeActivateSkill_BP(self)
end

function ZS_WindowVault:CanActivateSkill_BP()
    return ZS_WindowVault.SuperClass.CanActivateSkill_BP(self)
end

return ZS_WindowVault