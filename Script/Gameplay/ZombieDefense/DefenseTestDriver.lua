-- Explicitly approved test-only policy: automatic waves, no team-elimination loss.
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
    local ok, reason = gm:StartZombieDefense(point.EncounterId,instanceId,count)
    if not ok or not enabled then return ok, reason end
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
        -- Intentional approved test policy, NOT a default production team state.
        local snapshot, err = gm:StepZombieDefense(encounter,false)
        if snapshot and not err then err = snapshot.Error or snapshot.AdapterError end
        publish(point,snapshot,err or (not snapshot and 'MISSING_SNAPSHOT' or nil),UGCGameSystem.GetServerTimeSec())
        if err or not snapshot or snapshot.State == 'Succeeded' or snapshot.State == 'Failed' then
            UGCTimerUtility.RemoveLuaTimer(run.Timer)
            owners[gm][encounter] = nil
        end
    end
    run.Timer = UGCTimerUtility.CreateLuaTimer(M.Config.TickSeconds,tick,true)
    publish(point,gm.ZombieDefenseService:Snapshot(encounter),nil,UGCGameSystem.GetServerTimeSec())
    return true
end
return M
