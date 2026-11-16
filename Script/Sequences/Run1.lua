---@class Run1_C:AActor
---@field Cube3 UStaticMeshComponent
---@field ActorSequence2 UActorSequenceComponent
---@field Cube2 UStaticMeshComponent
---@field ASBoxTrigger BP_ASBoxTrigger_C
---@field Cube1 UStaticMeshComponent
---@field Cube UStaticMeshComponent
---@field SkeletalMesh USkeletalMeshComponent
---@field StaticMesh UStaticMeshComponent
---@field STCustomMesh USTCustomMeshComponent
---@field DefaultSceneRoot USceneComponent
--Edit Below--
---@type Run_C
local Run1 = {}
 
--[[
function Run1:ReceiveBeginPlay()
    Run1.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function Run1:ReceiveTick(DeltaTime)
    Run1.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function Run1:ReceiveEndPlay()
    Run1.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function Run1:GetReplicatedProperties()
    return
end
--]]

--[[
function Run1:GetAvailableServerRPCs()
    return
end
--]]

return Run1