---@class Blackboard_C:AActor
---@field Widget UWidgetComponent
---@field Cube UStaticMeshComponent
---@field DefaultSceneRoot USceneComponent
--Edit Below--
---@type Blackboard_C
local Blackboard = {}
 
--[[
function Blackboard:ReceiveBeginPlay()
    Blackboard.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function Blackboard:ReceiveTick(DeltaTime)
    Blackboard.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function Blackboard:ReceiveEndPlay()
    Blackboard.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function Blackboard:GetReplicatedProperties()
    return
end
--]]

--[[
function Blackboard:GetAvailableServerRPCs()
    return
end
--]]

return Blackboard