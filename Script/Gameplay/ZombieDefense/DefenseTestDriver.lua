-- Automatic wave driver; server roster owns player elimination policy.
local Team = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTeamPolicy')
local M = {}
M.Config = {
    Enabled = true,
    EncountersByMap = {ZombieTestMap = 'ZombieTest', UGCmap = 'DefenseMainTest'},
    TickSeconds = 0.2,
}
local owners = setmetatable({}, {__mode='k'})
local fail
local function valid(o) return o and KismetSystemLibrary.IsValid(o) end
local function enabledFor(gm, encounter)
    local map = UGCGameSystem.GetCurrentLevel(gm, true)
    return M.Config.Enabled and M.Config.EncountersByMap[map] == encounter
end
function M.Stop(gm)
    local runs = owners[gm]
    if not runs then return end
    for _, run in pairs(runs) do UGCTimerUtility.RemoveLuaTimer(run.Timer) end
    owners[gm] = nil
end
local function publish(point, snapshot, reason, now)
    if not valid(point) then return end
    local text
    if reason then
        local Interaction = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseStartInteraction')
        text = '波次错误: '..Interaction.ErrorText(reason)
    elseif snapshot.State == 'Preparing' then
        text = '准备 '..math.max(0,math.ceil(snapshot.ReadyAt-now))..'秒'
    elseif snapshot.State == 'Resting' then
        text = '下一波 '..math.max(0,math.ceil(snapshot.ReadyAt-now))..'秒'
    elseif snapshot.State == 'Fighting' then
        text = '第'..snapshot.WaveIndex..'/'..snapshot.WaveCount..'波 存活'..snapshot.AliveCount
    elseif snapshot.State == 'Succeeded' then
        text = snapshot.BossState == 'Active' and '变异班主任已出现' or '全部波次完成'
    elseif snapshot.State == 'Failed' then text = '已失败' end
    point.DefenseStatusText = text or snapshot.State
end
function M.Start(gm, point, instanceId, count)
    assert(valid(gm) and gm:HasAuthority(), 'DEFENSE_SERVER_ONLY')
    -- The driver only runs the automatic test flow on the configured test map. Refuse
    -- instead of half-starting: capturing a roster and marking the point started here
    -- would freeze that encounter with no timer, no result, and no way to relaunch it.
    if not enabledFor(gm, point.EncounterId) then
        return false, 'DRIVER_DISABLED'
    end
    local keys, reason = Team.Capture(gm,count)
    if not keys then return false, reason end
    local ok; ok, reason = gm:StartZombieDefense(point.EncounterId,instanceId,count)
    if not ok then return ok, reason end
    Team.Attach(gm,point.EncounterId,keys)
    owners[gm] = owners[gm] or {}
    local encounter = point.EncounterId
    local run = {Point=point}
    owners[gm][encounter] = run
    local function tick()
        -- Another callback may already have settled or stopped this run (a direct kill
        -- failure removes the timer and the owner entry). A queued tick must then bow out
        -- instead of stepping an encounter whose roster is gone.
        if not owners[gm] or owners[gm][encounter] ~= run then return end
        if not valid(gm) or not gm:HasAuthority() then M.Stop(gm);return end
        if not enabledFor(gm, encounter) then
            -- Reached only when the setting/map changes mid-run. Stop advancing and say
            -- so; the encounter keeps its roster and can be settled by an explicit
            -- ShutdownZombieDefense. No fake victory/failure is invented here.
            if valid(point) then point.DefenseStatusText = '自动推进已停止，需重开遭遇' end
            M.Stop(gm);return
        end
        -- Authoritative team result is evaluated before the offline pause: a roster
        -- that is fully eliminated must still settle even when nobody is connected.
        local teamFailed = Team.TeamFailed(gm,encounter)
        -- Nobody connected means nobody can fight: hold the wave instead of spawning
        -- more enemies onto an empty map. The encounter stays open for the reconnect,
        -- which is what the approved disconnect rule asks for.
        if not teamFailed and Team.Online(gm,encounter) == 0 then
            if valid(point) then point.DefenseStatusText = '等待玩家重连' end
            return
        end
        -- Consume final deaths first, but only commit victory on a later timer tick
        -- after sampling the roster again. Killed may fail immediately in between.
        local snapshot, err = gm:StepZombieDefense(encounter,teamFailed,not run.VictoryCandidate)
        if snapshot then
            run.VictoryCandidate = snapshot.State=='Fighting' and snapshot.WaveIndex==snapshot.WaveCount
                and snapshot.Generated==snapshot.Total and snapshot.PendingCount==0
                and snapshot.AliveCount==0 and not snapshot.Error and not snapshot.AdapterError
        end
        if snapshot and not err then err = snapshot.Error or snapshot.AdapterError end
        publish(point,snapshot,err or (not snapshot and 'MISSING_SNAPSHOT' or nil),KismetSystemLibrary.GetGameTimeInSeconds(gm))
        if err or not snapshot or snapshot.State == 'Succeeded' or snapshot.State == 'Failed' then
            UGCTimerUtility.RemoveLuaTimer(run.Timer)
            owners[gm][encounter] = nil
        end
    end
    run.Tick = tick
    run.Timer = UGCTimerUtility.CreateLuaTimer(M.Config.TickSeconds,tick,true)
    publish(point,gm.ZombieDefenseService:Snapshot(encounter),nil,KismetSystemLibrary.GetGameTimeInSeconds(gm))
    return true
end
-- Submit failure outside the timer/map gate: a resolved team must settle even when
-- the automatic wave driver is disabled.
local function fail(gm,encounter)
    local run=owners[gm] and owners[gm][encounter]
    local service=gm.ZombieDefenseService
    if not service then return end
    local before=service:Snapshot(encounter)
    if not before or before.State=='Succeeded' or before.State=='Failed' then return end
    local snapshot, err=gm:StepZombieDefense(encounter,true)
    if run then
        publish(run.Point,snapshot,err,KismetSystemLibrary.GetGameTimeInSeconds(gm))
        UGCTimerUtility.RemoveLuaTimer(run.Timer)
        owners[gm][encounter]=nil
    end
end
function M.OnKilled(gm,key)
    local encounters = Team.OnKilled(gm,key)
    if #encounters == 0 then
        -- The victim's key could not be resolved, so OnKilled could not attribute the
        -- death. Re-check every roster with the same authoritative rule instead of
        -- assuming nobody died; without it a wipe is missed while the timer is gated.
        encounters = Team.Encounters(gm)
    end
    for _, encounter in ipairs(encounters) do
        if Team.TeamFailed(gm,encounter) then fail(gm,encounter) end
    end
end
-- A disconnect never fails the encounter by itself. If the players still online are
-- wiped, it fails now; if every remaining member is offline but alive, the team
-- waits for a reconnect instead of failing.
function M.OnExit(gm,key)
    Team.OnExit(gm,key)
    for _, encounter in ipairs(Team.Encounters(gm)) do
        if Team.TeamFailed(gm,encounter) then fail(gm,encounter) end
    end
end
function M.OnLogin(gm,key,knownAlive) Team.OnLogin(gm,key,knownAlive) end
return M
