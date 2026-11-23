---@class ZombieBossSkill_1_C:PESkillTemplate_Base_C
---@field SkillAnimationIndex int32
---@field FanRadius float
---@field FanAngle float
---@field FanHeight float
--Edit Below--
---@class ZombieBossSkill_1_C:PESkillTemplate_Base_C
---@field SkillAnimationIndex int32
local Skill = {}

local BreakPointResource = 'Asset/Blueprint/Prefabs/Monsters/BP_BossBreakPoint.BP_BossBreakPoint_C'

-- Source frames of the second animation and its matching Lua section in CastSkill_01.
local ChargeStartSequenceSeconds = 0.2
local ChargeEndSequenceSeconds = 1.2
local MinimumChargeDuration = 0.1

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

function Skill:CloseBossBreakWindow(phase)
    local window = self.BossBreakWindow
    if not window then return end
    self.BossBreakWindow = nil
    for _, point in ipairs(window.Points) do
        if valid(point) then
            point.BossBreakSkill = nil
            point:FinishCue(phase or 'Cancelled')
        end
    end
end

local function interruptBrokenCast(self, boss)
    if not valid(boss) or not self:IsActivating() then return end
    if boss:EnterBossWeakness('SkillInterrupted') then
        ugcprint('[BossBreak] cast interrupted')
    end
end

local function restoreChargeRate(self)
    if not self.BossChargeRateActive then return end
    self.BossChargeRateActive = nil
    self:SetPlayRate(1)
end

-- The natural end of the Sequence section is the only path that authorizes release.
function Skill:FinishBossBreakWindow()
    restoreChargeRate(self)
    if not UGCGameSystem.IsServer() then return end
    local window = self.BossBreakWindow
    self:CloseBossBreakWindow('Expired')
    if self.BossCastPhase ~= 'Charging' or not window or not self:IsActivating() then return end
    local boss = window.Boss
    if not valid(boss) or boss.BossWeakness or not UGCGenericCharacterSystem.IsAlive(boss) then return end
    if window.Remaining == 0 then
        interruptBrokenCast(self, boss)
        return
    end
    self.BossCastPhase = 'Ready'
end

-- Runs before both the native launch and direct damage tracks.
function Skill:ValidateBossAttackRelease()
    if not UGCGameSystem.IsServer() or not self:IsActivating() then return end
    if self.BossCastPhase == 'Released' then return end
    local boss = self:GetOwnerActor()
    if self.BossCastPhase == 'Ready' and valid(boss) and not boss.BossWeakness
        and UGCGenericCharacterSystem.IsAlive(boss) then
        self.BossCastPhase = 'Released'
        ugcprint('[BossBreak] attack released')
        return
    end
    self:DeActivateSkill(1)
end

function Skill:OpenBossBreakWindow()
    if not self.BossChargeDuration or self.BossChargeRateActive or not self:IsActivating() then return end
    local sequenceTime = math.max(ChargeStartSequenceSeconds, self:GetCurrentStateTime())
    if sequenceTime >= ChargeEndSequenceSeconds then return end
    self.BossChargeRateActive = true
    self:SetPlayRate((ChargeEndSequenceSeconds - sequenceTime) / self.BossChargeDuration)
    if not UGCGameSystem.IsServer() or self.BossCastPhase ~= 'Charging' or self.BossBreakWindow then return end
    local boss = self:GetOwnerActor()
    if not valid(boss) or not UGCGenericCharacterSystem.IsAlive(boss) then return end
    local mesh = boss.Mesh
    local socket = boss.BreakPointSocket
    local offsets = boss.BreakPointOffsets
    local durability = boss.BreakPointDurability
    assert(durability >= 1, '[BossBreak] BreakPointDurability must be at least 1')
    assert(mesh:DoesSocketExist(socket), '[BossBreak] Missing socket: '..tostring(socket))
    assert(#offsets > 0, '[BossBreak] BreakPointOffsets must contain at least one point')
    local class = UGCObjectUtility.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(BreakPointResource))
    assert(class, '[BossBreak] Missing point class')

    local window = {Boss=boss, Points={}, Remaining=#offsets}
    self.BossBreakWindow = window

    local deadline = UGCGameSystem.GetGameState():GetServerWorldTimeSeconds() + self.BossChargeDuration
    local flashLead = boss.BossChargeFlashLeadSeconds
    for index, offset in ipairs(offsets) do
        local point = UGCGenericCharacterSystem.SpawnGenericCharacter(boss, class,
            mesh:GetSocketLocation(socket), boss:K2_GetActorRotation())
        if not valid(point) then
            self:CloseBossBreakWindow()
            error('[BossBreak] Failed to spawn point '..index)
        end
        window.Points[index] = point
        if not point.RootComponent:K2_AttachToComponent(mesh, socket, 2, 2, 0, false) then
            self:CloseBossBreakWindow()
            error('[BossBreak] Failed to attach point '..index)
        end
        point:K2_SetActorRelativeLocation(offset, false, {}, true)
        point:SetActorScale3D({X=1,Y=1,Z=1})
        point.BossBreakSkill = self
        point.BossBreakPointId = index
        point:OpenCue(deadline, flashLead, durability)
    end
    ugcprint('[BossBreak] open points='..#window.Points)
end

function Skill:BreakBossPoint(point)
    local window = self.BossBreakWindow
    local index = point.BossBreakPointId
    if not window or not index or window.Points[index] ~= point or point.BossBreakSkill ~= self then return end
    if not point:CountBreakHit() then return end
    point.BossBreakSkill = nil
    point:FinishCue('Broken')
    window.Remaining = window.Remaining - 1
    ugcprint('[BossBreak] point='..index..' remaining='..window.Remaining)
    UGCTimerUtility.CreateLuaTimer(0, function()
        if window.Remaining == 0 and valid(self) and self.BossBreakWindow == window then
            interruptBrokenCast(self, window.Boss)
        end
    end, false)
end

local function syncFanInputs(self, boss)
    if not valid(boss) then return end
    local scale = boss:GetActorScale3D()
    self.FanRadius = boss.BossFanBaseRadius * math.max(math.abs(scale.X), math.abs(scale.Y))
    self.FanAngle = boss.BossFanAngle
    self.FanHeight = boss.BossFanHeight
end

function Skill:OnEnableSkill_BP()
    syncFanInputs(self, self:GetOwnerActor())
    Skill.SuperClass.OnEnableSkill_BP(self)
end

function Skill:CanActivateSkill_BP()
    local boss = self:GetOwnerActor()
    if not valid(boss) then return false end
    local duration = boss.BossChargeDuration
    if not duration or not (duration >= MinimumChargeDuration and duration < math.huge) then
        return false
    end
    return Skill.SuperClass.CanActivateSkill_BP(self)
end

function Skill:OnActivateSkill_BP()
    local boss = self:GetOwnerActor()
    syncFanInputs(self, boss)
    self.BossChargeDuration = boss.BossChargeDuration
    if UGCGameSystem.IsServer() then
        self.BossCastPhase = 'Charging'
        if valid(boss) then boss.BossActiveSkill = self end
    end
    Skill.SuperClass.OnActivateSkill_BP(self)
end

function Skill:OnDeActivateSkill_BP(reason)
    restoreChargeRate(self)
    self.BossChargeDuration = nil
    self.BossCastPhase = nil
    if UGCGameSystem.IsServer() then
        self:CloseBossBreakWindow()
        local boss = self:GetOwnerActor()
        if valid(boss) and boss.BossActiveSkill == self then boss.BossActiveSkill = nil end
    end
    Skill.SuperClass.OnDeActivateSkill_BP(self, reason)
end

return Skill
