---@class BP_RedLightDetector_C:ActivityBaseActor
---@field HorizontalArrow UArrowComponent
---@field SightOrigin USceneComponent
---@field DirectionArrow UArrowComponent
---@field ScanCone UStaticMeshComponent
---@field DefaultSceneRoot USceneComponent
---@field DetectionEnabled bool
---@field ViewDistance float
---@field ViewFullAngle float
---@field DetectionInterval float
---@field DetectionDelay float
---@field SightChannel int32
---@field TargetBoundsHeightRatio float
---@field PlayerPawnChannel int32
---@field SweepHalfAngle float
---@field SweepDegreesPerSecond float
---@field SweepEndpointPause float
---@field SweepReplicationInterval float
---@field SweepYaw float
---@field RedLightCheckpointTag FString
---@field CheckpointOffsetX float
---@field CheckpointOffsetY float
---@field CheckpointOffsetZ float
---@field TeleportCooldown float
---@field DebugDraw bool
---@field RedLightCheckpointClass FString
--Edit Below--
local Detector = {}

local LOG = '[RedLightDetector]'
local CLIENT_SWEEP_INTERVAL = 0
local SERVER_SWEEP_INTERVAL = 1 / 20
local CLIENT_CORRECTION_RATE = 2
local CLIENT_MAX_CORRECTION_STEP = 0.08
local CLIENT_MAX_CORRECTION_ANGLE = 12
local DEFAULTS = {
    ViewDistance = 1000,
    ViewFullAngle = 60,
    DetectionInterval = 0.1,
    DetectionDelay = 1.0,
    SightChannel = 3,
    TargetBoundsHeightRatio = 0.65,
    PlayerPawnChannel = 16,
    SweepHalfAngle = 45,
    SweepDegreesPerSecond = 30,
    SweepEndpointPause = 0.5,
    SweepReplicationInterval = 0.2,
    RedLightCheckpointTag = 'RedLightDetector.Checkpoint',
    RedLightCheckpointClass = 'Asset/Blueprint/Prefabs/Triggers/BP_RedLightCheckpoint.BP_RedLightCheckpoint_C',
    TeleportCooldown = 2,
}

local function valid(obj)
    return obj ~= nil and KismetSystemLibrary.IsValid(obj)
end

local function log(message)
    ugcprint(LOG .. ' ' .. tostring(message))
end

