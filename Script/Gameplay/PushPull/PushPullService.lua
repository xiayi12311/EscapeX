-- Server-only engine adapter. Gameplay decisions live in PushPullManager; this file
-- validates player/crate state, owns the server pawn attachment, sweeps the crate and
-- publishes the replicated state table.
local Manager = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullManager')
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig')
local Service = {}

local LOG = '[PushPull]'
local active = nil
local holds = {}
local controlLocks = {}
local clockWarned = false

local function log(text) ugcprint(LOG .. ' server ' .. tostring(text)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local function clock(world)
    local ok, value = pcall(function() return UGCGameSystem.GetTimeSeconds(world) end)
    if ok and type(value) == 'number' then return value end
    if not clockWarned then
        clockWarned = true
        log('CLOCK UNAVAILABLE (GetTimeSeconds failed); PushPull state machine cannot advance')
    end
    return nil
end

local function keyOf(controller)
    if not valid(controller) then return -1 end
    local ok, key = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerController(controller) end)
    if ok and type(key) == 'number' then return key end
    return -1
end

local function pawnOf(key)
    local ok, pawn = pcall(function() return UGCGameSystem.GetPlayerPawnByPlayerKey(key) end)
    if ok and valid(pawn) then return pawn end
    return nil
end

local function validatePlayer(key)
    local pawn = pawnOf(key)
    if not pawn then return false, 'PLAYER_UNAVAILABLE', nil end
    local okAlive, alive = pcall(function() return UGCPlayerStateSystem.IsAlive(key) end)
    if not (okAlive and alive) then return false, 'PLAYER_UNAVAILABLE', pawn end
    local okExit, exited = pcall(function() return UGCPlayerStateSystem.IsExit(key) end)
    if okExit and exited then return false, 'PLAYER_UNAVAILABLE', pawn end
    return true, nil, pawn
end

local function setMoveIgnore(component, actor, ignore)
    if not (valid(component) and valid(actor)) then return end
    pcall(function() return component:IgnoreActorWhenMoving(actor, ignore == true) end)
end

local function forceStanding(pawn)
    if not valid(pawn) then return false end
    if pawn.PoseState == ESTEPoseState.Stand then return true end
    local ok, changed = pcall(function()
        return pawn:SwitchPoseState(ESTEPoseState.Stand, true, true, false, false)
    end)
    if not ok or changed == false then
        log('force standing failed: ' .. tostring(changed))
        return false
    end
    return true
end

local function lockActions(pawn)
    if controlLocks[pawn] then return true end
    local acquired = {}
    local ok, err = pcall(function()
        for _, tag in ipairs(Config.ActionStateTags) do
            assert(UGCGameplayTagSystem.IsValidTag(tag), 'invalid PushPull action tag: ' .. tag)
            UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, true, true)
            acquired[#acquired + 1] = tag
        end
    end)
    controlLocks[pawn] = acquired
    if not ok then
        for _, tag in ipairs(acquired) do
            UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, false, false)
        end
        controlLocks[pawn] = nil
        log('action lock failed: ' .. tostring(err))
        return false
    end
    return true
end

local function unlockActions(pawn)
    local tags = controlLocks[pawn]
    controlLocks[pawn] = nil
    if not tags then return end
    for _, tag in ipairs(tags) do
        UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, false, false)
    end
end
local function setServerMovement(pawn, held)
    if not valid(pawn) then return end
    local ok, err = pcall(function()
        local movement = pawn.CharacterMovement
        if movement == nil then error('pawn has no CharacterMovement') end
        if held and held.active then
            movement:SetMovementMode(0)
            movement:SetComponentTickEnabled(false)
        else
            movement:SetMovementMode(held and held.movementMode or 1)
            local tick = true
            if held and held.movementTick ~= nil then tick = held.movementTick end
            movement:SetComponentTickEnabled(tick)
        end
    end)
    if not ok then log('setServerMovement failed: ' .. tostring(err)) end
end

