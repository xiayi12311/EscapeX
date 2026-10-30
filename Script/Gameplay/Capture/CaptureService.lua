-- Engine adapter for capture/carry/imprison. Public entry points are server-only;
-- all gameplay decisions live in CaptureManager. This file only translates between
-- the manager and the engine: player lookups, replicated payloads, attachment, states.
local Manager = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureManager')
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureConfig')
local HT = UGCGameSystem.UGCRequire('Script.AI.HeadTeacher.HTCommon')
local Service = {}

local LOG = '[HTCapture]'
local active = nil        -- the manager owned by the GameMode, kept for emit's error paths

local function log(text) ugcprint(LOG .. ' ' .. tostring(text)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

-- Measured 2026-10-26 on this DS: UGCGameSystem.GetServerTimeSec() returns whole epoch
-- seconds (two samples 0.1s apart differ by 0.000000), so every sub-second rule silently
-- degenerates to a 1-second throttle (struggle interval, pickup/put-down beats, rescue
-- duration). GetTimeSeconds is the float world clock: same reading as
-- KismetSystemLibrary.GetGameTimeInSeconds, 0.100220 over 0.1s.
local clockWarned = false
local function makeClock(world)
    return function()
        local ok, t = pcall(function() return UGCGameSystem.GetTimeSeconds(world) end)
        if ok and type(t) == 'number' then return t end
        -- A frozen clock silently stops every timer in the state machine, so say it once.
        if not clockWarned then
            clockWarned = true
            log('CLOCK UNAVAILABLE (GetTimeSeconds failed): all capture timings are frozen')
        end
        return 0
    end
end

local function pawnOf(key)
    local ok, pawn = pcall(function() return UGCGameSystem.GetPlayerPawnByPlayerKey(key) end)
    if not ok or not valid(pawn) then return nil end
    return pawn
end

local function keyOf(controller)
    if not valid(controller) then return -1 end
    local ok, key = pcall(function()
        return UGCGameSystem.GetPlayerKeyByPlayerController(controller)
    end)
    if ok and type(key) == 'number' then return key end
    return -1
end

-- The captured player must be alive and still in the round. Health alone is not
-- enough: an eliminated player keeps a valid pawn handle for a short while.
local function validatePlayer(key)
    local pawn = pawnOf(key)
    if not pawn then return false, 'PLAYER_UNAVAILABLE' end
    local okAlive, alive = pcall(function() return UGCPlayerStateSystem.IsAlive(key) end)
    if not (okAlive and alive) then return false, 'PLAYER_DEAD' end
    local okExit, exited = pcall(function() return UGCPlayerStateSystem.IsExit(key) end)
    if okExit and exited then return false, 'PLAYER_UNAVAILABLE' end
    return true
end

-- A rescuer has to be a living player standing inside the post's radius.
local function validateRescuer(post, key, radius)
    local pawn = pawnOf(key)
    if not pawn then return false, 'RESCUER_UNAVAILABLE' end
    local okAlive, alive = pcall(function() return UGCPlayerStateSystem.IsAlive(key) end)
    if not (okAlive and alive) then return false, 'RESCUER_DEAD' end
    if not (post and valid(post.actor) and valid(post.actor.BindPoint)) then
        return false, 'POST_UNAVAILABLE'
    end
    local point = post.actor.BindPoint:K2_GetComponentLocation()
    local p = pawn:K2_GetActorLocation()
    local dx, dy, dz = p.X - point.X, p.Y - point.Y, p.Z - point.Z
    if dx * dx + dy * dy + dz * dz > radius * radius then return false, 'RESCUER_TOO_FAR' end
    return true
end

-- Imprisonment also activates the engine's team-damage punishment warning. Gameplay
-- capture instead owns one disable reference per action (raw/api/1947713df52a.json).
-- Removing our references preserves locks owned by other skills. Interacting stays
-- enabled so the prisoner can still use the native break-free button.
local controlTags = {
    'PawnState.Movement.Walking', 'PawnState.Action.Sprint',
    'PawnState.Action.Jump', 'PawnState.Action.Vault',
    'PawnState.Action.HoldWeapon', 'PawnState.Action.HoldGrenade',
    'PawnState.Action.MeleeAttack', 'PawnState.Action.Pick',
    'PawnState.Action.SwitchWeapon', 'PawnState.Action.UseConsumables',
    'PawnState.Gun.GunFire', 'PawnState.Gun.GunADS',
    'PawnState.Pose.Crouch', 'PawnState.Pose.Prone',
}
local controlLocks = {}
local function setFrozen(pawn, frozen)
    if pawn == nil then return false end
    if not valid(pawn) then controlLocks[pawn] = nil; return false end
    if frozen and controlLocks[pawn] then return true end
    if not frozen then
        local tags = controlLocks[pawn]
        if not tags then return true end
        for _, tag in ipairs(tags) do
            UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, false, false)
        end
        controlLocks[pawn] = nil
        return true
    end
    local acquired = {}
    local ok, err = pcall(function()
        for _, tag in ipairs(controlTags) do
            assert(UGCGameplayTagSystem.IsValidTag(tag), 'invalid capture control tag: ' .. tag)
            UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, true, true)
            acquired[#acquired + 1] = tag
        end
    end)
    controlLocks[pawn] = acquired
    if not ok then
        setFrozen(pawn, false)
        log('capture control lock failed: ' .. tostring(err))
        return false
    end
    return true
