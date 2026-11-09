---@class BP_PushPullCrate_C:AActor
---@field CrateMesh UStaticMeshComponent
---@field CrateCollision UBoxComponent
---@field DefaultSceneRoot USceneComponent
---@field CrateId FString
---@field CrateEnabled bool
---@field CrateHalfWidth float
---@field CrateHalfDepth float
---@field CrateHalfHeight float
---@field CrateVisualScale float
---@field CrateVisualFitToCollision bool
---@field CrateVisualScaleX float
---@field CrateVisualScaleY float
---@field CrateVisualScaleZ float
---@field CookAnim_OnPosition UAnimSequence
---@field CookAnim_Idle UAnimSequence
---@field CookAnim_PushStart UAnimSequence
---@field CookAnim_Push UAnimSequence
---@field CookAnim_PushStop UAnimSequence
---@field CookAnim_PullStart UAnimSequence
---@field CookAnim_Pull UAnimSequence
---@field CookAnim_PullStop UAnimSequence
--Edit Below--
local Service = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullService')
local Presentation = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullPresentation')
local Focus = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullFocusPresentation')
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig')
local Crate = {CrateState = {
    CrateId = '',
    SessionId = 0,
    Revision = 0,
    Enabled = false,
    MotionSpeed = 0,
    MotionDirX = 0,
    MotionDirY = 1,
    Blocked = false,
    Participants = {},
}}

local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local function fitVisual(self)
    if not (valid(self.CrateMesh) and valid(self.CrateMesh.StaticMesh)) then
        ugcprint('[PushPull] BP_PushPullCrate CrateMesh or StaticMesh is missing')
        return
    end
    local sx = self.CrateVisualScaleX
    local sy = self.CrateVisualScaleY
    local sz = self.CrateVisualScaleZ
    local originX, originY, originZ = 0, 0, 0
    if self.CrateVisualFitToCollision then
        local bounds = self.CrateMesh.StaticMesh:GetBounds()
        sx = self.CrateHalfWidth / bounds.BoxExtent.X
        sy = self.CrateHalfDepth / bounds.BoxExtent.Y
        sz = self.CrateHalfHeight / bounds.BoxExtent.Z
        originX, originY, originZ = bounds.Origin.X, bounds.Origin.Y, bounds.Origin.Z
    end
    local multiplier = self.CrateVisualScale or 1
    sx, sy, sz = sx * multiplier, sy * multiplier, sz * multiplier
    local location = {X = -originX * sx, Y = -originY * sy, Z = -originZ * sz}
    pcall(function() self.CrateMesh:SetRelativeLocation(location, false, {}, true) end)
    self.CrateMesh:SetWorldScale3D({X = sx, Y = sy, Z = sz})
end

function Crate:GetReplicatedProperties()
    return 'CrateState'
end

function Crate:ReceiveBeginPlay()
    Crate.SuperClass.ReceiveBeginPlay(self)
    self.NetUpdateFrequency = Config.Network.ActorUpdateFrequency
    self.MinNetUpdateFrequency = Config.Network.MinActorUpdateFrequency
    self.NetConsiderFrequency = Config.Network.ActorConsiderFrequency
    if valid(self.CrateCollision) then
        self.CrateCollision:SetBoxExtent({
            X = self.CrateHalfWidth,
            Y = self.CrateHalfDepth,
            Z = self.CrateHalfHeight,
        }, true)
        pcall(function() self.CrateCollision:SetCollisionProfileName('BlockAll') end)
    end
    fitVisual(self)
    self.CrateState.CrateId = self.CrateId or ''
    self.CrateState.Enabled = self.CrateEnabled ~= false
    if self:HasAuthority() then
        local crateId = self.CrateId
        if type(crateId) ~= 'string' or crateId == '' then
            ugcprint('[PushPull] BP_PushPullCrate CrateId is required; registration skipped')
            return
        end
        self.CrateRegisterTimer = UGCTimerUtility.CreateLuaTimer(0.1, function()
            if not KismetSystemLibrary.IsValid(self) then return end
            local gm = UGCGameSystem.GetGameMode()
            local ok, reason = Service.RegisterCrate(gm, self, crateId)
            if ok then
                UGCTimerUtility.RemoveLuaTimer(self.CrateRegisterTimer)
                self.CrateRegisterTimer = nil
            elseif reason ~= 'SERVICE_NOT_READY' and reason ~= 'ANIMATION_RESOURCE_UNAVAILABLE' then
                ugcprint('[PushPull] crate registration rejected ' .. tostring(reason))
                UGCTimerUtility.RemoveLuaTimer(self.CrateRegisterTimer)
                self.CrateRegisterTimer = nil
            end
        end, true, 'EscapeX.PushPull.CrateRegister.' .. tostring(crateId))
    end
end

function Crate:OnRep_CrateState()
    if not self:HasAuthority() then
        Presentation.Apply(self, self.CrateState)
        Focus.CrateChanged(self, self.CrateState)
    end
end

function Crate:ReceiveEndPlay(Reason)
    if self.CrateRegisterTimer then
        UGCTimerUtility.RemoveLuaTimer(self.CrateRegisterTimer)
        self.CrateRegisterTimer = nil
    end
    if self:HasAuthority() then
        Service.UnregisterCrate(UGCGameSystem.GetGameMode(), self)
    else
        Presentation.End(self)
        Focus.CrateRemoved(self)
    end
    Crate.SuperClass.ReceiveEndPlay(self, Reason)
end

return Crate
