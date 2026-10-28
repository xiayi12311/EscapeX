-- Shared operations for BT_HeadTeacher. Scheduling belongs exclusively to the BT.
local M = {}
M.Defaults = {
    HTViewDistance = 1000, HTViewFullAngle = 60, HTCatchDistance = 30,
    HTPatrolSpeed = 150, HTChaseSpeed = 500,
    HTDetectionInterval = 0.1, HTDetectionDelay = 1.0, HTMoveInterval = 0.5,
    HTWaypointRadius = 50, HTDiagnosticInterval = 5,
    HTAttachSocket = "headSocket", HTSourceSocket = "headSocket",
    HTTargetBoundsHeightRatio = 0.75, HTRouteTag = "HT_Route",
    HTSightChannel = 3, HTDebug = false,
    HTConePitch = 0, HTConeYaw = -171.49657, HTConeRoll = -90,
    -- The catch re-check reuses the distance measured when the chase decided; this
    -- bounds how far the target may have moved since then (teleport guard).
    HTCatchSanity = 200,
    -- Capture sequence. CaptureService reads these through M.config so a blueprint
    -- variable of the same name overrides the default per monster instance.
    HTCarrySocket = "headSocket",
    HTPickupDuration = 0.6, HTPutDownDuration = 0.6,
    HTEscortSpeed = 300, HTArriveRadius = 120, HTEscortTimeout = 20,
    HTImprisonDuration = 15, HTStruggleInterval = 0.15,
    HTPlayerPawnChannel = 16, HTPawnChannel = 2,
}

function M.config(p, key)
    local v = p[key]
    if v == nil then return M.Defaults[key] end
    return v
end

function M.valid(o)
    return o ~= nil and KismetSystemLibrary.IsValid(o)
end

function M.data(p)
    if not p.HTRuntime then
        p.HTRuntime = {index = 1, direction = 1, clock = 0, logs = {}}
    end
    return p.HTRuntime
end

function M.log(p, key, message)
    local d = M.data(p)
    if not d.logs[key] or d.clock >= d.logs[key] then
        ugcprint("[HeadTeacher] " .. message)
        d.logs[key] = d.clock + M.config(p, "HTDiagnosticInterval")
    end
end

function M.distance(a, b)
    local x,y,z = a.X-b.X, a.Y-b.Y, a.Z-b.Z
    return math.sqrt(x*x+y*y+z*z)
end

function M.capsuleGap(a, b)
    local ca, cb = a.CapsuleComponent, b.CapsuleComponent
    if not M.valid(ca) or not M.valid(cb) then return math.huge end
    local ra, rb = ca:GetScaledCapsuleRadius(), cb:GetScaledCapsuleRadius()
    local ha, hb = ca:GetScaledCapsuleHalfHeight(), cb:GetScaledCapsuleHalfHeight()
    local pa, pb = ca:K2_GetComponentLocation(), cb:K2_GetComponentLocation()
    local dz = math.max(0, math.abs(pa.Z-pb.Z) - (ha-ra) - (hb-rb))
    return math.max(0, math.sqrt((pa.X-pb.X)^2+(pa.Y-pb.Y)^2+dz^2)-ra-rb)
end

-- Temporary diagnostic switch: logs [HT_TRACE] lines for chase exits and catch
-- decisions. Set to false (or remove the M.trace* helpers) when done.
M.TRACE = false
local TraceWindow = 0.5

function M.traceEvent(message)
    if M.TRACE then ugcprint("[HT_TRACE] " .. message) end
end

function M.trace(p, key, message)
    if not M.TRACE then return end
    local d = M.data(p)
    d.trace = d.trace or {}
    if d.trace[key] and d.clock < d.trace[key] then return end
    d.trace[key] = d.clock + TraceWindow
    ugcprint("[HT_TRACE] " .. message)
end

function M.aliveWhy(target)
    if not M.valid(target) then return "invalid" end
    local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(target)
    if key == -1 then return "nokey", key end
    local health = UGCAttributeSystem.GetGameAttributeValue(target, "Health")
    if not (health > 0) then return "health", key, health end
    return nil, key, health
end

function M.alive(target)
    return M.aliveWhy(target) == nil
end

