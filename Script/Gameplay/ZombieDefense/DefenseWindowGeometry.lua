local Geometry = {}
local positiveFields = {'VaultDistance', 'OutsideDistance', 'BoardWidth', 'SlotSpacing',
    'GateHalfDepth', 'GateHalfHeight', 'QueryHalfDepth', 'QueryHalfWidth', 'QueryHalfHeight',
    'StartRadius', 'LandingRadius', 'FootTolerance', 'NavProjectionHeight'}
local offsetFields = {'FloorBelow', 'OutsideFloorOffset', 'InsideFloorOffset', 'BoardHeightOffset',
    'InteractionDepthOffset', 'InteractIn', 'GateUp', 'QueryIn'}

local function finite(value)
    return type(value) == 'number' and value > -math.huge and value < math.huge
end

local function extent(x, y, z)
    return {X = x, Y = y, Z = z}
end

function Geometry.Build(window)
    local issue = 'INVALID_WINDOW_LAYOUT: ' .. window.PointId
    for _, field in ipairs(positiveFields) do
        if not finite(window[field]) or window[field] <= 0 then return nil, issue .. ' ' .. field end
    end
    for _, field in ipairs(offsetFields) do
        if not finite(window[field]) then return nil, issue .. ' ' .. field end
    end
    local rotation = window:K2_GetActorRotation()
    local origin = window:K2_GetActorLocation()
    local scale = window:GetActorScale3D()
    local distance = window.OutsideDistance
    local outsideFloor, insideFloor = window.OutsideFloorOffset, window.InsideFloorOffset
    local boardHeight, interactionOffset = window.BoardHeightOffset, window.InteractionDepthOffset
    if not finite(rotation.Yaw) or math.abs(rotation.Pitch) > 0.1 or math.abs(rotation.Roll) > 0.1
        or math.abs(scale.X-1) > 0.001 or math.abs(scale.Y-1) > 0.001 or math.abs(scale.Z-1) > 0.001
        or distance <= window.GateHalfDepth or window.VaultDistance - distance <= window.GateHalfDepth
        or math.abs(insideFloor - outsideFloor) > window.FootTolerance then
        return nil, issue
    end
    local angle = math.rad(rotation.Yaw)
    local x, y = math.cos(angle), math.sin(angle)
    local function point(forward, z)
        return extent(origin.X + forward*x, origin.Y + forward*y, origin.Z + z)
    end
    return {
        Origin = origin, Rotation = {Pitch = 0, Yaw = rotation.Yaw, Roll = 0},
        Outside = point(-distance, outsideFloor - window.FloorBelow),
        Inside = point(window.VaultDistance-distance, insideFloor - window.FloorBelow),
        Board = point(0, boardHeight), Interaction = point(window.InteractIn + interactionOffset, 0),
        Gate = point(0, boardHeight + window.GateUp),
        GateExtent = extent(window.GateHalfDepth, window.BoardWidth/2, window.GateHalfHeight),
        Query = point(window.QueryIn, 0),
        QueryExtent = extent(window.QueryHalfDepth, window.QueryHalfWidth, window.QueryHalfHeight),
    }
end

function Geometry.Apply(window, geometry)
    local function move(component, position)
        component:K2_SetWorldLocationAndRotation(position, geometry.Rotation, false, {}, true)
    end
    move(window.OutsideApproach, geometry.Outside)
    move(window.InsideLanding, geometry.Inside)
    move(window.BoardRoot, geometry.Board)
    move(window.InteractionPoint, geometry.Interaction)
    local gate, query = window.VaultBlocker, window.WindowInteractionQuery
    move(gate, geometry.Gate)
    gate:SetBoxExtent(geometry.GateExtent, false)
    move(query, geometry.Query)
    query:SetBoxExtent(geometry.QueryExtent, false)
    query:SetCollisionObjectType(ECollisionChannel.ECC_WorldDynamic)
    query:SetCollisionResponseToAllChannels(ECollisionResponse.ECR_Ignore)
    query:SetCollisionEnabled(ECollisionEnabled.QueryOnly)
end

return Geometry