end

local function setInvincible(pawn, on)
    if not valid(pawn) then return end
    pcall(function() return UGCPlayerPawnSystem.SetIsInvincible(pawn, on) end)
end

-- Server-side attach keeps the authoritative position glued to the carrier. The
-- owning client attaches its own pawn locally for the visual (CapturePresentation):
-- measured 2026-10-26 that a server-only attach tracks on the server but does not
-- move the player on their own screen, so both ends must attach.
local function attach(pawn, actor, socketName)
    if not (valid(pawn) and valid(actor)) then return false, 'INVALID_ACTOR' end
    if socketName and socketName ~= '' and valid(actor.Mesh) then
        local okSocket, exists = pcall(function() return actor.Mesh:DoesSocketExist(socketName) end)
        if not (okSocket and exists) then return false, 'SOCKET_MISSING' end
        local ok, err = pcall(function() return pawn:K2_AttachToActor(actor, socketName, 2, 2, 2, false) end)
        if not ok then return false, tostring(err) end
        if err == false then return false, 'ATTACH_RETURNED_FALSE' end
        return true
    end
    if valid(actor.BindPoint) then
        local ok, err = pcall(function()
            return pawn:K2_AttachToComponent(actor.BindPoint, '', 2, 2, 2, false)
        end)
        if not ok then return false, tostring(err) end
        if err == false then return false, 'ATTACH_RETURNED_FALSE' end
        return true
    end
    return false, 'NO_ATTACH_TARGET'
end

local function detach(pawn)
    if not valid(pawn) then return end
    pcall(function() return pawn:K2_DetachFromActor(2, 2, 2) end)
end

-- Measured 2026-10-26: while attached, the carried pawn kept simulating Walking
-- (CharacterMovement.UpdatedComponent is the same RootComponent that is attached,
-- MovementMode=1 on both ends), and its relative offset drifted monotonically by
-- hundreds of centimetres as the carrier walked. A carried body must not run its own
-- ground movement; restore it only after the detach, on every exit path.
local movementTicks = {} -- pawn -> tick state owned by this capture
local function setSimulatedMovement(pawn, on)
    if not valid(pawn) then if pawn then movementTicks[pawn] = nil end; return end
    local ok, err = pcall(function()
        local cm = pawn.CharacterMovement
        if cm == nil then error('captured pawn has no CharacterMovement') end
        if not on then
            if movementTicks[pawn] == nil then
                movementTicks[pawn] = {enabled = cm:IsComponentTickEnabled()}
            end
            cm:SetMovementMode(0) -- MOVE_None
            -- Native 2026-10-27: None alone still drifted ~7 m in 8 s. Suspending
            -- movement Tick on both ends removed it (DS 0, client <0.003 cm).
            cm:SetComponentTickEnabled(false)
        else
            cm:SetMovementMode(1) -- Walking, after detach
            local saved = movementTicks[pawn]
            if saved then
                cm:SetComponentTickEnabled(saved.enabled)
                movementTicks[pawn] = nil
            end
        end
    end)
    if not ok then log('setSimulatedMovement(' .. tostring(on) .. ') failed: ' .. tostring(err)) end
end

-- BindPoint cannot be raised through the editor scripting layer (RelativeLocation is
-- a struct property this binding refuses to set), so the bind height is a post
-- variable applied after attaching. Designers can also move BindPoint in the BP.
local function applyBindOffset(pawn, offset)
    if not valid(pawn) then return false end
    if not offset or offset == 0 then return true end
    local ok, err = pcall(function()
        return pawn:K2_SetActorRelativeLocation({X = 0, Y = 0, Z = offset}, false, {}, true)
    end)
    if not ok then log('bind offset failed: ' .. tostring(err)) end
    return ok