function M.gapDetail(p, target)
    if not (M.valid(target) and M.valid(p.CapsuleComponent) and M.valid(target.CapsuleComponent)) then
        return "detail=unavailable"
    end
    local ca, cb = p.CapsuleComponent, target.CapsuleComponent
    local pa, pb = ca:K2_GetComponentLocation(), cb:K2_GetComponentLocation()
    return string.format("detail=pa(%.1f,%.1f,%.1f) pb(%.1f,%.1f,%.1f) ra=%.1f rb=%.1f ha=%.1f hb=%.1f",
        pa.X, pa.Y, pa.Z, pb.X, pb.Y, pb.Z,
        ca:GetScaledCapsuleRadius(), cb:GetScaledCapsuleRadius(),
        ca:GetScaledCapsuleHalfHeight(), cb:GetScaledCapsuleHalfHeight())
end

function M.snapshot(p, target)
    local why, key, health = M.aliveWhy(target)
    local gap = -1
    if M.valid(target) and M.valid(p.CapsuleComponent) and M.valid(target.CapsuleComponent) then
        gap = M.capsuleGap(p, target)
    end
    local bb = M.bb(p)
    return string.format(
        "gap=%.1f alive=%s why=%s key=%s health=%s bbSeq=%s processed=%s lock=%s",
        gap, tostring(why == nil), tostring(why), tostring(key), tostring(health),
        tostring(bb:GetValueAsInt("ChaseSequenceId")), tostring(bb:GetValueAsInt("ProcessedSequenceId")),
        tostring(M.valid(M.target(p))))
end

function M.bb(p)
    return UGCGenericCharacterSystem.GetBlackboard(p)
end

function M.target(p)
    return M.bb(p):GetValueAsObject("LockedTarget")
end

function M.socket(p, mesh, name)
    if not M.valid(mesh) or not mesh:DoesSocketExist(name) then
        M.log(p, "socket:"..name, "Missing socket: "..name.."; detection skipped")
        return nil
    end
    return mesh:GetSocketLocation(name)
end

-- One explicit bounds sample, independent of the player's visual mesh/rig.
-- Extent is HALF size. 0.75 samples the upper region, below the box top.
function M.sightPoint(p, target)
    if not M.valid(target) then return nil end
    local center, extent = {}, {}
    target:GetActorBounds(true, center, extent)
    local ratio = M.config(p, "HTTargetBoundsHeightRatio")
    local function finite(n)
        return type(n)=="number" and n==n and math.abs(n)<math.huge
    end
    if not (finite(center.X) and finite(center.Y) and finite(center.Z)
        and finite(extent.Z) and extent.Z>0
        and finite(ratio) and ratio>=0 and ratio<=1) then
        M.log(p,"sight-bounds","Invalid player collision bounds or height ratio; detection skipped")
        return nil
    end
    return {X=center.X,Y=center.Y,Z=center.Z+extent.Z*ratio}
end

function M.visible(p, target)
    local a = M.socket(p, p.Mesh, M.config(p,"HTSourceSocket"))
    if not a then return false end
    local b = M.sightPoint(p, target)
    if not b then return false end
    local blocked = KismetSystemLibrary.LineTraceSingleByCollisionChannel(
        p, a, b, M.config(p,"HTSightChannel"), false, {p,target},
        M.config(p,"HTDebug") and 1 or 0, {}, true,
        {R=0,G=1,B=0,A=1}, {R=1,G=0,B=0,A=1}, 0.12)
    if not blocked then
        M.trace(p,"vis",string.format("vis_clear mode=bounds src=(%.0f,%.0f,%.0f) dst=(%.0f,%.0f,%.0f)",
            a.X,a.Y,a.Z,b.X,b.Y,b.Z))
        return true
    end
    -- The target itself is ignored above; any remaining blocking hit is cover.
    -- Do not dereference FHitResult object handles: this editor/DS binding has
    -- produced invalid FName/object data while resolving their names/owners.
    M.trace(p,"vis",string.format("vis_blocked mode=bounds src=(%.0f,%.0f,%.0f) dst=(%.0f,%.0f,%.0f)",
        a.X,a.Y,a.Z,b.X,b.Y,b.Z))
    return false
end