local function attachServer(pawn, crate, participant)
    local movement = pawn.CharacterMovement
    if movement == nil then return false, 'PLAYER_UNAVAILABLE' end
    if not forceStanding(pawn) then return false, 'PLAYER_UNAVAILABLE' end
    if not lockActions(pawn) then return false, 'PLAYER_UNAVAILABLE' end
    local saved = {
        active = true,
        movementMode = movement and movement.MovementMode or 1,
        useControllerYaw = pawn.bUseControllerRotationYaw,
        useControllerPitch = pawn.bUseControllerRotationPitch,
        useControllerRoll = pawn.bUseControllerRotationRoll,
        movementTick = movement and movement:IsComponentTickEnabled() or true,
        crate = crate,
    }
    local ok, err = pcall(function()
        return pawn:K2_AttachToActor(crate, '', 1, 1, 1, false)
    end)
    if ok and err == false then ok, err = false, 'attach returned false' end
    if not ok then
        unlockActions(pawn)
        log('server attach failed: ' .. tostring(err))
        return false, 'PLAYER_UNAVAILABLE'
    end
    local crateLocation = crate:K2_GetActorLocation()
    local pawnLocation = pawn:K2_GetActorLocation()
    local extent = crate.CrateCollision:GetScaledBoxExtent()
    local localX, localY = Manager.GripLocal({
        HalfExtentX = extent.X,
        HalfExtentY = extent.Y,
        EdgeMargin = Config.Interaction.EdgeMargin,
    }, participant)
    local relativeZ = pawnLocation.Z - crateLocation.Z
    local face = Manager.Face(participant.FaceIndex)
    ok, err = pcall(function()
        pawn:K2_SetActorRelativeLocation({X = localX, Y = localY, Z = relativeZ}, false, {}, true)
        pawn:K2_SetActorRelativeRotation({Pitch = 0, Yaw = face.yaw, Roll = 0}, false, {}, true)
    end)
    if not ok then
        pcall(function() return pawn:K2_DetachFromActor(1, 1, 1) end)
        unlockActions(pawn)
        log('server grip alignment failed: ' .. tostring(err))
        return false, 'PLAYER_UNAVAILABLE'
    end
    setMoveIgnore(pawn.CapsuleComponent, crate, true)
    setMoveIgnore(crate.CrateCollision, pawn, true)
    saved.pawn = pawn
    pawn.bUseControllerRotationYaw = false
    pawn.bUseControllerRotationPitch = false
    pawn.bUseControllerRotationRoll = false
    holds[pawn] = saved
    setServerMovement(pawn, saved)
    return true
end

local function releaseServer(pawn, reason)
    if not pawn then return end
    local held = holds[pawn]
    local hadHold = held ~= nil
    if held then
        holds[pawn] = nil
        held.active = false
        if valid(pawn) then
            local world = pawn:K2_GetActorLocation()
            pcall(function() return pawn:K2_DetachFromActor(1, 1, 1) end)
            pcall(function() return pawn:K2_SetActorLocation(world, false, {}, true) end)
            setMoveIgnore(pawn.CapsuleComponent, held.crate, false)
            if held.crate and valid(held.crate.CrateCollision) then
                setMoveIgnore(held.crate.CrateCollision, pawn, false)
            end
            setServerMovement(pawn, held)
            pawn.bUseControllerRotationYaw = held.useControllerYaw
            pawn.bUseControllerRotationPitch = held.useControllerPitch
            pawn.bUseControllerRotationRoll = held.useControllerRoll
        end
    end
    if valid(pawn) then unlockActions(pawn) end
    if reason and hadHold then log('released player=' .. tostring(pawn) .. ' reason=' .. tostring(reason)) end
end

local function loadDurations()
    local actual = {}
    local actualOk = true
    for state, path in pairs(Config.Animations) do
        local ok, length = pcall(function()
            local asset = UGCObjectUtility.LoadObject(path)
            if not valid(asset) then error('animation unavailable: ' .. tostring(path)) end
            return asset:GetPlayLength()
        end)
        if not ok or type(length) ~= 'number' or length <= 0 then
            log('DS animation resource unavailable state=' .. tostring(state) .. ' path=' .. tostring(path)
                .. ' error=' .. tostring(length))
            actualOk = false
            break
        end
        if length > Config.Action.AnimationDurationSafetyMax then
            log('animation duration exceeds safety max state=' .. tostring(state)
                .. ' length=' .. tostring(length))
            return nil, 'INVALID_RESOURCE_DURATION'
        end
        actual[state] = length
    end
    if actualOk then return actual, 'RESOURCE' end
    local configured = {}
    for state, _ in pairs(Config.Animations) do
        local length = Config.AnimationDurations[state]
        if type(length) ~= 'number' or length <= 0 or length > Config.Action.AnimationDurationSafetyMax then
            log('invalid user-approved animation duration state=' .. tostring(state)
                .. ' value=' .. tostring(length))
            return nil, 'INVALID_CONFIG_DURATION'
        end
        configured[state] = length
    end
    log('DS animation packages are client-only; using user-approved PushPullConfig.AnimationDurations')
    return configured, 'CONFIG_USER_APPROVED'