end

local function bindHeight(post)
    if post and valid(post.actor) then
        local v = post.actor.BindHeightOffset
        if type(v) == 'number' then return v end
    end
    return Config.Defaults.BindHeightOffset
end

local function placeAt(pawn, location)
    if not (valid(pawn) and location) then return false end
    -- bTeleport is required: UGCActorComponentUtility.SetActorLocation does not
    -- move Pawns (measured, recipes/chase-moveto-stutter.md).
    local ok, err = pcall(function() return pawn:K2_SetActorLocation(location, false, {}, true) end)
    if not ok then log('place failed: ' .. tostring(err)) end
    return ok
end

-- Replicated payloads. Whole-table replacement, one atomic synced field per actor
-- (same contract as the searchable desk). The monster only advertises a holder while
-- it is actually carrying: once the player is bound, the post owns them, and leaving
-- a stale "Imprisoned" on the monster would outlive the escort forever.
local function publishMonster(monster, data)
    if not valid(monster) then return end
    local held = (data.State == 'Grabbing' or data.State == 'Carrying' or data.State == 'PuttingDown')
    local current = monster.HTCaptureState
    if not held then
        -- The monster is freed from a session as soon as the player is bound, so it can
        -- be escorting somebody new when an older session finally releases. Never clear
        -- another session's state.
        if current and current.SessionId and current.SessionId ~= data.SessionId then return end
        monster.HTCaptureState = {PlayerKey = -1, Stage = 'None', SessionId = -1,
            Revision = data.Revision,
            VisionSignature = current and current.VisionSignature,
            VisionPlayerKeys = current and current.VisionPlayerKeys}
        return
    end
    monster.HTCaptureState = {
        SessionId = data.SessionId, PlayerKey = data.PlayerKey, PostId = data.PostId,
        Stage = data.State, Revision = data.Revision, CarrySocket = data.CarrySocket,
        VisionSignature = current and current.VisionSignature,
        VisionPlayerKeys = current and current.VisionPlayerKeys,
    }
end

local function publishPost(post, data)
    if not valid(post.actor) then return end
    -- SessionId must ride on every payload, including Free: the client's staleness guard
    -- treats a new session as permission to accept a lower revision, which is what
    -- happens after the service is rebuilt without restarting the clients.
    if data.State ~= 'Imprisoned' then
        post.actor.PrisonState = {PlayerKey = -1, State = 'Free', PostId = post.id,
            SessionId = data.SessionId, Revision = data.Revision}
        return
    end
    -- Durations, not absolute timestamps: the world clock restarts per machine, so a
    -- client-side countdown built from server time would be wrong. Enforcement stays on
    -- the server regardless of what a display shows.
    local wait = nil
    if data.StruggleExpiresAt then
        wait = math.max(0, data.StruggleExpiresAt - UGCGameSystem.GetTimeSeconds(post.actor) )
    end
    local rescueLeft = nil
    if data.RescueEndsAt then
        rescueLeft = math.max(0, data.RescueEndsAt - UGCGameSystem.GetTimeSeconds(post.actor))
    end
    post.actor.PrisonState = {
        PlayerKey = data.PlayerKey, State = data.State, PostId = post.id,
        SessionId = data.SessionId,
        Revision = data.Revision, Struggle = data.Struggle, StruggleNeed = data.StruggleNeed,
        StruggleReady = data.StruggleReady, StruggleWaitSeconds = wait,
        RescuerKey = data.RescuerKey, RescueSeconds = rescueLeft,
        RescueDuration = data.RescueDuration,
    }
end

local function failSession(sessionId, reason)
    if not active then
        log('cannot fail session ' .. tostring(sessionId) .. ': service already shut down')
        return
    end
    active:Release(sessionId, reason)
    active:FlushEvents()
end

-- Cleanup has to target the pawn that was captured, not whatever GetPlayerPawnByPlayerKey
-- happens to return at release time (respawn or a transient lookup failure would otherwise
-- leave the frozen/invincible flags set on the old pawn forever).
local pawnsBySession = {}
local function pawnFor(data)
    local cached = pawnsBySession[data.SessionId]
    if cached and valid(cached) then return cached end
    local pawn = pawnOf(data.PlayerKey)
    if pawn then pawnsBySession[data.SessionId] = pawn end
    return pawn
end

