-- Owner-client attachment, input lease and animation presentation. The replicated crate
-- state is the only authority; this module never moves the crate or chooses gameplay.
local Animation = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullAnimation')
local Manager = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullManager')
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig')
local P = {}

local LOG = '[PushPull]'
local hold = nil
local timer = nil
local monitorTimer = nil
local watchedPawn = nil

local function log(text) ugcprint(LOG .. ' presentation ' .. tostring(text)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local function localController()
    local ok, pc = pcall(function() return UGCGameSystem.GetLocalPlayerController() end)
    if ok and valid(pc) then return pc end
    return nil
end

local function localKey(pc)
    if not valid(pc) then return -1 end
    local ok, key = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerController(pc) end)
    if ok and type(key) == 'number' then return key end
    return -1
end

local function localPawn()
    local pc = localController()
    if not valid(pc) then return nil end
    local ok, pawn = pcall(function() return pc:K2_GetPawn() end)
    if ok and valid(pawn) then return pawn end
    return nil
end

local function pawnOf(key)
    local ok, pawn = pcall(function() return UGCGameSystem.GetPlayerPawnByPlayerKey(key) end)
    if ok and valid(pawn) then return pawn end
    return nil
end

local function participantOf(state, key)
    return state and state.Participants and state.Participants[key] or nil
end

local function setMoveIgnore(component, actor, ignore)
    if not (valid(component) and valid(actor)) then return end
    pcall(function() return component:IgnoreActorWhenMoving(actor, ignore == true) end)
end

local function setMovementLocked(pawn, saved, locked)
    if not valid(pawn) then return end
    local ok, err = pcall(function()
        local movement = pawn.CharacterMovement
        if movement == nil then error('pawn has no CharacterMovement') end
        if locked then
            movement:SetMovementMode(0)
            movement:SetComponentTickEnabled(false)
        else
            movement:SetMovementMode(saved and saved.movementMode or 1)
            local tick = true
            if saved and saved.movementTick ~= nil then tick = saved.movementTick end
            movement:SetComponentTickEnabled(tick)
        end
    end)
    if not ok then log('movement lock failed: ' .. tostring(err)) end
end

local function release(reason)
    if not hold then return end
    local current = hold
    hold = nil
    local pawn = current.pawn
    if valid(pawn) then
        local world = pawn:K2_GetActorLocation()
        pcall(function() return pawn:K2_DetachFromActor(1, 1, 1) end)
        pcall(function() return pawn:K2_SetActorLocation(world, false, {}, true) end)
        setMoveIgnore(pawn.CapsuleComponent, current.actor, false)
        if valid(current.actor.CrateCollision) then
            setMoveIgnore(current.actor.CrateCollision, pawn, false)
        end
        setMovementLocked(pawn, current, false)
        pawn.bUseControllerRotationYaw = current.useControllerYaw
        pawn.bUseControllerRotationPitch = current.useControllerPitch
        pawn.bUseControllerRotationRoll = current.useControllerRoll
        Animation.RestorePawn(pawn)
    end
    log('released reason=' .. tostring(reason))
end

local function relativeFromWorld(actor, pawn)
    local a = actor:K2_GetActorLocation()
    local p = pawn:K2_GetActorLocation()
    local yaw = actor:K2_GetActorRotation().Yaw or 0
    local radians = yaw * math.pi / 180
    local s, c = math.sin(radians), math.cos(radians)
    local dx, dy = p.X - a.X, p.Y - a.Y
    return {
        X = dx * c + dy * s,
        Y = -dx * s + dy * c,
        Z = p.Z - a.Z,
    }
end

local function acquire(actor, state, participant, pc, pawn)
    release('REACQUIRE')
    local movement = pawn.CharacterMovement
    local saved = {
        active = true,
        actor = actor,
        pawn = pawn,
        controller = pc,
        movementMode = movement and movement.MovementMode or 1,
        movementTick = movement and movement:IsComponentTickEnabled() or true,
        useControllerYaw = pawn.bUseControllerRotationYaw,
        useControllerPitch = pawn.bUseControllerRotationPitch,
        useControllerRoll = pawn.bUseControllerRotationRoll,
        sessionId = state.SessionId,
        participant = participant,
        state = state,
    }
    local start = relativeFromWorld(actor, pawn)
    local startYaw = (pawn:K2_GetActorRotation().Yaw or 0) - (actor:K2_GetActorRotation().Yaw or 0)
    local ok, err = pcall(function()
        return pawn:K2_AttachToActor(actor, '', 1, 1, 1, false)
    end)
    if ok and err == false then ok, err = false, 'attach returned false' end
    if not ok then
        log('local attach failed: ' .. tostring(err))
        setMovementLocked(pawn, saved, false)
        return false
    end
    local targetX, targetY = Manager.GripLocal({
        HalfExtentX = actor.CrateCollision:GetScaledBoxExtent().X,
        HalfExtentY = actor.CrateCollision:GetScaledBoxExtent().Y,
        EdgeMargin = Config.Interaction.EdgeMargin,
    }, participant)
    saved.start = start
    saved.target = {X = targetX, Y = targetY, Z = start.Z}
    saved.startYaw = startYaw
    saved.targetYaw = Manager.Face(participant.FaceIndex).yaw
    saved.alignStart = UGCGameSystem.GetTimeSeconds(pc)
    saved.aligned = false
    pcall(function()
        pawn:K2_SetActorRelativeLocation(start, false, {}, true)
        pawn:K2_SetActorRelativeRotation({Pitch = 0, Yaw = startYaw, Roll = 0}, false, {}, true)
    end)
    setMoveIgnore(pawn.CapsuleComponent, actor, true)
    setMoveIgnore(actor.CrateCollision, pawn, true)
    hold = saved
    pawn.bUseControllerRotationYaw = false
    pawn.bUseControllerRotationPitch = false
    pawn.bUseControllerRotationRoll = false
    setMovementLocked(pawn, saved, true)
    log('attached local player=' .. tostring(participant.PlayerKey))
    return true
