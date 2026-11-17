---@type BP_ZS_WindowPoint_C
local Point = {DefenseBoardSlots = ''}
local Presentation = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardPresentation')

function Point:GetReplicatedProperties()
    return 'DefenseBoardSlots'
end

function Point:ReceiveBeginPlay()
    Point.SuperClass.ReceiveBeginPlay(self)
    Presentation.Begin(self)
end

function Point:OnRep_DefenseBoardSlots()
    Presentation.Apply(self, true)
end

function Point:SetDefenseBoardSlots(slots)
    self.DefenseBoardSlots = slots
    Presentation.Apply(self, true)
end

function Point:ReceiveEndPlay(reason)
    Presentation.End(self)
    Point.SuperClass.ReceiveEndPlay(self, reason)
end

return Point