local function emit(data, kind, reason, post, monster)
    local pawn = pawnFor(data)
    if kind == 'SessionStarted' then
        -- Freeze at the grab itself: waiting for Carrying leaves the pickup window open
        -- and the player can walk out of reach before being attached.
        if not setFrozen(pawn, true) then
            failSession(data.SessionId, 'CONTROL_LOCK_FAILED')
            return
        end
        setInvincible(pawn, true)
    elseif kind == 'Carrying' then
        setSimulatedMovement(pawn, false)
        local ok, err = attach(pawn, monster, data.CarrySocket)
        if not ok then
            log('server carry attach failed (' .. tostring(err) .. '); releasing session')
            setSimulatedMovement(pawn, true)
            failSession(data.SessionId, 'CARRY_ATTACH_FAILED')
            -- failSession already emitted Released; publishing the stale Carrying
            -- snapshot afterwards would re-attach the player on their own client.
            return
        end
    elseif kind == 'Imprisoned' then
        detach(pawn)
        local ok, err = attach(pawn, post and post.actor or nil, nil)
        if not ok then
            -- A post without a usable bind point cannot hold anyone: say so and let
            -- the player go instead of pretending the bind happened.
            log('post bind failed (' .. tostring(err) .. ') for ' .. tostring(post and post.id)
                .. '; releasing player')
            failSession(data.SessionId, 'POST_BIND_FAILED')
            return
        end
        if not applyBindOffset(pawn, bindHeight(post)) then
            failSession(data.SessionId, 'POST_BIND_OFFSET_FAILED')
            return
        end
    elseif kind == 'Released' then
        setFrozen(pawn, false)
        setInvincible(pawn, false)
        detach(pawn)
        setSimulatedMovement(pawn, true)
        -- Only a player who was actually bound gets re-anchored at the post; an escort
        -- that failed halfway must be released where they stand (plan section 7).
        if data.WasBound and post and post.location then
            placeAt(pawn, {X = post.location.X, Y = post.location.Y,
                Z = post.location.Z + bindHeight(post)})
        end
        pawnsBySession[data.SessionId] = nil
    end
    publishMonster(monster, data)
    if post then publishPost(post, data) end
    if not pawn and kind ~= 'SessionStarted' then
        log('no pawn handle for player=' .. tostring(data.PlayerKey) .. ' kind=' .. tostring(kind)
            .. '; state bookkeeping only')
    end
    log(string.format('kind=%s player=%s post=%s reason=%s rev=%s', tostring(kind),
        tostring(data.PlayerKey), tostring(data.PostId), tostring(reason), tostring(data.Revision)))
end

function Service.GetManager(gm)
    if not valid(gm) or not gm:HasAuthority() then return nil, 'SERVER_ONLY' end
    return gm.CaptureManager
end

function Service.Setup(gm)
    if not (valid(gm) and gm:HasAuthority()) or gm.CaptureManager then return end
    local clock = makeClock(gm)
    gm.CaptureManager = Manager.new({
        now = clock,
        validatePlayer = validatePlayer,
        validateRescuer = validateRescuer,
        emit = emit,
        log = log,
    }, Config)
    active = gm.CaptureManager
    log(string.format('clock source=%s first read=%.4f', 'UGCGameSystem.GetTimeSeconds', clock()))
    gm.CaptureTimer = UGCTimerUtility.CreateLuaTimer(0.1, function()
        if not valid(gm) or not gm.CaptureManager then return end
        gm.CaptureManager:Update()
    end, true, 'EscapeX.Capture.Update')
    log('server service initialized')
end

function Service.Shutdown(gm)
    if valid(gm) and gm.CaptureManager then
        gm.CaptureManager:ReleaseAll('SERVER_SHUTDOWN')
        gm.CaptureManager = nil
    end
    active = nil
    if valid(gm) and gm.CaptureTimer then
        UGCTimerUtility.RemoveLuaTimer(gm.CaptureTimer)
        gm.CaptureTimer = nil
    end
end

-- Post identity. The blueprint's PostId is an IntProperty (this build's
-- blueprint_add_member_variable maps the 'str' keyword to int and the variable cannot
-- be removed or retyped from the scripting layer), and Lua treats 0 as truthy, so the
-- id must be resolved by type and value - a plain `actor.PostId or name` would make
-- every unconfigured post collide on id 0.
local function postIdOf(actor)
    local configured = actor.PostId
    if type(configured) == 'string' and configured ~= '' then
        return configured
    end
    if type(configured) == 'number' and configured > 0 then
        return tostring(math.floor(configured))
    end
    return KismetSystemLibrary.GetObjectName(actor)