end
local function nextSequence(controller)
    controller.PushPullClientSequence = (controller.PushPullClientSequence or 0) + 1
    return controller.PushPullClientSequence
end

local function sendIntent(current, intent, now)
    local pawn = current.pawn
    if not (valid(pawn) and valid(current.controller)) then return end
    local changed = current.lastIntent ~= intent
    local heartbeat = intent ~= 0 and now - (current.lastIntentAt or 0) >= Config.Input.Heartbeat
    if not changed and not heartbeat then return end
    current.lastIntent = intent
    current.lastIntentAt = now
    UnrealNetwork.CallUnrealRPC(current.controller, current.controller, 'ServerSetPushPullIntent',
        current.actor, current.sessionId, intent, nextSequence(current.controller))
end

local function tick()
    local current = hold
    if not current then return end
    local pawn = current.pawn
    if not (valid(pawn) and valid(current.actor)) then release('ACTOR_UNAVAILABLE'); return end
    local now = UGCGameSystem.GetTimeSeconds(pawn)
    if type(now) ~= 'number' then return end
    if not current.aligned then
        local progress = math.max(0, math.min(1, (now - current.alignStart) / Config.Action.AlignDuration))
        local x = current.start.X + (current.target.X - current.start.X) * progress
        local y = current.start.Y + (current.target.Y - current.start.Y) * progress
        local z = current.start.Z + (current.target.Z - current.start.Z) * progress
        local yaw = current.startYaw + (current.targetYaw - current.startYaw) * progress
        pcall(function()
            pawn:K2_SetActorRelativeLocation({X = x, Y = y, Z = z}, false, {}, true)
            pawn:K2_SetActorRelativeRotation({Pitch = 0, Yaw = yaw, Roll = 0}, false, {}, true)
        end)
        if progress >= 1 then
            current.aligned = true
            log('alignment complete player=' .. tostring(current.participant.PlayerKey))
        end
    else
        pcall(function()
            pawn:K2_SetActorRelativeRotation({Pitch = 0, Yaw = current.targetYaw, Roll = 0}, false, {}, true)
        end)
    end
    Animation.UpdateRate(current.actor, current.state)
    local raw = UGCInputSystem.GetInputValue(pawn, Config.Input.Tag)
    local intent = 0
    if type(raw) == 'number' and raw > Config.Input.Deadzone then intent = 1
    elseif type(raw) == 'number' and raw < -Config.Input.Deadzone then intent = -1 end
    sendIntent(current, intent, now)
end

function P.Apply(actor, state)
    if not valid(actor) then return end
    Animation.Sync(actor, state)
    local pc = localController()
    local key = localKey(pc)
    local pawn = localPawn()
    local participant = participantOf(state, key)
    if participant and valid(pawn) then
        if not hold or hold.actor ~= actor or hold.pawn ~= pawn or hold.sessionId ~= state.SessionId then
            acquire(actor, state, participant, pc, pawn)
        else
            hold.participant = participant
            hold.state = state
        end
    elseif hold and hold.actor == actor then
        release('PARTICIPANT_REMOVED')
    end
    if not timer then
        timer = UGCTimerUtility.CreateLuaTimer(Config.Interaction.PositionInterval, tick, true,
            'EscapeX.PushPull.Presentation')
    end
end

function P.RefreshLocal()
    local pc = localController()
    local key = localKey(pc)
    local pawn = localPawn()
    if not (valid(pc) and valid(pawn) and key >= 0) then return false end
    local cls = UE.LoadClass(Config.Interaction.CrateClassPath)
    if not cls then
        log('crate class unavailable: ' .. tostring(Config.Interaction.CrateClassPath))
        return false
    end
    for _, actor in pairs(UGCActorComponentUtility.GetAllActorsOfClass(pawn, cls)) do
        local state = actor.CrateState
        if participantOf(state, key) then
            P.Apply(actor, state)
            return true
        end
    end
    return false
end

function P.End(actor)
    if hold and (not actor or hold.actor == actor) then release('END') end
    if actor then Animation.ClearActor(actor) end
end

function P.Monitor()
    if monitorTimer then return end
    monitorTimer = UGCTimerUtility.CreateLuaTimer(Config.Interaction.MonitorInterval, function()
        local pawn = localPawn()
        if pawn == watchedPawn then return end
        if watchedPawn then release('PAWN_CHANGED') end
        watchedPawn = pawn
        if valid(pawn) then P.RefreshLocal() end
    end, true, 'EscapeX.PushPull.PresentationMonitor')
end

function P.StopMonitor()
    if monitorTimer then
        UGCTimerUtility.RemoveLuaTimer(monitorTimer)
        monitorTimer = nil
    end
    release('STOP_MONITOR')
    watchedPawn = nil
    if timer then
        UGCTimerUtility.RemoveLuaTimer(timer)
        timer = nil
    end
end

return P
