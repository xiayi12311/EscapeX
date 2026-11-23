---@class BP_BossBreakPoint_C:BP_UGC_GenericMobPawn_Base_C
---@field BreakPointWidget UWidgetComponent
local Point = {}
local Aim = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.BossBreakAim')

local style = {
    Segments = 24,
    TickSeconds = 1 / 60,
    EnterSeconds = 0.26,
    EnterScale = 3.0,
    BrokenSeconds = 0.20,
    BrokenScale = 1.16,
    ExpiredSeconds = 0.16,
    ExpiredScale = 0.16,
    ScreenSize = { DistanceScaleCm=360, MinScale=0.22, MaxScale=0.60 },
    WarningFrequency = 7,
    RotationDegreesPerSecond = 150,
    ReplicationGraceSeconds = 0.30,
    NormalColor = {R=0.17, G=0.91, B=0.83, A=1},
    WarningColor = {R=1, G=0.045, B=0.025, A=1},
}

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

local function clock()
    return UGCGameSystem.GetGameState():GetServerWorldTimeSeconds()
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function ratio(elapsed, duration)
    return math.max(0, math.min(1, elapsed / duration))
end

local function setProgress(view, progress)
    local segments = math.floor(math.max(0, math.min(1, progress)) * style.Segments + 0.5)
    if segments == view.VisibleSegments then return end
    view.VisibleSegments = segments
    for index, image in ipairs(view.Progress) do
        image:SetVisibility(index <= segments and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
    end
end

local function tickCue(self)
    local state, view = self.BreakCueState, self.BreakCueView
    if not state or not view then return end
    local now = clock()
    local camera = UGCGameSystem.GetLocalPlayerController()
    camera = camera and camera.PlayerCameraManager
    if not camera then return end

    local cue = self.BreakPointWidget
    local anchor, eye = cue:K2_GetComponentLocation(), camera:GetCameraLocation()
    local distance = math.sqrt((eye.X-anchor.X)^2 + (eye.Y-anchor.Y)^2 + (eye.Z-anchor.Z)^2)
    local size = style.ScreenSize
    local perspective = math.max(size.MinScale, math.min(size.MaxScale, size.DistanceScaleCm / math.max(distance, 1)))

    if view.Phase ~= state.Phase then
        if not view.Phase and state.Phase ~= 'Active' then return end
        view.Phase, view.PhaseStartedAt = state.Phase, now
        view.PhaseStartScale = view.Scale or 1
    end
    local scale, opacity, warning = 1, 1, 0
    if state.Phase == 'Active' then
        local t = ratio(now - view.PhaseStartedAt, style.EnterSeconds)
        scale = lerp(1, style.EnterScale, (1 - t)^2)
        if state.FlashLead > 0 and state.Deadline - now <= state.FlashLead then
            local elapsed = now - state.Deadline + state.FlashLead
            warning = 0.35 + 0.65 * (0.5 + 0.5 * math.cos(elapsed * style.WarningFrequency * 2 * math.pi))
        end
    else
        local broken = state.Phase == 'Broken'
        local seconds = broken and style.BrokenSeconds or style.ExpiredSeconds
        local t = ratio(now - view.PhaseStartedAt, seconds)
        if t >= 1 then
            cue:SetVisibility(false, false)
            return
        end
        local target = broken and view.PhaseStartScale * style.BrokenScale or style.ExpiredScale
        scale = lerp(view.PhaseStartScale, target, t)
        opacity = broken and (1 - t) or 1
    end

    local color = warning > 0 and style.WarningColor or style.NormalColor
    view.Outer:SetColorAndOpacity({
        R=color.R, G=color.G, B=color.B, A=warning > 0 and warning or color.A,
    })
    view.Outer:SetRenderAngle(((now - state.OpenedAt) * style.RotationDegreesPerSecond) % 360)
    view.Scale = scale
    view.Widget:SetRenderScale({X=scale*perspective,Y=scale*perspective})
    view.Widget:SetRenderOpacity(opacity)
    setProgress(view, state.Progress)
    cue:SetVisibility(true, false)
end

function Point:GetReplicatedProperties()
    return 'BreakCueState'
end

function Point:OpenCue(deadline, flashLead, durability)
    self.BossBreakDurability = durability
    self.BossBreakHitCount = 0
    self.BreakCueState = { Phase='Active', OpenedAt=clock(), Deadline=deadline, FlashLead=flashLead, Progress=0 }
    self:ForceNetUpdate()
end

function Point:CountBreakHit()
    local state = self.BreakCueState
    if not state or state.Phase ~= 'Active' then return false end
    local hits = self.BossBreakHitCount + 1
    self.BossBreakHitCount = hits
    if hits >= self.BossBreakDurability then return true end

    self.BreakCueState = {
        Phase=state.Phase, OpenedAt=state.OpenedAt, Deadline=state.Deadline,
        FlashLead=state.FlashLead, Progress=hits/self.BossBreakDurability,
    }
    self:ForceNetUpdate()
    return false
end

function Point:FinishCue(phase)
    local state = self.BreakCueState
    if not state then
        self:K2_DestroyActor()
        return
    end
    if state.Phase ~= 'Active' then return end
    self:SetActorEnableCollision(false)
    self.BreakCueState = {
        Phase=phase, OpenedAt=state.OpenedAt, Deadline=state.Deadline,
        Progress=phase == 'Broken' and 1 or state.Progress,
    }
    self:ForceNetUpdate()
    -- Keep the non-interactive anchor alive for replication and the local exit.
    local keep = math.max(style.BrokenSeconds, style.ExpiredSeconds) + style.ReplicationGraceSeconds
    UGCTimerUtility.CreateLuaTimer(keep, function()
        if valid(self) then self:K2_DestroyActor() end
    end, false)
end

local function initView(self)
    local widget = self.BreakPointWidget:GetUserWidgetObject()
    if not valid(widget) then return end
    local view = {Widget=widget, Outer=assert(widget:GetWidgetFromName('OuterRing')), Progress={}}
    for index = 1, style.Segments do
        local image = assert(widget:GetWidgetFromName(string.format('Progress%02d', index)))
        image:SetRenderAngle((index - 1) * 360 / style.Segments)
        view.Progress[index] = image
    end
    widget:SetRenderTransformPivot({X=0.5,Y=0.5})
    self.BreakCueView = view
end

function Point:ReceiveBeginPlay()
    Point.SuperClass.ReceiveBeginPlay(self)
    self:SetActorEnableCollision(false)
    if KismetSystemLibrary.IsDedicatedServer(self) then return end
    Aim.Track(self)

    self.CueTimer = UGCTimerUtility.CreateLuaTimer(style.TickSeconds, function()
        if not self.BreakCueView then initView(self) end
        tickCue(self)
    end, true)
end

function Point:PreOverrideDamage()
    -- Aim-based points ignore the native damage pipeline.
    return 0
end

function Point:ReceiveEndPlay(reason)
    Aim.Untrack(self)
    if self.CueTimer then UGCTimerUtility.RemoveLuaTimer(self.CueTimer) end
    self.BreakCueView = nil
    Point.SuperClass.ReceiveEndPlay(self, reason)
end

return Point