end

function Service.RegisterPost(gm, actor)
    local m, reason = Service.GetManager(gm)
    if not m then return false, reason or 'SERVICE_NOT_READY' end
    if not valid(actor) then return false, 'INVALID_POST' end
    if not valid(actor.BindPoint) then return false, 'POST_MISSING_BIND_POINT' end
    local id = postIdOf(actor)
    local location = actor:K2_GetActorLocation()
    local ok, detail = m:RegisterPost(actor, id, {
        Location = {X = location.X, Y = location.Y, Z = location.Z},
        RescueRadius = actor.RescueRadius,
        RescueDuration = actor.RescueDuration,
        StrugglePresses = actor.StrugglePresses,
    })
    m:FlushEvents()
    if ok then log('post registered id=' .. tostring(id)) end
    return ok, detail
end

function Service.UnregisterPost(gm, actor)
    local m, reason = Service.GetManager(gm)
    if not m then return false, reason or 'SERVICE_NOT_READY' end
    local ok, detail = m:UnregisterPost(actor)
    m:FlushEvents()
    return ok, detail
end

function Service.StartCapture(gm, monster, target)
    local m, reason = Service.GetManager(gm)
    if not m then return false, reason or 'SERVICE_NOT_READY' end
    if not (valid(monster) and valid(target)) then return false, 'INVALID_ACTOR' end
    local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(target)
    if key == nil or key < 0 then return false, 'INVALID_PLAYER_KEY' end
    local socket = HT.config(monster, 'HTCarrySocket')
    local okSocket, exists = pcall(function()
        return valid(monster.Mesh) and monster.Mesh:DoesSocketExist(socket)
    end)
    if not (okSocket and exists) then return false, 'CARRY_SOCKET_MISSING' end
    local started, sessionId = m:StartSession(key, monster, {
        PickupDuration = HT.config(monster, 'HTPickupDuration'),
        PutDownDuration = HT.config(monster, 'HTPutDownDuration'),
        EscortTimeout = HT.config(monster, 'HTEscortTimeout'),
        ImprisonDuration = HT.config(monster, 'HTImprisonDuration'),
        StruggleInterval = HT.config(monster, 'HTStruggleInterval'),
        EscortSpeed = HT.config(monster, 'HTEscortSpeed'),
        ArriveRadius = HT.config(monster, 'HTArriveRadius'),
        CarrySocket = socket,
    }, nil)
    m:FlushEvents()
    if started and not m:GetSnapshot(sessionId) then
        return false, 'CONTROL_LOCK_FAILED'
    end
    -- StartSession rejects duplicate/invalid grabs. Notify once, only after the
    -- SessionStarted effects succeeded; later carry/bind/release stages do not reset.
    if started then gm:OnPlayerCaptured(key, sessionId) end
    log((started and 'capture started player=' or 'capture refused player=') .. tostring(key)
        .. ' result=' .. tostring(sessionId))
    return started and true or false, sessionId
end

function Service.SessionOfMonster(gm, monster)
    local m = Service.GetManager(gm)
    if not m then return nil end
    local s = m:SessionOfMonster(monster)
    return s and s.id or nil
end

function Service.Snapshot(gm, sessionId)
    local m = Service.GetManager(gm)
    if not m then return nil end
    return m:GetSnapshot(sessionId)
end

function Service.NearestFreePosts(gm, fromVec, limit)
    local m = Service.GetManager(gm)
    if not m then return {}, 'SERVICE_NOT_READY' end
    return m:NearestFreePosts(fromVec, limit)
end

-- Read-only access to an already claimed post (free-post listings exclude it).
function Service.PostById(gm, postId)
    local m = Service.GetManager(gm)
    if not m then return nil end
    return m.posts[postId]
end

function Service.ClaimPost(gm, sessionId, postId)
    local m = Service.GetManager(gm)
    if not m then return false, 'SERVICE_NOT_READY' end
    local ok, detail = m:ClaimPost(sessionId, postId)
    m:FlushEvents()
    return ok, detail
end

function Service.MarkArrived(gm, sessionId)
    local m = Service.GetManager(gm)
    if not m then return false, 'SERVICE_NOT_READY' end
    local ok, detail = m:MarkArrived(sessionId)
    m:FlushEvents()
    return ok, detail
end

