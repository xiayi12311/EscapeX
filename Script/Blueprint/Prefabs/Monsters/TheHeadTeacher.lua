---@class TheHeadTeacher_C:BP_UGC_GenericMobPawn_Base_C
---@field SpotLight USpotLightComponent
---@field RedLightMesh UStaticMeshComponent
---@field HitBox UCapsuleComponent
---@field HTViewDistance float
---@field HTViewFullAngle float
---@field HTCatchDistance float
---@field HTPatrolSpeed float
---@field HTChaseSpeed float
---@field HTDamage float
---@field HTDetectionInterval float
---@field HTMoveInterval float
---@field HTWaypointRadius float
---@field HTDiagnosticInterval float
---@field HTAttachSocket FString
---@field HTSourceSocket FString
---@field HTTargetSocket FString
---@field HTRouteTag FString
---@field HTSightChannel int32
---@field HTDebug bool
---@field HTConePitch float
---@field HTConeYaw float
---@field HTConeRoll float
---@field HTDetectionEnabled bool
---@field HTServerSightMeshPath FString
---@field HTServerSightAnimClassPath FString
--Edit Below--
local TheHeadTeacher = {}

-- function TheHeadTeacher:ReceiveBeginPlay()
--     TheHeadTeacher.SuperClass.ReceiveBeginPlay(self)
-- end

-- function TheHeadTeacher:ReceiveTick(DeltaTime)
--     TheHeadTeacher.SuperClass.ReceiveTick(self, DeltaTime)
-- end

-- function TheHeadTeacher:ReceiveEndPlay()
--     TheHeadTeacher.SuperClass.ReceiveEndPlay(self) 
-- end

-- function TheHeadTeacher:GetReplicatedProperties()
--     return
-- end

-- ---受击前置事件
-- ---生效范围：服务器
-- ---@param Damage float 伤害值
-- ---@param EventInstigator AController 伤害来源的Controller
-- ---@param DamageCauser AActor 伤害来源
-- ---@param DamageContext FGameMagnitudeContext  伤害上下文
-- function TheHeadTeacher:PreTakeDamageEvent(Damage, EventInstigator, DamageCauser, DamageContext)
     
-- end

-- ---受击后置事件
-- ---生效范围：服务器
-- ---@param Damage float 伤害值
-- ---@param EventInstigator AController 伤害来源的Controller
-- ---@param DamageCauser AActor 伤害来源
-- ---@param DamageContext FGameMagnitudeContext  伤害上下文
-- function TheHeadTeacher:PostTakeDamageEvent(Damage, EventInstigator, DamageCauser, DamageContext)
    
-- end

-- ---受击前置伤害修改
-- ---生效范围：服务器
-- ---@param Damage float 伤害值
-- ---@param EventInstigator AController 伤害来源的Controller
-- ---@param DamageCauser AActor 伤害来源
-- ---@param DamageContext FGameMagnitudeContext  伤害上下文
-- ---@return float 修改后的伤害值
-- function TheHeadTeacher:PreOverrideDamage(Damage, EventInstigator, DamageCauser, DamageContext)
--     return Damage
-- end

-- ---受击后置伤害修改
-- ---生效范围：服务器
-- ---@param Damage float 伤害值
-- ---@param EventInstigator AController 伤害来源的Controller
-- ---@param DamageCauser AActor 伤害来源
-- ---@param DamageContext FGameMagnitudeContext  伤害上下文
-- ---@return float 修改后的伤害值
-- function TheHeadTeacher:PostOverrideDamage(Damage, EventInstigator, DamageCauser, DamageContext)
--     return Damage
-- end

---角色死亡事件
---生效范围：服务器&客户端
---@param Damage float 伤害值
---@param EventInstigator AController 伤害来源的Controller
---@param DamageCauser AActor 伤害来源
---@param FDamageEvent DamageEvent 伤害事件
---@param DamageTypeID int32 伤害类型
function TheHeadTeacher:BPDie(KillingDamage, EventInstigator, DamageCauser, DamageEvent, DamageTypeID)
    if self:HasAuthority() then
        -- 只有服务端才可以掉落
        self.UGCPresetCommonDropItemComponent:StartDrop(self, EventInstigator, {})
    end
end

-- ---状态进入事件
-- ---生效范围：服务器&客户端
-- ---@param DynamicState FGameplayTag 进入的状态
-- function TheHeadTeacher:OnEnterTagState_BP(DynamicState)
--     local Tag = BlueprintGameplayTagLibrary.GetTagName(DynamicState)
--     ugcprint('OnEnterTagState_BP: ' .. Tag)
-- end