end

local function geometryOf(crate)
    local location = crate:K2_GetActorLocation()
    local rotation = crate:K2_GetActorRotation()
    local extent = crate.CrateCollision:GetScaledBoxExtent()
    return location, rotation.Yaw, extent
end

local function publish(manager, crate)
    local rec = manager:FindCrate(crate)
    if not rec then return end
    rec.Revision = (rec.Revision or 0) + 1
    local state = manager:Snapshot(crate)
    crate.CrateState = state
    rec._dirty = false
    rec._lastPublishedRevision = state.Revision
end
local function keyOfPawn(pawn)
    if not valid(pawn) then return -1 end
    local ok, key = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerPawn(pawn) end)
    if ok and type(key) == 'number' then return key end
    return -1
end

local function removeHoldsForMissingParticipants(manager, crate)
    local rec = manager:FindCrate(crate)
    if not rec then return end
    for pawn, held in pairs(holds) do
        if held.crate == crate then
            local key = keyOfPawn(pawn)
            if key < 0 or not rec.Participants[key] then releaseServer(pawn, 'SESSION_ENDED') end
        end
    end
end

local function applyMovement(manager, crate, dt)
    local rec = manager:FindCrate(crate)
    if not rec or rec.MotionSpeed <= 0 then return false end
    local old = crate:K2_GetActorLocation()
    local distance = rec.MotionSpeed * dt
    local target = {
        X = old.X + (rec.MotionDirX or 0) * distance,
        Y = old.Y + (rec.MotionDirY or 0) * distance,
        Z = old.Z,
    }
    if rec.Rail then
        target = manager:RailTarget(crate, distance)
        if math.abs(target.X - old.X) + math.abs(target.Y - old.Y) < 0.000001 then
            manager:CommitRailMovement(crate, old)
            manager:ClearBlocked(crate)
            return false
        end
    end
    -- Actor Sweep only tests the root (our root is a non-colliding SceneComponent).
    -- Sweep the actual oriented collision box over the ENTIRE step before moving.
    local collision = crate.CrateCollision
    local start = collision:K2_GetComponentLocation()
    local finish = {X = start.X + target.X - old.X,
        Y = start.Y + target.Y - old.Y, Z = start.Z + target.Z - old.Z}
    local ignored = {crate}
    for _, participant in pairs(rec.Participants) do
        local pawn = pawnOf(participant.PlayerKey)
        if pawn then ignored[#ignored + 1] = pawn end
    end
    local hit = {}
    local blocked = KismetSystemLibrary.BoxTraceSingleByProfile(crate, start, finish,
        collision:GetScaledBoxExtent(), collision:K2_GetComponentRotation(),
        collision:GetCollisionProfileName(), false, ignored, EDrawDebugTrace.None, hit, true,
        {}, {}, 0)
    if blocked then
        manager:MarkBlocked(crate)
        log('CRATE_BLOCKED crate=' .. tostring(rec.CrateId))
        return true
    end
    -- Sweep can move partially and still return true. Keep the safe swept position;
    -- never teleport back or finish an obstructed step without collision.
    local moved = crate:K2_SetActorLocation(target, true, {}, false)
    local actual = crate:K2_GetActorLocation()
    if rec.Rail then manager:CommitRailMovement(crate, actual) end
    local dx, dy, dz = actual.X - target.X, actual.Y - target.Y, actual.Z - target.Z
    if not moved or dx * dx + dy * dy + dz * dz > Config.Movement.SweepPositionTolerance ^ 2 then
        manager:MarkBlocked(crate)
        log('CRATE_BLOCKED crate=' .. tostring(rec.CrateId))
        return true
    end
    manager:ClearBlocked(crate)
    return false
end

local function update(gm)
    local manager = gm.PushPullManager
    if not manager then return end
    local now = clock(gm)
    if not now then return end
    local dt = 1 / Config.Movement.MotionTickRate
    local dirty = manager:Tick(now, dt)
    local dirtySet = {}
    for _, crate in ipairs(dirty) do dirtySet[crate] = true end
    for crate, rec in pairs(manager.crates) do
        if valid(crate) then
            local location, yaw, extent = geometryOf(crate)
            manager:SetCrateGeometry(crate, location, yaw, extent)
            removeHoldsForMissingParticipants(manager, crate)
            local blockedNow = applyMovement(manager, crate, dt)
            if blockedNow then dirtySet[crate] = true end
            local location2 = crate:K2_GetActorLocation()
            manager:SetCrateGeometry(crate, location2, yaw, extent)
            local due = rec._motionDirty and now - (rec._lastMotionPublish or 0) >= Config.Movement.StatePublishInterval
            if dirtySet[crate] or due or rec._dirty then publish(manager, crate) end
            if due then rec._lastMotionPublish = now end
        end
    end
end

function Service.Setup(gm)
    if not (valid(gm) and gm:HasAuthority()) or gm.PushPullManager then return end
    holds = {}
    controlLocks = {}
    local durations, source = loadDurations()
    if not durations then
        gm.PushPullSetupError = source or 'ANIMATION_DURATION_UNAVAILABLE'
        log('service disabled because animation durations are invalid')
        return
    end
    gm.PushPullManager = Manager.New(Config, durations)
    active = gm.PushPullManager
    gm.PushPullTimer = UGCTimerUtility.CreateLuaTimer(1 / Config.Movement.MotionTickRate, function()
        if valid(gm) then update(gm) end
    end, true, 'EscapeX.PushPull.Update')
    log('server service initialized durationSource=' .. tostring(source)
        .. ' OnPosition=' .. tostring(durations.OnPosition))
end

function Service.Shutdown(gm)
    if valid(gm) and gm.PushPullManager then
        for crate, _ in pairs(gm.PushPullManager.crates) do
            Service.UnregisterCrate(gm, crate)
        end
        gm.PushPullManager = nil
    end
    active = nil
    for pawn in pairs(holds) do releaseServer(pawn, 'SERVER_SHUTDOWN') end
    if valid(gm) and gm.PushPullTimer then
        UGCTimerUtility.RemoveLuaTimer(gm.PushPullTimer)
        gm.PushPullTimer = nil
    end
end

function Service.RegisterCrate(gm, crate, crateId)
    if not (valid(gm) and gm:HasAuthority()) then return false, 'SERVER_ONLY' end
    local manager = gm.PushPullManager
    if not manager then return false, gm.PushPullSetupError or 'SERVICE_NOT_READY' end
    if not (valid(crate) and valid(crate.CrateCollision)) then return false, 'CRATE_DESTROYED' end
    local extentCheck = crate.CrateCollision:GetScaledBoxExtent()
    if extentCheck.X <= 0 or extentCheck.Y <= 0 or extentCheck.Z <= 0 then
        return false, 'CRATE_DISABLED'
    end
    local rec = manager:RegisterCrate(crate, crateId)
    if crate.CrateEnabled == false then manager:SetCrateEnabled(crate, false) end
    local location, yaw, extent = geometryOf(crate)
    manager:SetCrateGeometry(crate, location, yaw, extent)
    if crate.CrateRailEnabled then
        local spline = crate.CrateRailPath
        local reason
        if not valid(spline) or spline:GetNumberOfSplinePoints() ~= 2 then
            reason = 'INVALID_RAIL_POINTS'
        elseif spline:IsClosedLoop() then
            reason = 'INVALID_RAIL_CLOSED_LOOP'
        elseif spline:GetSplinePointType(0) ~= ESplinePointType.Linear
            or spline:GetSplinePointType(1) ~= ESplinePointType.Linear then
            reason = 'INVALID_RAIL_POINT_TYPE'
        else
            local a = spline:GetLocationAtSplinePoint(0, ESplineCoordinateSpace.World)
            local b = spline:GetLocationAtSplinePoint(1, ESplineCoordinateSpace.World)
            local ok
            ok, reason = manager:ConfigureRail(crate, a, b)
            if ok then reason = nil end
        end
        if reason then
            manager:UnregisterCrate(crate)
            return false, reason
        end
    end
    publish(manager, crate)
    log('registered crate=' .. tostring(rec.CrateId) .. ' session=' .. tostring(rec.SessionId))
    return true
end

function Service.UnregisterCrate(gm, crate)
    local manager = gm and gm.PushPullManager
    if not manager then return false, 'SERVICE_NOT_READY' end
    local removed = manager:UnregisterCrate(crate)
    for _, participant in ipairs(removed) do
        local pawn = pawnOf(participant.PlayerKey)
        if pawn then releaseServer(pawn, 'CRATE_DESTROYED') end
    end
    if valid(crate) then crate.CrateState = {Enabled = false} end
    return true
end
function Service.RequestEntry(gm, crate, controller)
    local manager = gm and gm.PushPullManager
    if not manager then return false, 'SERVICE_NOT_READY' end
    if not valid(crate) then return false, 'CRATE_DESTROYED' end
    local key = keyOf(controller)
    if key < 0 then return false, 'PLAYER_UNAVAILABLE' end
    local ok, reason, pawn = validatePlayer(key)
    if not ok then return false, reason end
    if not (valid(pawn.CharacterMovement) and pawn.CharacterMovement:IsMovingOnGround()) then
        return false, 'PLAYER_AIRBORNE'
    end
    local Capture = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureService')
    if Capture.IsBusy(gm, key) then return false, 'PLAYER_BUSY' end
    local now = clock(gm)
    if not now then return false, 'SERVICE_NOT_READY' end
    local location = pawn:K2_GetActorLocation()
    local forward = pawn:GetActorForwardVector()
    local participant, entryReason = manager:RequestEntry(crate, key, location, forward, now)
    if not participant then return false, entryReason end
    local attached, attachReason = attachServer(pawn, crate, participant)
    if not attached then
        manager:RemovePlayer(key, true)
        publish(manager, crate)
        return false, attachReason
    end
    publish(manager, crate)
    log('entry player=' .. tostring(key) .. ' face=' .. tostring(participant.FaceIndex)
        .. ' u=' .. tostring(participant.GripU))
    return true
end

function Service.SetIntent(gm, crate, controller, sessionId, intent)
    local manager = gm and gm.PushPullManager
    if not manager then return false, 'SERVICE_NOT_READY' end
    local key = keyOf(controller)
    if key < 0 then return false, 'PLAYER_UNAVAILABLE' end
    local now = clock(gm)
    if not now then return false, 'SERVICE_NOT_READY' end
    local ok, reason = manager:SetIntent(crate, key, sessionId, intent, now)
    if ok then publish(manager, crate) end
    return ok, reason
end

function Service.Release(gm, crate, controller, sessionId)
    local manager = gm and gm.PushPullManager
    if not manager then return false, 'SERVICE_NOT_READY' end
    local key = keyOf(controller)
    if key < 0 then return false, 'PLAYER_UNAVAILABLE' end
    local now = clock(gm)
    if not now then return false, 'SERVICE_NOT_READY' end
    local rec = manager:FindCrate(crate)
    if not rec then return false, 'CRATE_DESTROYED' end
    local pawn = pawnOf(key)
    local ok, reason = manager:Release(crate, key, sessionId, now, false)
    if ok then
        if rec.Participants[key] == nil and pawn then releaseServer(pawn, 'PLAYER_RELEASED') end
        publish(manager, crate)
    end
    return ok, reason
end

function Service.CancelPlayer(gm, playerKeyOrController, reason)
    local manager = gm and gm.PushPullManager
    if not manager then return false, 'SERVICE_NOT_READY' end
    local key = playerKeyOrController
    if type(key) ~= 'number' then key = keyOf(playerKeyOrController) end
    if key < 0 then return false, 'PLAYER_UNAVAILABLE' end
    local owned = manager.players[key]
    local pawn = pawnOf(key)
    local removed = manager:RemovePlayer(key, true)
    if pawn then releaseServer(pawn, reason or 'PLAYER_UNAVAILABLE') end
    if removed and owned then publish(manager, owned.actor) end
    return removed ~= nil
end

function Service.CancelVictim(gm, controller, pawn, reason)
    local key = keyOf(controller)
    if key < 0 and valid(pawn) then
        local ok, value = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerPawn(pawn) end)
        if ok and type(value) == 'number' then key = value end
    end
    if key < 0 then return false end
    return Service.CancelPlayer(gm, key, reason)
end

function Service.IsBusy(gm, key)
    local manager = gm and gm.PushPullManager
    return manager ~= nil and manager.players[key] ~= nil
end

return Service
