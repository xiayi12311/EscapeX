---@class TheHeadTeacherMutated_C:BP_UGC_GenericMobPawn_Base_C
---@field HitBox UCapsuleComponent
---@field LightWeaknessDuration float
---@field HeavyWeaknessDuration float
---@field BreakPointOffsets ULuaArrayHelper<FVector>
---@field BossFanBaseRadius float
---@field BossFanAngle float
---@field BossFanHeight float
---@field BreakPointSocket FName
---@field WeakPointDamageMultiplier float
---@field ToughnessMax float
---@field ToughnessPerWeakPointHit float
---@field BossChargeDuration float
---@field BossChargeFlashLeadSeconds float
---@field BreakPointDurability int32
--Edit Below--
---@type TheHeadTeacherMutated_C
local TheHeadTeacherMutated = {}

local CombatTreeResource = 'Asset/Blueprint/Prefabs/Monsters/BT_HeadTeacherMutated_Combat.BT_HeadTeacherMutated_Combat'


local Weakness = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.BossWeaknessSkill')

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

function TheHeadTeacherMutated:InterruptBossSkill()
    local skill = self.BossActiveSkill
    self.BossActiveSkill = nil
    if valid(skill) and skill:IsActivating() then
        skill:DeActivateSkill(1) -- Interrupt
    end
end

function TheHeadTeacherMutated:EnterBossWeakness(kind)
    if self.BossWeakness or self.BossCombatEnding or not UGCGenericCharacterSystem.IsAlive(self) then return false end
    local skill = Weakness.GetSkill(self, kind)
    assert(valid(skill), '[EscapeX Boss] Missing weakness skill: '..kind)
    if not skill:CanActivateSkill() then return false end
    skill:ActivateSkill()
    return self.BossWeaknessSkill == skill
end

function TheHeadTeacherMutated:PreOverrideDamage(damage, instigator, causer, context)
    self.BossWeakPointHealthBefore = nil
    if damage <= 0 or self.BossCombatEnding or not context then return damage end
    if UGCAttributeSystem.GetDamagePositionTypeFromContext(context) ~= EAvatarDamagePosition.BigHead then
        return damage
    end

    self.BossWeakPointHealthBefore = UGCGenericCharacterSystem.GetHealth(self)
    return damage * self.WeakPointDamageMultiplier
end

function TheHeadTeacherMutated:PostTakeDamageEvent()
    local healthBefore = self.BossWeakPointHealthBefore
    self.BossWeakPointHealthBefore = nil
    if not healthBefore or self.BossWeakness or self.BossCombatEnding
        or not UGCGenericCharacterSystem.IsAlive(self)
        or UGCGenericCharacterSystem.GetHealth(self) >= healthBefore then return end

    self.BossToughness = math.max(0, self.BossToughness - self.ToughnessPerWeakPointHit)
    if self.BossToughness == 0 then
        self:EnterBossWeakness('ToughnessBroken')
    end
end

function TheHeadTeacherMutated:ReceiveBeginPlay()
    TheHeadTeacherMutated.SuperClass.ReceiveBeginPlay(self)
    if not self:HasAuthority() then return end

    self.BossToughnessMax = self.ToughnessMax
    self.BossToughness = self.BossToughnessMax

    UGCTimerUtility.CreateLuaTimer(0, function()
        if not valid(self) or not UGCGenericCharacterSystem.IsAlive(self) then return end
        -- Normalize older placements that serialized their previous behavior tree.
        local path = UGCGameSystem.GetUGCResourcesFullPath(CombatTreeResource)
        local tree = UGCObjectUtility.LoadObject(path)
        assert(tree, '[EscapeX Boss] Missing combat behavior tree: '..path)
        local current = UGCGenericCharacterSystem.GetBehaviorTreeSetting(self)
        if current.BehaviorTreePath ~= tree then
            UGCGenericCharacterSystem.RunBehavior(self, path)
        end
    end, false)
end

-- function TheHeadTeacherMutated:ReceiveTick(DeltaTime)
--     TheHeadTeacherMutated.SuperClass.ReceiveTick(self, DeltaTime)
-- end

-- function TheHeadTeacherMutated:ReceiveEndPlay()
--     TheHeadTeacherMutated.SuperClass.ReceiveEndPlay(self) 
-- end

-- function TheHeadTeacherMutated:GetReplicatedProperties()
--     return
-- end

