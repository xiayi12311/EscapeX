---@class BP_HTRouteGroup_C:AActor
---@field Marker UArrowComponent
---@field DefaultSceneRoot USceneComponent
---@field GroupName FString
---@field RouteTag FString
---@field bEnabled bool
--Edit Below--
local BP_HTRouteGroup = {}
 
--[[
function BP_HTRouteGroup:ReceiveBeginPlay()
    BP_HTRouteGroup.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function BP_HTRouteGroup:ReceiveTick(DeltaTime)
    BP_HTRouteGroup.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function BP_HTRouteGroup:ReceiveEndPlay()
    BP_HTRouteGroup.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function BP_HTRouteGroup:GetReplicatedProperties()
    return
end
--]]

--[[
function BP_HTRouteGroup:GetAvailableServerRPCs()
    return
end
--]]

return BP_HTRouteGroup