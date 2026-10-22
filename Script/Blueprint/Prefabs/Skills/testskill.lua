local testskill = {}
 
function testskill:OnEnableSkill_BP()
    testskill.SuperClass.OnEnableSkill_BP(self)
end

function testskill:OnDisableSkill_BP()
    testskill.SuperClass.OnDisableSkill_BP(self)
end

function testskill:OnActivateSkill_BP()
    testskill.SuperClass.OnActivateSkill_BP(self)
end

function testskill:OnDeActivateSkill_BP()
    testskill.SuperClass.OnDeActivateSkill_BP(self)
end

function testskill:CanActivateSkill_BP()
    return testskill.SuperClass.CanActivateSkill_BP(self)
end

return testskill