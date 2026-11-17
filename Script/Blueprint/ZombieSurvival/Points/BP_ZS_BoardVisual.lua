---@class BP_ZS_BoardVisual_C:AActor
---@field RemoveSequence UActorSequenceComponent
---@field InstallSequence UActorSequenceComponent
---@field BoardMesh UStaticMeshComponent
---@field BoardPivot USceneComponent
---@field DefaultSceneRoot USceneComponent
--Edit Below--
---@type BP_ZS_BoardVisual_C
local BP_ZS_BoardVisual = {}

--[[
function BP_ZS_BoardVisual:ReceiveBeginPlay()
    BP_ZS_BoardVisual.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function BP_ZS_BoardVisual:ReceiveTick(DeltaTime)
    BP_ZS_BoardVisual.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function BP_ZS_BoardVisual:ReceiveEndPlay()
    BP_ZS_BoardVisual.SuperClass.ReceiveEndPlay(self)
end
--]]

--[[
function BP_ZS_BoardVisual:GetReplicatedProperties()
    return
end
--]]

--[[
function BP_ZS_BoardVisual:GetAvailableServerRPCs()
    return
end
--]]

return BP_ZS_BoardVisual