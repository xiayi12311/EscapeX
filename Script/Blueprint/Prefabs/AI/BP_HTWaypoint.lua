---@class BP_HTWaypoint_C:AActor
---@field Marker UArrowComponent
---@field DefaultSceneRoot USceneComponent
---@field RouteIndex int32
---@field RouteName FString
---@field WaitTime float
--Edit Below--
local BP_HTWaypoint = {}
 
--[[
function BP_HTWaypoint:ReceiveBeginPlay()
    BP_HTWaypoint.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function BP_HTWaypoint:ReceiveTick(DeltaTime)
    BP_HTWaypoint.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function BP_HTWaypoint:ReceiveEndPlay()
    BP_HTWaypoint.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function BP_HTWaypoint:GetReplicatedProperties()
    return
end
--]]

--[[
function BP_HTWaypoint:GetAvailableServerRPCs()
    return
end
--]]

return BP_HTWaypoint