local function config(self, key)
    local value = self[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function angleDelta(fromYaw, toYaw)
    local delta = toYaw - fromYaw
    while delta > 180 do delta = delta - 360 end
    while delta < -180 do delta = delta + 360 end
    return delta
end

local function sweepYawAt(self, elapsed)
    local halfAngle = math.max(0, tonumber(config(self, 'SweepHalfAngle')) or 0)
    if halfAngle <= 0 then return 0 end
    local speed = math.max(0.01, tonumber(config(self, 'SweepDegreesPerSecond')) or 30)
    local pause = math.max(0, tonumber(config(self, 'SweepEndpointPause')) or 0)
    local travel = halfAngle / speed
    local cycle = 4 * travel + 2 * pause
    local phase = elapsed % cycle
    if phase <= travel then
        return halfAngle * phase / travel
    end
    phase = phase - travel
    if phase <= pause then
        return halfAngle
    end
    phase = phase - pause
    if phase <= 2 * travel then
        return halfAngle * (1 - phase / travel)
    end
    phase = phase - 2 * travel
    if phase <= pause then
        return -halfAngle
    end
    phase = phase - pause
    return -halfAngle + halfAngle * phase / travel
end

local function applySweep(self, yaw)
    local pivot = self.SightOrigin
    local cone = self.ScanCone
    if not valid(pivot) or not valid(cone) then return end
    -- Rotate a component-space pivot at the actor origin. Keeping the cone's
    -- pitch fixed avoids composing dynamic yaw with a 90-degree pitch every
    -- frame, which produces visibly uneven motion near gimbal lock.
    pivot:K2_SetRelativeRotation({Roll = 0, Pitch = 0, Yaw = yaw}, false, {}, false)
end

local function configureCone(self)
    local pivot = self.SightOrigin
    local cone = self.ScanCone
    if not valid(pivot) or not valid(cone) then return false end
    local length = math.max(1, tonumber(config(self, 'ViewDistance')) or 1000)
    local fullAngle = clamp(tonumber(config(self, 'ViewFullAngle')) or 60, 1, 179)
    local diameter = 2 * length * math.tan(math.rad(fullAngle / 2))
    local halfLength = length / 2
    local attached = cone:K2_AttachToComponent(pivot, '', 2, 2, 2, false)
    if attached == false then
        log('ERROR: ScanCone could not attach to SightOrigin')
        return false
    end
    cone:K2_SetRelativeRotation({Roll = 0, Pitch = 90, Yaw = 0}, false, {}, false)
    cone:K2_SetRelativeLocation({X = halfLength, Y = 0, Z = 0}, false, {}, false)
    cone:SetRelativeScale3D({
        X = diameter / 100,
        Y = diameter / 100,
        Z = length / 100,
    })
    return true
end

local function setupCone(self)
    local cone = self.ScanCone
    if not valid(cone) then
        log('ERROR: ScanCone is missing')
        return false
    end
    local channel = math.floor(tonumber(config(self, 'PlayerPawnChannel')) or 16)
    cone:SetCollisionEnabled(self:HasAuthority() and 1 or 0)
    cone:SetCollisionResponseToAllChannels(0)
    cone:SetCollisionResponseToChannel(channel, 1)
    cone.bGenerateOverlapEvents = true
    if not configureCone(self) then return false end
    applySweep(self, tonumber(self.SweepYaw) or 0)
    return true
end

local function isAlive(target)
    local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(target)
    if key == nil or key < 0 then return false end
    local okAlive, alive = pcall(function() return UGCPlayerStateSystem.IsAlive(key) end)
    if not (okAlive and alive) then return false end
    local okExit, exited = pcall(function() return UGCPlayerStateSystem.IsExit(key) end)
    if okExit and exited then return false end
    return true
end

local function busyPlayer(key)
    local ok, mode = pcall(function() return UGCGameSystem.GetGameMode() end)
    if not (ok and valid(mode) and mode.CaptureManager) then return false end
    return mode.CaptureManager:IsBusy(key) == true
end

local function sightPoint(self, target)
    local center, extent = {}, {}
    target:GetActorBounds(true, center, extent)
    local ratio = clamp(tonumber(config(self, 'TargetBoundsHeightRatio')) or 0.65, 0, 1)
    if type(center.X) ~= 'number' or type(center.Y) ~= 'number'
        or type(center.Z) ~= 'number' or type(extent.Z) ~= 'number' then
        return nil
    end
    return {X = center.X, Y = center.Y, Z = center.Z + extent.Z * ratio}
end

local function canSee(self, target)
    if not valid(target) or not isAlive(target) then return false end
    local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(target)
    if key == nil or key < 0 or busyPlayer(key) then return false end
    local destination = sightPoint(self, target)
    if not destination then return false end
    local sourceComponent = self.SightOrigin
    local source = valid(sourceComponent)
        and sourceComponent:K2_GetComponentLocation()
        or self:K2_GetActorLocation()
    local blocked = KismetSystemLibrary.LineTraceSingleByCollisionChannel(
        self,
        source,
        destination,
        math.floor(tonumber(config(self, 'SightChannel')) or 3),
        false,
        {self, target},
        config(self, 'DebugDraw') and 1 or 0,
        {},
        true,
        {R = 0, G = 1, B = 0, A = 1},
        {R = 1, G = 0, B = 0, A = 1},
        0.12
    )
    return not blocked
end

local function resolveCheckpoint(self)
    local tag = config(self, 'RedLightCheckpointTag')
    if type(tag) ~= 'string' or tag == '' then
        log('ERROR: RedLightCheckpointTag is not configured')
        return nil
    end
    local classPath = config(self, 'RedLightCheckpointClass')
    local checkpointClass = type(classPath) == 'string' and classPath ~= ''
        and UGCObjectUtility.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(classPath))
        or nil
    if not valid(checkpointClass) then
        log('ERROR: RedLightCheckpointClass could not be loaded: ' .. tostring(classPath))
        return nil
    end
    local checkpoints = {}
    for _, actor in pairs(UGCActorComponentUtility.GetAllActorsOfClass(self, checkpointClass) or {}) do
        local matches = actor.RedLightCheckpointTag == tag or actor:ActorHasTag(tag)
        if valid(actor) and matches and actor.CheckpointEnabled ~= false then
            checkpoints[#checkpoints + 1] = actor
        end
    end
    if #checkpoints == 0 then
        if not self.NextCheckpointErrorAt or self.DetectorElapsed >= self.NextCheckpointErrorAt then
            log('ERROR: no enabled checkpoint tagged ' .. tag)
            self.NextCheckpointErrorAt = self.DetectorElapsed + 5
        end
        return nil
    end
    return checkpoints[math.random(#checkpoints)]
end

local function teleportPlayer(self, pawn, key)
    local checkpoint = resolveCheckpoint(self)
    if not checkpoint then return false end
    local location = checkpoint:K2_GetActorLocation()
    local destination = {
        X = location.X + (tonumber(self.CheckpointOffsetX) or 0),
        Y = location.Y + (tonumber(self.CheckpointOffsetY) or 0),
        Z = location.Z + (tonumber(self.CheckpointOffsetZ) or 0),
    }
    pcall(function()
        if valid(pawn.CharacterMovement) then pawn.CharacterMovement:StopMovementImmediately() end
    end)
    local moved = pawn:K2_SetActorLocation(destination, false, {}, true)
    if not moved then
        log('ERROR: teleport failed player=' .. tostring(key))
        return false
    end
    local cooldown = math.max(0, tonumber(config(self, 'TeleportCooldown')) or 0)
    self.TeleportCooldowns[key] = self.DetectorElapsed + cooldown
    self.VisibleSince[pawn] = nil
    log(string.format('teleported player=%s checkpoint=%s', tostring(key),
        tostring(KismetSystemLibrary.GetObjectName(checkpoint))))
    return true
end

local function scanPlayers(self)
    if not valid(self.ScanCone) then return end
    local candidates = UGCActorComponentUtility.GetOverlappingActorsWithPrimitiveComponent(
        self.ScanCone,
        self.ScanCone:K2_GetComponentToWorld(),
        {ESceneQueryType.PlayerPawn},
        nil,
        {self}
    ) or {}
    local now = self.DetectorElapsed
    local delay = math.max(0, tonumber(config(self, 'DetectionDelay')) or 0)
    local stillVisible = {}
    for _, target in pairs(candidates) do
        if canSee(self, target) then
            stillVisible[target] = true
            local since = self.VisibleSince[target]
            if since == nil then
                since = now
                self.VisibleSince[target] = now
            end
            if now - since + 0.000001 >= delay then
                local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(target)
                local cooldownUntil = key and self.TeleportCooldowns[key] or nil
                if key and key >= 0 and (cooldownUntil == nil or now >= cooldownUntil) then
                    teleportPlayer(self, target, key)
                end
            end
        end
    end
    for target in pairs(self.VisibleSince) do
        if not stillVisible[target] then self.VisibleSince[target] = nil end
    end
end

local function sweepDelta(self)
    local now = KismetSystemLibrary.GetGameTimeInSeconds(self)
    local previous = self.LastSweepTimerTime
    self.LastSweepTimerTime = now
    if previous == nil then return 0 end
    return clamp(now - previous, 0, 0.25)
end

local function updateAuthoritySweep(self, delta)
    self.DetectorElapsed = self.DetectorElapsed + delta
    self.SweepElapsed = self.SweepElapsed + delta
    local yaw = sweepYawAt(self, self.SweepElapsed)
    applySweep(self, yaw)

    self.SweepNetworkElapsed = self.SweepNetworkElapsed + delta
    local replicateInterval = math.max(0.05,
        tonumber(config(self, 'SweepReplicationInterval')) or 0.2)
    if self.SweepNetworkElapsed >= replicateInterval then
        self.SweepNetworkElapsed = self.SweepNetworkElapsed - replicateInterval
        self.SweepYaw = yaw
    end

    if config(self, 'DetectionEnabled') ~= false then
        self.DetectionElapsed = self.DetectionElapsed + delta
        local interval = math.max(0.02, tonumber(config(self, 'DetectionInterval')) or 0.1)
        if self.DetectionElapsed >= interval then
            self.DetectionElapsed = self.DetectionElapsed - interval
            scanPlayers(self)
        end
    else
        self.VisibleSince = {}
    end
end

local function updateClientSweep(self, delta)
    self.SweepElapsed = self.SweepElapsed + delta
    local localYaw = sweepYawAt(self, self.SweepElapsed)
    -- Keep the local sweep moving continuously. The sparse authority update
    -- only adjusts a smoothed phase offset, so it never becomes a constant
    -- target that freezes the cone between network updates.
    local targetCorrection = self.TargetSweepCorrection or 0
    local correctionDelta = angleDelta(self.SweepCorrectionYaw or 0, targetCorrection)
    local alpha = math.min(CLIENT_MAX_CORRECTION_STEP, delta * CLIENT_CORRECTION_RATE)
    self.SweepCorrectionYaw = (self.SweepCorrectionYaw or 0) + correctionDelta * alpha
    self.ClientSweepYaw = localYaw + self.SweepCorrectionYaw
    applySweep(self, self.ClientSweepYaw)
end

local function startSweepTimer(self)
    local interval = self:HasAuthority() and SERVER_SWEEP_INTERVAL or CLIENT_SWEEP_INTERVAL
    local timerName = 'RedLightDetector.Sweep.' .. tostring(KismetSystemLibrary.GetObjectName(self))
    UGCTimerUtility.RemoveLuaTimerByName(timerName)
    self.SweepTimerName = timerName
    self.SweepTimer = UGCTimerUtility.CreateLuaTimer(
        interval,
        function()
            if not valid(self) then return end
            local delta = sweepDelta(self)
            if self:HasAuthority() then
                updateAuthoritySweep(self, delta)
            else
                updateClientSweep(self, delta)
            end
        end,
        true,
        timerName,
        0,
        false,
        false
    )
end

function Detector:GetReplicatedProperties()
    return 'SweepYaw'
end

function Detector:ReceiveBeginPlay()
    Detector.SuperClass.ReceiveBeginPlay(self)
    self.VisibleSince = {}
    self.TeleportCooldowns = {}
    self.DetectorElapsed = 0
    self.DetectionElapsed = 0
    self.SweepElapsed = 0
    self.SweepNetworkElapsed = 0
    self.AuthoritativeSweepYaw = tonumber(self.SweepYaw)
    self.TargetSweepCorrection = 0
    self.SweepCorrectionYaw = 0
    self.ClientSweepYaw = 0
    self.LastSweepTimerTime = KismetSystemLibrary.GetGameTimeInSeconds(self)
    if self:HasAuthority() then self.SweepYaw = 0 end
    setupCone(self)
    startSweepTimer(self)
end

function Detector:OnRep_SweepYaw()
    self.AuthoritativeSweepYaw = tonumber(self.SweepYaw)
    if self.AuthoritativeSweepYaw == nil or self.SweepElapsed == nil then return end
    local localYaw = sweepYawAt(self, self.SweepElapsed)
    self.TargetSweepCorrection = clamp(
        angleDelta(localYaw, self.AuthoritativeSweepYaw),
        -CLIENT_MAX_CORRECTION_ANGLE,
        CLIENT_MAX_CORRECTION_ANGLE
    )
end

function Detector:ReceiveTick(DeltaTime)
    Detector.SuperClass.ReceiveTick(self, DeltaTime)
end

function Detector:ReceiveEndPlay(Reason)
    if self.SweepTimer then
        UGCTimerUtility.RemoveLuaTimer(self.SweepTimer)
        self.SweepTimer = nil
    elseif self.SweepTimerName then
        UGCTimerUtility.RemoveLuaTimerByName(self.SweepTimerName)
    end
    Detector.SuperClass.ReceiveEndPlay(self, Reason)
end

return Detector
