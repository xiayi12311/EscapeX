local WBP_HTEnemyArrow = {}

local State = UGCGameSystem.UGCRequire("Script.UI.EnemyArrow.HTArrowState")

local TIER_ASSETS = {
    [State.WHITE] = "Asset/UI/Textures/T_EnemyArrow/Arrow_White",
    [State.YELLOW] = "Asset/UI/Textures/T_EnemyArrow/Arrow_Yellow",
    [State.RED] = "Asset/UI/Textures/T_EnemyArrow/Arrow_Red",
}

local TextureCache = {}
local ORBIT_MARGIN = 48
local DIRECTION_OFFSET_DEGREES = 0
local ARROW_IMAGE_SCALE = 1.5

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

local function setArrowImageScale(self)
    local transform = {
        Translation = {X = 0, Y = 0},
        Scale = {X = ARROW_IMAGE_SCALE, Y = ARROW_IMAGE_SCALE},
        Shear = {X = 0, Y = 0},
        Angle = 0,
    }
    for _, image in ipairs({self.Image_InScreenArrow, self.Image_Arrow}) do
        image:SetRenderTransformPivot({X = 0.5, Y = 0.5})
        image:SetRenderTransform(transform)
    end
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

local updateTier

function WBP_HTEnemyArrow:SetTargetActor(target)
    self.TargetActor = target
end

function WBP_HTEnemyArrow:GetTargetActor()
    return self.TargetActor
end

function WBP_HTEnemyArrow:Refresh()
    updateOrbitArrow(self)
    updateTier(self, getDistanceToPlayer(self))
end

function WBP_HTEnemyArrow:Construct()
    self.CurrentArrowTier = nil
    self.CanvasPanel_Arrow:SetRenderTransformPivot({X = 0.5, Y = 0.5})
    setArrowImageScale(self)
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
end

function WBP_HTEnemyArrow:Destruct()
    if self.ArrowRefreshTimer then
        UGCTimerUtility.RemoveLuaTimer(self.ArrowRefreshTimer)
        self.ArrowRefreshTimer = nil
    end
    self.TargetActor = nil
end

function updateTier(self, InDistance)
    local distance = tonumber(InDistance)
    if not finite(distance) then
        return
    end

    local detected = isInsideVision(self)
    local tier = State.tierFor(distance, detected)
    applyTier(self, tier)
end

return WBP_HTEnemyArrow