-- ---受击前置事件
-- ---生效范围：服务器
-- ---@param Damage float 伤害值
-- ---@param EventInstigator AController 伤害来源的Controller
-- ---@param DamageCauser AActor 伤害来源
-- ---@param DamageContext FGameMagnitudeContext  伤害上下文
-- function TheHeadTeacherMutated:PreTakeDamageEvent(Damage, EventInstigator, DamageCauser, DamageContext)
     
-- end

-- ---受击后置伤害修改
-- ---生效范围：服务器
-- ---@param Damage float 伤害值
-- ---@param EventInstigator AController 伤害来源的Controller
-- ---@param DamageCauser AActor 伤害来源
-- ---@param DamageContext FGameMagnitudeContext  伤害上下文
-- ---@return float 修改后的伤害值
-- function TheHeadTeacherMutated:PostOverrideDamage(Damage, EventInstigator, DamageCauser, DamageContext)
--     return Damage
-- end

local function clearCombatState(self)
    if not self:HasAuthority() then return end
    self.BossCombatEnding = true
    self:InterruptBossSkill()
    local weakness = self.BossWeaknessSkill
    if valid(weakness) and weakness:IsActivating() then
        weakness:DeActivateSkill(1) -- Interrupt
    end
    self.BossWeakPointHealthBefore = nil
end

---角色死亡事件
---生效范围：服务器&客户端
---@param Damage float 伤害值
---@param EventInstigator AController 伤害来源的Controller
---@param DamageCauser AActor 伤害来源
---@param FDamageEvent DamageEvent 伤害事件
---@param DamageTypeID int32 伤害类型
function TheHeadTeacherMutated:BPDie(KillingDamage, EventInstigator, DamageCauser, DamageEvent, DamageTypeID)
    clearCombatState(self)
    if self:HasAuthority() then
        -- 只有服务端才可以掉落
        self.UGCPresetCommonDropItemComponent:StartDrop(self, EventInstigator, {})
        UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseEngineAdapter').NotifyDeath(self)
    end
end

-- ---状态进入事件
-- ---生效范围：服务器&客户端
-- ---@param DynamicState FGameplayTag 进入的状态
-- function TheHeadTeacherMutated:OnEnterTagState_BP(DynamicState)
--     local Tag = BlueprintGameplayTagLibrary.GetTagName(DynamicState)
--     ugcprint('OnEnterTagState_BP: ' .. Tag)
-- end

-- ---状态退出事件
-- ---生效范围：服务器&客户端
-- ---@param DynamicState FGameplayTag 退出的状态
-- function TheHeadTeacherMutated:OnLeaveTagState_BP(DynamicState)
--     local Tag = BlueprintGameplayTagLibrary.GetTagName(DynamicState)
--     ugcprint('OnLeaveTagState_BP: ' .. Tag)
-- end

-- ---状态打断事件
-- ---生效范围：服务器&客户端
-- ---@param DynamicState FGameplayTag 打断的状态
-- function TheHeadTeacherMutated:OnInterruptTagState_BP(DynamicState)
--     local Tag = BlueprintGameplayTagLibrary.GetTagName(DynamicState)
--     ugcprint('OnInterruptTagState_BP' .. Tag)
-- end

-- ---行为树消息
-- ---生效范围：服务器
-- ---@param NotifyMsg string 消息
-- function TheHeadTeacherMutated:OnBehaviorNotify_BP(NotifyMsg)
--     ugcprint('OnBehaviorNotify_BP: ' .. NotifyMsg)
-- end

-- ---怪物的目标发生变化事件
-- ---生效范围：服务器&客户端
-- ---@param NewTarget AActor 新目标
-- ---@param OldTarget AActor 旧目标
-- function TheHeadTeacherMutated:OnTargetChange_BP(NewTarget, OldTarget)
    
-- end

function TheHeadTeacherMutated:GetReplicatedProperties()
    return 'BossWeaknessPlayback'
end

function TheHeadTeacherMutated:OnRep_BossWeaknessPlayback()
    Weakness.SyncPlayback(self)
end

function TheHeadTeacherMutated:ReceiveEndPlay(reason)
    clearCombatState(self)
    Weakness.CancelPlaybackCheck(self)
    TheHeadTeacherMutated.SuperClass.ReceiveEndPlay(self, reason)
end

return TheHeadTeacherMutated