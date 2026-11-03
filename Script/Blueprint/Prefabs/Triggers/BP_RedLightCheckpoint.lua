---@class BP_RedLightCheckpoint_C:AActor
---@field CheckpointArrow UArrowComponent
---@field CheckpointEnabled bool
---@field RedLightCheckpointTag FString
---@field CheckpointDescription FString
--Edit Below--
local Checkpoint = {}

function Checkpoint:ReceiveBeginPlay()
    Checkpoint.SuperClass.ReceiveBeginPlay(self)
end

return Checkpoint
