---@class ZS_BoardClaw_C:PESkillTemplate_Base_C
--Edit Below--
---@type ZS_BoardClaw_C
local ZS_BoardClaw = {}

function ZS_BoardClaw:OnEnableSkill_BP()
    ZS_BoardClaw.SuperClass.OnEnableSkill_BP(self)
end

function ZS_BoardClaw:OnDisableSkill_BP()
    ZS_BoardClaw.SuperClass.OnDisableSkill_BP(self)
end

function ZS_BoardClaw:OnActivateSkill_BP()
    ZS_BoardClaw.SuperClass.OnActivateSkill_BP(self)
end

function ZS_BoardClaw:OnDeActivateSkill_BP()
    ZS_BoardClaw.SuperClass.OnDeActivateSkill_BP(self)
end

function ZS_BoardClaw:CanActivateSkill_BP()
    return ZS_BoardClaw.SuperClass.CanActivateSkill_BP(self)
end

return ZS_BoardClaw