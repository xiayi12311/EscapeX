---@class BP_ZS_StartPoint_C:AActor
---@field StartMesh UStaticMeshComponent
--Edit Below--
local Point = {DefenseStarted = false, DefenseStatusText = ''}
function Point:GetReplicatedProperties()
    return 'DefenseStarted', 'DefenseStatusText'
end
return Point