-- ---状态退出事件
-- ---生效范围：服务器&客户端
-- ---@param DynamicState FGameplayTag 退出的状态
-- function TheHeadTeacher:OnLeaveTagState_BP(DynamicState)
--     local Tag = BlueprintGameplayTagLibrary.GetTagName(DynamicState)
--     ugcprint('OnLeaveTagState_BP: ' .. Tag)
-- end

-- ---状态打断事件
-- ---生效范围：服务器&客户端
-- ---@param DynamicState FGameplayTag 打断的状态
-- function TheHeadTeacher:OnInterruptTagState_BP(DynamicState)
--     local Tag = BlueprintGameplayTagLibrary.GetTagName(DynamicState)
--     ugcprint('OnInterruptTagState_BP' .. Tag)
-- end

-- ---行为树消息
-- ---生效范围：服务器
-- ---@param NotifyMsg string 消息
-- function TheHeadTeacher:OnBehaviorNotify_BP(NotifyMsg)
--     ugcprint('OnBehaviorNotify_BP: ' .. NotifyMsg)
-- end

-- ---怪物的目标发生变化事件
-- ---生效范围：服务器&客户端
-- ---@param NewTarget AActor 新目标
-- ---@param OldTarget AActor 旧目标
-- function TheHeadTeacher:OnTargetChange_BP(NewTarget, OldTarget)
    
-- end

local H = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCommon")
local C = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCapture")
local Presentation = UGCGameSystem.UGCRequire("Script.Gameplay.Capture.CapturePresentation")

-- Synced so the carried player's own client can attach its pawn locally; a
-- server-only attach does not move them on their screen (measured 2026-10-26).
TheHeadTeacher.HTCaptureState = {PlayerKey = -1, Stage = "None", Revision = 0}

function TheHeadTeacher:ReceiveBeginPlay()
    TheHeadTeacher.SuperClass.ReceiveBeginPlay(self)
    H.setupCone(self)
    if self:HasAuthority() then
        -- This monster's head socket must remain current on the dedicated server.
        self.Mesh.MeshComponentUpdateFlag = 0
        -- Monster cannot be body-blocked by player capsules.
        self.CapsuleComponent:SetCollisionResponseToChannel(16, 0)
        if H.valid(self.HitBox) then self.HitBox:SetCollisionResponseToChannel(16, 0) end
    elseif self.HTCaptureState then
        -- Late join: apply whatever the server already published for this monster.
        Presentation.Carrier(self, self.HTCaptureState)
    end
end

function TheHeadTeacher:GetReplicatedProperties()
    return "HTDetectionEnabled", "HTViewDistance", "HTViewFullAngle",
        "HTConePitch", "HTConeYaw", "HTConeRoll", "HTAttachSocket", "HTCaptureState"
end

function TheHeadTeacher:OnRep_HTViewDistance() H.setupCone(self) end
function TheHeadTeacher:OnRep_HTViewFullAngle() H.setupCone(self) end
function TheHeadTeacher:OnRep_HTConePitch() H.setupCone(self) end
function TheHeadTeacher:OnRep_HTConeYaw() H.setupCone(self) end
function TheHeadTeacher:OnRep_HTConeRoll() H.setupCone(self) end
function TheHeadTeacher:OnRep_HTAttachSocket() H.setupCone(self) end

-- Capture replaces the old damage settlement: the caught player is carried to a
-- prison post instead of being eliminated. Returns started, reason so the Catch
-- task can decide whether to stay Running (see BTT_HTCatch).
function TheHeadTeacher:HandleCaughtPlayer(Target, ChaseSequenceId, Controller)
    if not self:HasAuthority() then return false, 'NOT_AUTHORITY' end
    local started, reason = C.begin(self, Target)
    ugcprint("[HeadTeacher] Catch sequence="..tostring(ChaseSequenceId)..
        " started="..tostring(started).." result="..tostring(reason))
    return started, reason
end

function TheHeadTeacher:OnRep_HTCaptureState()
    if self:HasAuthority() then return end
    Presentation.Carrier(self, self.HTCaptureState)
end

function TheHeadTeacher:ReceiveEndPlay(Reason)
    if self:HasAuthority() then
        -- Never leave a player attached to an actor that is going away.
        C.cancel(self, 'MONSTER_DESTROYED')
    else
        Presentation.End(self)
    end
    TheHeadTeacher.SuperClass.ReceiveEndPlay(self, Reason)
end

return TheHeadTeacher