function M.setupCone(p)
    local mesh, cone = p.Mesh, p.RedLightMesh
    if not M.valid(cone) or not M.valid(mesh) then return false end
    local socket = M.config(p,"HTAttachSocket")
    if not mesh:DoesSocketExist(socket) then
        M.log(p, "attach", "Missing cone attachment socket "..socket)
        return false
    end
    cone:K2_AttachToComponent(mesh, socket, 2, 2, 2, false)
    -- Engine Cone is 100 cm tall, radius 50, tip at local +Z.
    -- Local calibration is measured against this monster's head socket.
    local rotation={Pitch=M.config(p,"HTConePitch"), Yaw=M.config(p,"HTConeYaw"),
        Roll=M.config(p,"HTConeRoll")}
    cone:K2_SetRelativeRotation(rotation, false, {}, false)
    local length = M.config(p,"HTViewDistance")
    local diameter = 2*length*math.tan(math.rad(M.config(p,"HTViewFullAngle")/2))
    cone:SetRelativeScale3D({X=diameter/100,Y=diameter/100,Z=length/100})
    local axis = KismetMathLibrary.GetUpVector(rotation)
    cone:K2_SetRelativeLocation({X=-axis.X*length/2,Y=-axis.Y*length/2,
        Z=-axis.Z*length/2}, false, {}, false)
    cone:SetCollisionEnabled(p:HasAuthority() and 1 or 0)
    cone:SetCollisionResponseToAllChannels(0)
    cone:SetCollisionResponseToChannel(16,1) -- PlayerPawn
    cone.bGenerateOverlapEvents = true
    return true
end

-- A player already being carried or held by another capture must not be locked again.
-- Reached through the GameMode instead of requiring CaptureService: that module
-- requires this one, and a require cycle would leave a half-built table.
function M.busyPlayer(key)
    local ok, mode = pcall(function() return UGCGameSystem.GetGameMode() end)
    if not (ok and M.valid(mode) and mode.CaptureManager) then return false end
    local busy = mode.CaptureManager:IsBusy(key)
    return busy == true
end

function M.scan(p)
    local cone = p.RedLightMesh
    if not M.setupCone(p) then return nil,{} end
    local near=p.HTProximityArea
    if not M.valid(near) then
        M.log(p,'proximity-area','HTProximityArea is missing; detection disabled')
        return nil,{}
    end
    near:SetCollisionEnabled(p:HasAuthority() and 1 or 0)
    near:SetCollisionResponseToAllChannels(0)
    near:SetCollisionResponseToChannel(16,1)
    -- Query the current convex collision at its live socket transform. This also
    -- catches players already inside when patrol resumes, without overlap events.
    local candidates = UGCActorComponentUtility.GetOverlappingActorsWithPrimitiveComponent(
        cone, cone:K2_GetComponentToWorld(), {ESceneQueryType.PlayerPawn}, nil, {p})
    local nearby = UGCActorComponentUtility.GetOverlappingActorsWithPrimitiveComponent(
        near, near:K2_GetComponentToWorld(), {ESceneQueryType.PlayerPawn}, nil, {p})
    local seen, visible = {}, {}
    local function collect(target)
        if not seen[target] and M.alive(target) then
            seen[target] = true
            local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(target)
            if not M.busyPlayer(key) and M.visible(p,target) then
                visible[#visible+1] = {actor=target,
                    distance=M.distance(p:K2_GetActorLocation(),target:K2_GetActorLocation()),
                    key=key}
            end
        end
    end
    for _,target in pairs(candidates or {}) do collect(target) end
    for _,target in pairs(nearby or {}) do collect(target) end
    table.sort(visible,function(a,b)
        if a.distance == b.distance then return a.key < b.key end
        return a.distance < b.distance
    end)
    local selected=visible[1] and visible[1].actor or nil
    return selected,visible
end

