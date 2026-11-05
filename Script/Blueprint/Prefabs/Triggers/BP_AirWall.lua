---@class BP_AirWall_C:AActor
---@field AirWallVisual UStaticMeshComponent
---@field AirWallCollision UBoxComponent
---@field DefaultSceneRoot USceneComponent
---@field FadeStartDistance float
---@field FullVisibleDistance float
---@field MaxAlphaIntensity float
--Edit Below--
local AirWall = {}

local Config = {
    UpdateInterval = 0.05,
    FadeInterpSpeed = 4,
    MaterialSlot = 0,
    OpacityParameter = 'Alpha_Intensity',
}

local function valid(o)
    return o ~= nil and KismetSystemLibrary.IsValid(o)
end

local function setOpacity(wall, opacity)
    wall.CurrentOpacity = opacity
    if valid(wall.AirWallMaterial) then
        wall.AirWallMaterial:SetScalarParameterValue(Config.OpacityParameter, opacity)
    end
end

function AirWall:UpdateFade()
    if not valid(self) or not valid(self.AirWallVisual) then return end
    local pawn = UGCGameSystem.GetLocalPlayerPawn()
    if not valid(pawn) then
        setOpacity(self, 0)
        return
    end

    local fadeStartDistance = self.FadeStartDistance
    local fullVisibleDistance = self.FullVisibleDistance
    if type(fadeStartDistance) ~= 'number'
        or type(fullVisibleDistance) ~= 'number'
        or fullVisibleDistance < 0
        or fadeStartDistance <= fullVisibleDistance then
        if not self.FadeStartDistanceError then
            self.FadeStartDistanceError = true
            ugcprint('[AirWall] ERROR: FadeStartDistance must be greater than FullVisibleDistance')
        end
        setOpacity(self, 0)
        return
    end

    local maximumOpacity = self.MaxAlphaIntensity
    if type(maximumOpacity) ~= 'number' or maximumOpacity ~= maximumOpacity
        or maximumOpacity < 0 or maximumOpacity == math.huge then
        if not self.MaxAlphaIntensityError then
            self.MaxAlphaIntensityError = true
            ugcprint('[AirWall] ERROR: MaxAlphaIntensity must be a finite non-negative number')
        end
        return
    end

    local distance = self:GetDistanceTo(pawn)
    local target = 0
    if distance <= fullVisibleDistance then
        target = maximumOpacity
    elseif distance < fadeStartDistance then
        local ratio = (fadeStartDistance - distance)
            / (fadeStartDistance - fullVisibleDistance)
        target = maximumOpacity * ratio
    end

    local blend = math.min(1, Config.UpdateInterval * Config.FadeInterpSpeed)
    setOpacity(self, (self.CurrentOpacity or 0) + (target - (self.CurrentOpacity or 0)) * blend)
end

function AirWall:ReceiveBeginPlay()
    AirWall.SuperClass.ReceiveBeginPlay(self)
    self.CurrentOpacity = 0

    if not valid(self.AirWallVisual) then
        ugcprint('[AirWall] ERROR: AirWallVisual is missing')
        return
    end
    self.AirWallMaterial = self.AirWallVisual:CreateDynamicMaterialInstance(Config.MaterialSlot)
    if not valid(self.AirWallMaterial) then
        ugcprint('[AirWall] ERROR: translucent material instance is unavailable')
        return
    end

    setOpacity(self, 0)
    self.AirWallFadeTimer = UGCTimerUtility.CreateLuaTimer(
        Config.UpdateInterval, function() self:UpdateFade() end, true, 'EscapeX.AirWall.Fade')
end

function AirWall:ReceiveEndPlay(Reason)
    if self.AirWallFadeTimer then
        UGCTimerUtility.RemoveLuaTimer(self.AirWallFadeTimer)
        self.AirWallFadeTimer = nil
    end
    AirWall.SuperClass.ReceiveEndPlay(self, Reason)
end

return AirWall
