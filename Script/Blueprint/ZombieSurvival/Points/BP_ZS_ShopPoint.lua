---@class BP_ZS_ShopPoint_C:AActor
---@field STCustomMesh USTCustomMeshComponent
---@field InteractionPoint USceneComponent
---@field ShopDirection UArrowComponent
---@field DefaultSceneRoot USceneComponent
---@field EncounterId FString
---@field PointId FString
---@field ShopConfigId FString
---@field Enabled bool
--Edit Below--
---@type BP_ZS_ShopPoint_C
local BP_ZS_ShopPoint = {}
 
--[[
function BP_ZS_ShopPoint:ReceiveBeginPlay()
    BP_ZS_ShopPoint.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function BP_ZS_ShopPoint:ReceiveTick(DeltaTime)
    BP_ZS_ShopPoint.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function BP_ZS_ShopPoint:ReceiveEndPlay()
    BP_ZS_ShopPoint.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function BP_ZS_ShopPoint:GetReplicatedProperties()
    return
end
--]]

--[[
function BP_ZS_ShopPoint:GetAvailableServerRPCs()
    return
end
--]]

return BP_ZS_ShopPoint