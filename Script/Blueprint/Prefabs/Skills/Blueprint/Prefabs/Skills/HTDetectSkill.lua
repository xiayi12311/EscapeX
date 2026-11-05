local HTDetectSkill = {}
 
function HTDetectSkill:OnEnableSkill_BP()
    HTDetectSkill.SuperClass.OnEnableSkill_BP(self)
end

function HTDetectSkill:OnDisableSkill_BP()
    HTDetectSkill.SuperClass.OnDisableSkill_BP(self)
end

function HTDetectSkill:OnActivateSkill_BP()
    HTDetectSkill.SuperClass.OnActivateSkill_BP(self)
    self.HTCompletionReason = nil
end

function HTDetectSkill:OnDeActivateSkill_BP(Reason)
    self.HTCompletionReason = Reason
    HTDetectSkill.SuperClass.OnDeActivateSkill_BP(self, Reason)
end

function HTDetectSkill:CanActivateSkill_BP()
    return HTDetectSkill.SuperClass.CanActivateSkill_BP(self)
end

return HTDetectSkill