function M.routes(p)
    local d,tag=M.data(p),M.config(p,"HTRouteTag")
    if d.route and d.routeTag==tag then return d.route end
    local all = GameplayStatics.GetAllActorsWithTag(p,tag,{})
    local route = {}
    for _,a in pairs(all or {}) do
        if M.valid(a) then route[#route+1] = a end
    end
    local function order(a)
        for _,value in pairs(a.Tags or {}) do
            local n=string.match(tostring(value),"^HT_Route_(%d+)$")
            if n then return tonumber(n) end
        end
        return math.huge
    end
    table.sort(route,function(a,b)
        local ia,ib=order(a),order(b)
        if ia~=ib then return ia<ib end
        return KismetSystemLibrary.GetObjectName(a) < KismetSystemLibrary.GetObjectName(b)
    end)
    if #route == 0 then M.log(p,"route","No route actors tagged "..M.config(p,"HTRouteTag")) end
    if #route>0 then d.route,d.routeTag=route,tag end
    return route
end

function M.feet(p)
    local v = p:K2_GetActorLocation()
    return {X=v.X,Y=v.Y,Z=v.Z-p.CapsuleComponent:GetScaledCapsuleHalfHeight()}
end

function M.arrived(p,point)
    return M.distance(M.feet(p),point:K2_GetActorLocation()) <= M.config(p,"HTWaypointRadius")
end

function M.advance(index,direction,count)
    if count <= 1 then return 1,direction end
    if index >= count then direction = -1 elseif index <= 1 then direction = 1 end
    return index+direction,direction
end

function M.stop(p)
    UGCGenericCharacterSystem.StopMove(p)
end

-- The monster must not be body-blocked by players, and must not block them either.
-- Measured 2026-10-26: the server-side capsule already answered channel 16 with Ignore,
-- but every client's copy still answered Overlap/Block, so local prediction could still
-- be shouldered. This has to run on both ends, not only under HasAuthority.
-- Channel 16 is this build's PlayerPawn channel (see setupCone), 2 is the generic Pawn
-- channel; the live player capsule's object type is 2; channel 4 is Camera.
function M.ignorePlayers(p)
    local channels = { M.config(p, "HTPlayerPawnChannel"), M.config(p, "HTPawnChannel") }
    for _, channel in ipairs(channels) do
        if M.valid(p.CapsuleComponent) then
            p.CapsuleComponent:SetCollisionResponseToChannel(channel, 0)
        end
        if M.valid(p.HitBox) then
            p.HitBox:SetCollisionResponseToChannel(channel, 0)
        end
    end
end

function M.move(p,position,speed)
    UGCGenericCharacterSystem.SetMaxSpeed(p,speed,0)
    UGCGenericCharacterSystem.MoveTo(p,position,5)
end

function M.progress(p, dt)
    local d = M.data(p)
    d.clock = d.clock + dt
end

function M.velocity(p)
    local v = UGCGenericCharacterSystem.GetCurrentVelocity(p)
    if not v then return 0 end
    return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)
end

-- A move request captured before the target moved can be reached early: the
-- character then stands still until the next cadence tick, which reads as a
-- pause right before contact. Re-path at once whenever it is holding short, and
-- start the next path before it reaches a destination the target has left.
local HoldSlack, HoldSpeed, HoldRetry = 10, 20, 0.2
local EarlyGoal, EarlyDrift = 250, 50

function M.moveTick(task,p,position,speed,dt)
    task.MoveElapsed = (task.MoveElapsed or 100)+dt
    task.HoldElapsed = (task.HoldElapsed or 0)+dt
    local now = p:K2_GetActorLocation()
    local due = task.MoveElapsed >= M.config(p,"HTMoveInterval")
    local holding = task.MoveIssued and task.HoldElapsed >= HoldRetry
        and M.velocity(p) < HoldSpeed
        and M.distance(now,position) > HoldSlack
    local early = task.Goal and M.distance(now,task.Goal) <= EarlyGoal
        and M.distance(position,task.Goal) > EarlyDrift
    if not due and not holding and not early then return end
    task.MoveElapsed, task.HoldElapsed, task.MoveIssued = 0, 0, true
    task.Goal = {X=position.X,Y=position.Y,Z=position.Z}
    M.move(p,position,speed)
    if task.LastPosition and M.distance(now,task.LastPosition)<1 then
        task.Stalled = (task.Stalled or 0)+M.config(p,"HTMoveInterval")
        if task.Stalled >= 5 then
            M.log(p,"nav","Navigation stalled; retain target/waypoint and retry")
        end
    else task.Stalled = 0 end
    task.LastPosition = {X=now.X,Y=now.Y,Z=now.Z}
end

function M.begin(task,p,branch)
    if not p:HasAuthority() then task:FinishExecute(false); return false end
    task.MoveElapsed, task.LastPosition, task.Stalled = 100,nil,0
    task.MoveIssued, task.HoldElapsed, task.Goal = nil, 0, nil
    M.data(p)
    M.log(p,"branch:"..branch,"BT task: "..branch)
    return true
end

function M.abort(task,p)
    if M.valid(p) and p:HasAuthority() then
        M.stop(p)
    end
    task:FinishAbort()
end

return M
