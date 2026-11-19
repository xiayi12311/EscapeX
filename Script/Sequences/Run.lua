---@class Run_C:AActor
---@field Run1ASBoxTrigger BP_ASBoxTrigger_C
---@field Run1Sequence2 UActorSequenceComponent
---@field Run1Sequence UActorSequenceComponent
---@field Run1Cube3 UStaticMeshComponent
---@field Run1Cube2 UStaticMeshComponent
---@field Run1SkeletalMesh USkeletalMeshComponent
---@field BP_ASBoxTrigger1 BP_ASBoxTrigger_C
---@field ActorSequence2 UActorSequenceComponent
---@field StaticMesh2 UStaticMeshComponent
---@field StaticMesh1 UStaticMeshComponent
---@field Cube2 UStaticMeshComponent
---@field BP_ASBoxTrigger BP_ASBoxTrigger_C
---@field ASBoxTrigger BP_ASBoxTrigger_C
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