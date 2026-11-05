---@class WBP_HTEnemyArrow_C:UUserWidget
---@field CanvasPanel_Arrow UCanvasPanel
---@field Image_Arrow UImage
---@field InScreenPnl UCanvasPanel
---@field OutScreenPnl UCanvasPanel
---@field ProgressBar_0 UProgressBar
--Edit Below--
local WBP_HTEnemyArrow = {}

local State = UGCGameSystem.UGCRequire("Script.UI.EnemyArrow.HTArrowState")
local Config = UGCGameSystem.UGCRequire("Script.UI.EnemyArrow.HTArrowConfig")

local TIER_ASSETS = {
    [State.WHITE] = "Asset/UI/Textures/T_EnemyArrow/ar_white.ar_white",
    [State.YELLOW] = "Asset/UI/Textures/T_EnemyArrow/ar_yellow.ar_yellow",
    [State.RED] = "Asset/UI/Textures/T_EnemyArrow/ar_red.ar_red",
}

local TextureCache = {}
local ORBIT_MARGIN = 48
local DIRECTION_OFFSET_DEGREES = 90

local function finite(value)
    return type(value) == "number"
        and value == value
        and math.abs(value) < math.huge
end

local function validVector2(value)
    return value
        and finite(value.X)
        and finite(value.Y)
end

