local Weakness = {}
local pauseReason = 'EscapeX.BossWeakness'

-- The base duration is the playback range of CastSkill in each skill asset.
local config = {
    SkillInterrupted = {
        Duration = 'LightWeaknessDuration',
        SequenceSeconds = 2,
        Resource = 'Asset/Blueprint/Prefabs/Skills/ZombieBossWeaknessLight.ZombieBossWeaknessLight_C',
    },
    ToughnessBroken = {
        Duration = 'HeavyWeaknessDuration',
        SequenceSeconds = 5,
        Resource = 'Asset/Blueprint/Prefabs/Skills/ZombieBossWeakness.ZombieBossWeakness_C',
    },
}

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

local function serverTime()
    return UGCGameSystem.GetGameState():GetServerWorldTimeSeconds()
end

function Weakness.GetSkill(boss, kind)
    local settings = assert(config[kind], '[EscapeX Boss] Unknown weakness: '..tostring(kind))
    local path = UGCGameSystem.GetUGCResourcesFullPath(settings.Resource)
    return UGCPersistEffectSystem.GetSkillsByClass(boss, path)[1]
end

function Weakness.CancelPlaybackCheck(boss)
    if boss.BossWeaknessPlaybackTimer then
        UGCTimerUtility.RemoveLuaTimer(boss.BossWeaknessPlaybackTimer)
        boss.BossWeaknessPlaybackTimer = nil
    end
end

function Weakness.SyncPlayback(boss, skill)
    Weakness.CancelPlaybackCheck(boss)
    local state = boss.BossWeaknessPlayback
    if not state then return end

    local baseSeconds = config[state.Kind].SequenceSeconds
    local authority = boss:HasAuthority()
    local function applyWhenReady()
        if not valid(boss) or boss.BossWeaknessPlayback ~= state then return true end
        skill = skill or Weakness.GetSkill(boss, state.Kind)
        local remaining = state.EndAt - serverTime()
        if remaining <= 0 then
            if authority and valid(skill) and skill:IsActivating() then skill:DeActivateSkill(0) end
            return true
        end
        if not valid(skill) or not skill:IsActivating() or skill:GetCurrentStateName() ~= 'CastSkill' then
            return false
        end

        -- The runtime rate takes effect only after CastSkill starts. Account for the
        -- Sequence time already played before the callback or replication arrives.
        local unplayed = baseSeconds - skill:GetCurrentStateTime()
        if unplayed > 0 then skill:SetPlayRate(unplayed / remaining) end
        return true
    end

    -- Lua replication can report CastSkill before its native Sequence player is initialized.
    -- Apply on the next tick so native activation cannot overwrite the rate.
    local timer
    timer = UGCTimerUtility.CreateLuaTimer(0.02, function()
        if not applyWhenReady() then return end
        if valid(boss) then
            Weakness.CancelPlaybackCheck(boss)
        else
            UGCTimerUtility.RemoveLuaTimer(timer)
        end
    end, true)
    boss.BossWeaknessPlaybackTimer = timer
end

function Weakness.Create(kind)
    local Skill = {}
    local settings = config[kind]

    function Skill:CanActivateSkill_BP()
        local boss = self:GetOwnerActor()
        if not valid(boss) or not boss.InterruptBossSkill or boss.BossCombatEnding
            or boss.BossWeakness or not UGCGenericCharacterSystem.IsAlive(boss) then return false end
        if boss:HasAuthority() then
            local duration = boss[settings.Duration]
            if not duration or duration < 0.1 or duration ~= duration or duration == math.huge then
                ugcprint('[EscapeX Boss] Invalid '..settings.Duration)
                return false
            end
        end
        return Skill.SuperClass.CanActivateSkill_BP(self)
    end

    function Skill:OnActivateSkill_BP()
        Skill.SuperClass.OnActivateSkill_BP(self)
        if not UGCGameSystem.IsServer() then return end

        local boss = self:GetOwnerActor()
        local duration = boss[settings.Duration]
        boss.BossWeakness = kind
        boss.BossWeaknessSkill = self
        if kind == 'ToughnessBroken' then boss.BossToughness = 0 end
        UGCGenericCharacterSystem.PauseBehavior(boss, pauseReason)
        UGCGenericCharacterSystem.StopMove(boss)
        boss:InterruptBossSkill()

        boss.BossWeaknessPlayback = {Kind = kind, EndAt = serverTime() + duration}
        boss:ForceNetUpdate()
        Weakness.SyncPlayback(boss, self)
        ugcprint(string.format('[EscapeX Boss] weakness=%s duration=%.2f', kind, duration))
    end

    local function finishWeakness(self)
        self:SetPlayRate(1)
        if not UGCGameSystem.IsServer() then return end
        local boss = self:GetOwnerActor()
        if not valid(boss) or boss.BossWeaknessSkill ~= self then return end
        Weakness.CancelPlaybackCheck(boss)
        boss.BossWeaknessPlayback = false
        boss:ForceNetUpdate()
        boss.BossWeaknessSkill = nil
        boss.BossWeakness = nil
        if boss.BossCombatEnding or not UGCGenericCharacterSystem.IsAlive(boss) then return end
        if kind == 'ToughnessBroken' then
            boss.BossToughness = boss.BossToughnessMax
        end
        UGCGenericCharacterSystem.ResumeBehavior(boss, pauseReason)
        ugcprint('[EscapeX Boss] recovered from '..kind)
    end

    function Skill:OnDeActivateSkill_BP(reason)
        finishWeakness(self)
        Skill.SuperClass.OnDeActivateSkill_BP(self, reason)
    end

    function Skill:OnDisableSkill_BP()
        finishWeakness(self)
        Skill.SuperClass.OnDisableSkill_BP(self)
    end

    return Skill
end

return Weakness
