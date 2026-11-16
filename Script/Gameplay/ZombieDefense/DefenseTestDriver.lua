-- Automatic wave driver; server roster owns player elimination policy.
local Team = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTeamPolicy')
local M = {}
M.Config = {Enabled = true, MapName = 'ZombieTestMap', TickSeconds = 0.2}
local owners = setmetatable({}, {__mode='k'})
local function valid(o) return o and KismetSystemLibrary.IsValid(o) end
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
    elseif snapshot.State == 'Succeeded' then text = '全部波次完成'
    elseif snapshot.State == 'Failed' then text = '已失败' end
    point.DefenseStatusText = text or snapshot.State
end
function M.Start(gm, point, instanceId, count)
    assert(valid(gm) and gm:HasAuthority(), 'DEFENSE_SERVER_ONLY')
    local enabled = M.Config.Enabled and UGCGameSystem.GetCurrentLevel(gm,true) == M.Config.MapName
    local keys, reason = Team.Capture(gm,count)
    if not keys then return false, reason end
    local ok; ok, reason = gm:StartZombieDefense(point.EncounterId,instanceId,count)
    if not ok then return ok, reason end
    Team.Attach(gm,point.EncounterId,keys)
    if not enabled then return true end
    owners[gm] = owners[gm] or {}
    local encounter = point.EncounterId
    local run = {Point=point}
    owners[gm][encounter] = run
    local function tick()
        if not valid(gm) or not gm:HasAuthority() then M.Stop(gm);return end
        if not M.Config.Enabled or UGCGameSystem.GetCurrentLevel(gm,true) ~= M.Config.MapName then
            if valid(point) then point.DefenseStatusText = '测试波次已停止' end
            M.Stop(gm);return
        end
        -- Consume final deaths first, but only commit victory on a later timer tick
        -- after sampling the roster again. Killed may fail immediately in between.
        local snapshot, err = gm:StepZombieDefense(encounter,Team.TeamFailed(gm,encounter),not run.VictoryCandidate)
        if snapshot then
            run.VictoryCandidate = snapshot.State=='Fighting' and snapshot.WaveIndex==snapshot.WaveCount
                and snapshot.Generated==snapshot.Total and snapshot.PendingCount==0
                and snapshot.AliveCount==0 and not snapshot.Error and not snapshot.AdapterError
        end
        if snapshot and not err then err = snapshot.Error or snapshot.AdapterError end
        publish(point,snapshot,err or (not snapshot and 'MISSING_SNAPSHOT' or nil),UGCGameSystem.GetServerTimeSec())
        if err or not snapshot or snapshot.State == 'Succeeded' or snapshot.State == 'Failed' then
            UGCTimerUtility.RemoveLuaTimer(run.Timer)
            owners[gm][encounter] = nil
        end
    end
    run.Tick = tick
    run.Timer = UGCTimerUtility.CreateLuaTimer(M.Config.TickSeconds,tick,true)
    publish(point,gm.ZombieDefenseService:Snapshot(encounter),nil,UGCGameSystem.GetServerTimeSec())
    return true
end
function M.OnKilled(gm,key)
    for _, encounter in ipairs(Team.OnKilled(gm,key)) do
        if Team.TeamFailed(gm,encounter) then
            local run=owners[gm] and owners[gm][encounter]
            local snapshot, err=gm:StepZombieDefense(encounter,true)
            if run then
                publish(run.Point,snapshot,err,UGCGameSystem.GetServerTimeSec())
                UGCTimerUtility.RemoveLuaTimer(run.Timer)
                owners[gm][encounter]=nil
            end
        end
    end
end
return M