local function atan2(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 then
        return math.atan(y / x) - math.pi
    elseif y > 0 then
        return math.pi * 0.5
    elseif y < 0 then
        return -math.pi * 0.5
    end
    return 0
end

local function loadTexture(tier)
    if TextureCache[tier] then
        return TextureCache[tier]
    end

    local relativePath = TIER_ASSETS[tier]
    if not relativePath then
        return nil
    end

    local fullPath = UGCGameSystem.GetUGCResourcesFullPath(relativePath)
    local texture = UGCObjectUtility.LoadObject(fullPath)
    if not texture then
        ugcprint("[HTArrow] Missing texture " .. tostring(fullPath))
        return nil
    end

    TextureCache[tier] = texture
    return texture
end

local function setImageTexture(image, texture)
    if not image or not texture then
        return
    end
    image:SetBrushFromTexture(texture, false)
end

local function setArrowTransform(self, angle)
    self.CanvasPanel_Arrow:SetRenderTransform({
        Translation = {X = 0, Y = 0},
        Scale = {X = 1, Y = 1},
        Shear = {X = 0, Y = 0},
        Angle = angle or 0,
    })
end

local function applyTier(self, tier)
    if not tier or tier == self.CurrentArrowTier then
        return
    end

    local texture = loadTexture(tier)
    if not texture then
        return
    end

    setImageTexture(self.Image_InScreenArrow, texture)
    setImageTexture(self.Image_Arrow, texture)
    self.CurrentArrowTier = tier
end

local function getPlayer(self)
    return self:GetOwningPlayerPawn() or UGCGameSystem.GetLocalPlayerPawn()
end

local function getDistanceToPlayer(self)
    local target = self:GetTargetActor()
    local player = getPlayer(self)
    if not target or not player then
        return nil
    end
    local targetLocation = target:K2_GetActorLocation()
    local playerLocation = player:K2_GetActorLocation()
    local dx = targetLocation.X - playerLocation.X
    local dy = targetLocation.Y - playerLocation.Y
    local dz = targetLocation.Z - playerLocation.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function updateOrbitArrow(self)
    local player = getPlayer(self)
    local target = self:GetTargetActor()
    if not player or not target then
        self.OutScreenPnl:SetVisibility(1)
        return
    end

    self.InScreenPnl:SetVisibility(1)
    self.OutScreenPnl:SetVisibility(4)

    local rootGeometry = UGCWidgetUtility.GetWidgetGeometry(self)
    local rootLocalSize = UGCWidgetUtility.GetLocalSize(rootGeometry)
    if not validVector2(rootLocalSize)
        or rootLocalSize.X <= 0
        or rootLocalSize.Y <= 0 then
        return
    end

    local playerLocation = player:K2_GetActorLocation()
    local targetLocation = target:K2_GetActorLocation()
    local forward = player:GetActorForwardVector()
    local right = player:GetActorRightVector()

    local dx = targetLocation.X - playerLocation.X
    local dy = targetLocation.Y - playerLocation.Y
    local forwardDistance = dx * forward.X + dy * forward.Y
    local rightDistance = dx * right.X + dy * right.Y
    local bearing = atan2(rightDistance, forwardDistance)
    local outwardX = math.sin(bearing)
    local outwardY = -math.cos(bearing)

    local centerX = rootLocalSize.X * 0.5
    local centerY = rootLocalSize.Y * 0.5
    local orbitRadius = math.max(
        1,
        math.min(rootLocalSize.X, rootLocalSize.Y) * 0.5 - ORBIT_MARGIN
    )
    self.OutScreenPnl.Slot:SetPosition({
        X = centerX + outwardX * orbitRadius,
        Y = centerY + outwardY * orbitRadius,
    })

    local angle = math.deg(atan2(outwardY, outwardX)) + DIRECTION_OFFSET_DEGREES
    setArrowTransform(self, angle)
end

local function isInsideVision(self)
    local target = self:GetTargetActor()
    local player = getPlayer(self)
    if not target or not player then
        return false
    end
    local captureState = target.HTCaptureState
    local playerKeys = captureState and captureState.VisionPlayerKeys or ""
    local playerKey = UGCGameSystem.GetPlayerKeyByPlayerPawn(player)
    if playerKey == nil or playerKey == -1 then
        return false
    end
    for detectedKey in string.gmatch(playerKeys, "([^,]+)") do
        if tonumber(detectedKey) == playerKey then return true end
    end
    return false
end

local function localDetection(self)
    local target, player = self:GetTargetActor(), getPlayer(self)
    if not target or not player then return false, false end
    local state = target.HTCaptureState or {}
    local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(player)
    if key == nil or key == -1 then return false, false end
    local inside = isInsideVision(self)
    local locked = tonumber(state.VisionLockedKey) == key
    return inside, locked
end

local function playSound(self, name)
    local path = Config[name]
    if type(path) ~= 'string' or path == '' then return nil end
    if string.sub(path,1,1) ~= '/' then path = UGCGameSystem.GetUGCResourcesFullPath(path) end
    local event = UGCObjectUtility.LoadObject(path)
    if not event then
        if not self.SoundErrors then self.SoundErrors = {} end
        if not self.SoundErrors[name] then
            ugcprint('[HTArrow] Missing AkAudioEvent: '..path)
            self.SoundErrors[name] = true
        end
        return nil
    end
    return UGCSoundManagerSystem.PlaySound2D(event)
end

local function stopDetectionSound(self)
    if self.DetectionSoundId and self.DetectionSoundId ~= 0 then
        UGCSoundManagerSystem.StopSoundByID(self.DetectionSoundId)
    end
    self.DetectionSoundId = nil
end

local updateProgress

function WBP_HTEnemyArrow:SetTargetActor(target)
    self.TargetActor = target
end

function WBP_HTEnemyArrow:GetTargetActor()
    return self.TargetActor
end

function WBP_HTEnemyArrow:Refresh()
    updateOrbitArrow(self)
    local distance = tonumber(getDistanceToPlayer(self))
    if not finite(distance) then
        stopDetectionSound(self)
        self.WasDetecting = false
        self.WasLocked = false
        return
    end

    local detected, locked = localDetection(self)
    if detected ~= self.DebugDetected or locked ~= self.DebugLocked then
        ugcprint(string.format('[HTArrow] detection=%s locked=%s progress=%.3f',
            tostring(detected), tostring(locked), self.DetectionProgress))
        self.DebugDetected = detected
        self.DebugLocked = locked
    end
    local baseTier = State.tierFor(distance, false)
    if locked and not self.WasLocked then playSound(self, 'LockSound') end
    if detected and not locked and not self.WasDetecting then
        self.DetectionSoundId = playSound(self, 'DetectionSound')
    elseif (not detected or locked) and self.WasDetecting then
        stopDetectionSound(self)
    end
    local wasDetecting = self.WasDetecting
    self.WasDetecting = detected and not locked
    self.WasLocked = locked
    if locked then
        self.DetectionProgress = 1
    elseif self.WasDetecting and not wasDetecting then
        self.DetectionProgress = 0
    end
    local showingProgress = detected or locked or self.DetectionProgress > 0
    self.ProgressBar_0:SetPercent(self.DetectionProgress)
    self.ProgressBar_0:SetVisibility(showingProgress and 4 or 1)
    local visibleTier = locked and State.RED
        or showingProgress and State.YELLOW
        or baseTier
    applyTier(self, visibleTier)
    if visibleTier == State.WHITE and self.PreviousVisibleTier == nil then
        playSound(self, 'WhiteSound')
    elseif visibleTier == State.YELLOW and self.PreviousVisibleTier == State.WHITE then
        playSound(self, 'NearSound')
    end
    self.PreviousVisibleTier = visibleTier
end

function WBP_HTEnemyArrow:Construct()
    self.CurrentArrowTier = nil
    self.PreviousVisibleTier = nil
    self.DetectionProgress = 0
    self.CanvasPanel_Arrow:SetRenderTransformPivot({X = 0.5, Y = 0.5})
    setArrowTransform(self, 0)
    self.InScreenPnl:SetVisibility(1)
    self.OutScreenPnl:SetVisibility(4)
    applyTier(self, State.WHITE)
    if not self.ArrowRefreshTimer then
        local timer
        timer = UGCTimerUtility.CreateLuaTimer(0.05, function()
            if not KismetSystemLibrary.IsValid(self) then
                UGCTimerUtility.RemoveLuaTimer(timer)
                return
            end
            self:Refresh()
        end, true)
        self.ArrowRefreshTimer = timer
    end
    if not self.ProgressRefreshTimer then
        local timer
        timer = UGCTimerUtility.CreateLuaTimer(Config.ProgressRefreshInterval, function()
            if not KismetSystemLibrary.IsValid(self) then
                UGCTimerUtility.RemoveLuaTimer(timer)
                return
            end
            local player = getPlayer(self)
            if not player then self.ProgressLastTime = nil; return end
            local now = UGCGameSystem.GetTimeSeconds(player)
            local delta = self.ProgressLastTime and math.max(0, now - self.ProgressLastTime) or 0
            self.ProgressLastTime = now
            updateProgress(self, delta)
        end, true)
        self.ProgressRefreshTimer = timer
    end
end

function updateProgress(self, DeltaTime)
    if self.WasLocked then
        self.DetectionProgress = 1
    elseif self.WasDetecting then
        local duration = Config.DetectionProgressSeconds
        if duration == 0 then
            self.DetectionProgress = 1
        elseif finite(duration) and duration > 0 then
            self.DetectionProgress = math.min(1, self.DetectionProgress + DeltaTime / duration)
        end
    else
        self.DetectionProgress = math.max(0, self.DetectionProgress - Config.ProgressReturnPerSecond * DeltaTime)
    end
    self.ProgressBar_0:SetPercent(self.DetectionProgress)
    self.ProgressBar_0:SetVisibility((self.WasDetecting or self.WasLocked or self.DetectionProgress > 0) and 4 or 1)
end

function WBP_HTEnemyArrow:Destruct()
    stopDetectionSound(self)
    if self.ArrowRefreshTimer then
        UGCTimerUtility.RemoveLuaTimer(self.ArrowRefreshTimer)
        self.ArrowRefreshTimer = nil
    end
    if self.ProgressRefreshTimer then
        UGCTimerUtility.RemoveLuaTimer(self.ProgressRefreshTimer)
        self.ProgressRefreshTimer = nil
    end
    self.TargetActor = nil
end

return WBP_HTEnemyArrow