function Service.CancelMonster(gm, monster, reason)
    local m = Service.GetManager(gm)
    if not m then return false, 'SERVICE_NOT_READY' end
    local ok, detail = m:CancelMonster(monster, reason or 'MONSTER_DESTROYED')
    m:FlushEvents()
    return ok, detail
end

function Service.CancelPlayer(gm, playerKeyOrController, reason)
    local m = Service.GetManager(gm)
    if not m then return false, 'SERVICE_NOT_READY' end
    local key = playerKeyOrController
    if type(key) ~= 'number' then key = keyOf(playerKeyOrController) end
    if key == nil or key < 0 then return false, 'INVALID_PLAYER_KEY' end
    local ok, detail = m:CancelPlayer(key, reason or 'PLAYER_UNAVAILABLE')
    m:FlushEvents()
    return ok, detail
end

-- Bound player mashing the post's struggle action.
function Service.Struggle(gm, post, pc)
    local m, reason = Service.GetManager(gm)
    if not m then return false, reason or 'SERVICE_NOT_READY' end
    if not valid(post) then return false, 'INVALID_POST' end
    local key = keyOf(pc)
    if key < 0 then return false, 'INVALID_PLAYER_KEY' end
    local d = m:FindPost(post)
    if not d or not d.session then return false, 'NOT_IMPRISONED' end
    local snapshot = m:GetSnapshot(d.session)
    if not snapshot or snapshot.PlayerKey ~= key then return false, 'NOT_PRISONER' end
    -- count and need are what a progress display consumes
    local ok, count, need = m:RegisterStruggle(key)
    m:FlushEvents()
    return ok, count, need
end

-- Exposed for blueprint shells that must resolve a controller to a PlayerKey in their
-- Check callbacks; keeps the pcall discipline in one place.
function Service.KeyOf(controller)
    return keyOf(controller)
end

-- Same questions the rescue action will be judged by, so the button never offers what
-- the server is about to reject: a player standing just outside the radius would
-- otherwise click, be refused, and see nothing happen.
function Service.CanRescue(gm, post, pc)
    local m = Service.GetManager(gm)
    if not m then return false, 'SERVICE_NOT_READY' end
    if not valid(post) then return false, 'INVALID_POST' end
    local d = m:FindPost(post)
    if not d or not d.session then return false, 'NOT_IMPRISONED' end
    local snapshot = m:GetSnapshot(d.session)
    if not snapshot then return false, 'NOT_IMPRISONED' end
    local key = keyOf(pc)
    if key < 0 then return false, 'INVALID_PLAYER_KEY' end
    if key == snapshot.PlayerKey then return false, 'SELF_RESCUE' end
    if m:IsBusy(key) then return false, 'RESCUER_BUSY' end
    return validateRescuer(d, key, d.rescueRadius)
end

-- Teammate pressing the post's rescue action; progress then runs on the server clock.
function Service.Rescue(gm, post, pc)
    local m, reason = Service.GetManager(gm)
    if not m then return false, reason or 'SERVICE_NOT_READY' end
    if not valid(post) then return false, 'INVALID_POST' end
    local rescuer = keyOf(pc)
    if rescuer < 0 then return false, 'INVALID_PLAYER_KEY' end
    local d = m:FindPost(post)
    if not d or not d.session then return false, 'NOT_IMPRISONED' end
    local snapshot = m:GetSnapshot(d.session)
    if not snapshot then return false, 'NOT_IMPRISONED' end
    local ok, detail = m:StartRescue(snapshot.PlayerKey, rescuer)
    m:FlushEvents()
    return ok, detail
end

-- Elimination and disconnect events hand over either a controller or a pawn; take
-- whichever resolves (same fallback the auto-revive helper uses).
function Service.CancelVictim(gm, controller, pawn, reason)
    local key = -1
    local okC, c = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerController(controller) end)
    if okC and valid(controller) and type(c) == 'number' then key = c end
    if key < 0 then
        local okP, p = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerPawn(pawn) end)
        if okP and valid(pawn) and type(p) == 'number' then key = p end
    end
    if key < 0 then return false, 'INVALID_PLAYER_KEY' end
    return Service.CancelPlayer(gm, key, reason)
end

-- Read-only helpers for the interaction Check callbacks.
function Service.PrisonerOf(gm, post)
    local m = Service.GetManager(gm)
    if not m then return nil end
    local d = m:FindPost(post)
    if not d or not d.session then return nil end
    return m:GetSnapshot(d.session)
end

function Service.IsBusy(gm, playerKey)
    local m = Service.GetManager(gm)
    if not m then return false end
    return m:IsBusy(playerKey)
end

return Service
