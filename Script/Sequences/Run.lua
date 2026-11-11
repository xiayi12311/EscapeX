---@class Run_C:AActor
---@field ActorSequence1 UActorSequenceComponent
---@field Cube1 UStaticMeshComponent
---@field Cube UStaticMeshComponent
---@field ActorSequence UActorSequenceComponent
---@field SkeletalMesh USkeletalMeshComponent
---@field StaticMesh UStaticMeshComponent
---@field STCustomMesh USTCustomMeshComponent
---@field DefaultSceneRoot USceneComponent
--Edit Below--
---@type Run_C
local Run = {}
 
--[[
function Run:ReceiveBeginPlay()
    Run.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function Run:ReceiveTick(DeltaTime)
    Run.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function Run:ReceiveEndPlay()
    Run.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function Run:GetReplicatedProperties()
    return
end
--]]

--[[
function Run:GetAvailableServerRPCs()
    return
end
--]]

return Run