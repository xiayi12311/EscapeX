-- 测试用功能：玩家死亡后自动在死亡位置原地复活。正式玩法请关闭开关或整体移除本模块。
-- 复活方式与复活接口（UGCPlayerPawnSystem.SetDefaultPlayerRespawnPointSelectionMethod、
-- UGCPlayerPawnSystem.RespawnPlayer）在官方 API 文档中标注为【实验性】，因此本模块保留总开关，
-- 只在服务器执行，并且不改动玩家背包、掉落和战绩。
-- 依赖引擎记录的“最近一次死亡位置”，需要死亡时已生成玩家 Pawn 才有可比对的坐标。
local M = {}

M.Defaults = {
    -- 可在 GameMode 蓝图上添加同名布尔量覆盖；蓝图变量不存在时取这里的默认值。
    TestAutoReviveEnabled = true,
    TestAutoReviveDelay = 1.0,
}

M.lastDeath = {}

function M.config(gm, key)
    local v = gm[key]
    if v == nil then return M.Defaults[key] end
    return v
end

function M.log(message)
    ugcprint("[TestRevive] " .. message)
end

function M.respawnMethod()
    local e = EUGCPlayerRespawnPointSelectionMethod
    -- 枚举表按编辑器版本导出，缺失时退回快照值 0（原地复活）。
    if e and e.RespawnOnTheSpot ~= nil then return e.RespawnOnTheSpot end
    return 0
end

function M.playerKey(controller, pawn)
    if controller and KismetSystemLibrary.IsValid(controller) then
        local key = UGCGameSystem.GetPlayerKeyByPlayerController(controller)
        if key and key >= 0 then return key end
    end
    if pawn and KismetSystemLibrary.IsValid(pawn) then
        local key = UGCGameSystem.GetPlayerKeyByPlayerPawn(pawn)
        if key and key >= 0 then return key end
    end
    return -1
end

function M.position(actor)
    if not (actor and KismetSystemLibrary.IsValid(actor)) then return nil end
    local v = actor:K2_GetActorLocation()
    if not v then return nil end
    return {X=v.X, Y=v.Y, Z=v.Z}
end

function M.describe(p)
    if not p then return "unknown" end
    return string.format("(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
end

function M.timerName(key)
    return "TestAutoRevive_" .. tostring(key)
end

---服务器 BeginPlay 调用一次：把默认复活方式设为原地复活。
function M.setup(gm)
    if not gm:HasAuthority() then return false end
    if not M.config(gm, "TestAutoReviveEnabled") then
        M.log("TEST-ONLY auto in-place revive is disabled")
        return false
    end
    -- RespawnMethodInfo 只在“指定世界坐标复活”时生效，原地复活传入被忽略的零向量。
    UGCPlayerPawnSystem.SetDefaultPlayerRespawnPointSelectionMethod(
        M.respawnMethod(), {X=0, Y=0, Z=0})
    local delay = M.config(gm, "TestAutoReviveDelay") or 0
    if delay < 0 then delay = 0 end
    M.log(string.format(
        "TEST-ONLY auto in-place revive enabled: method=RespawnOnTheSpot, delay=%.2fs", delay))
    return true
end

---玩家被淘汰事件（服务器）。排队一次原地复活，同一玩家的重复事件由计时器名去重。
function M.onKilled(gm, killer, victimController, victimPawn, damageType)
    if not gm:HasAuthority() then return end
    if not M.config(gm, "TestAutoReviveEnabled") then return end
    local key = M.playerKey(victimController, victimPawn)
    if key < 0 then
        M.log("Killed event without a resolvable PlayerKey, nothing scheduled")
        return
    end
    local name = M.timerName(key)
    if UGCTimerUtility.IsLuaTimerExistByName(name) then
        M.log("PlayerKey=" .. key .. " revive already queued, ignored the repeat kill")
        return
    end
    local delay = M.config(gm, "TestAutoReviveDelay") or 0
    if delay < 0 then delay = 0 end
    local death = M.position(victimPawn)
    M.lastDeath[key] = death
    M.log(string.format(
        "PlayerKey=%d died at %s, reviving in place after %.2fs", key, M.describe(death), delay))
    UGCTimerUtility.CreateLuaTimer(delay, function()
        -- IsDestoryAlivePawn=false：只复活已死亡的角色，不动存活的 Pawn。
        -- DestroyDelayTime 取默认 0.01，文档说明该项不能为 0。
        UGCPlayerPawnSystem.RespawnPlayer(key, 0, false, 0.01)
        M.log("PlayerKey=" .. key .. " revive requested")
    end, false, name)
end

---玩家复活事件（服务器）。比对复活点与死亡位置，便于测试时直接确认是否真的原地。
function M.onRespawn(gm, respawnedController)
    if not gm:HasAuthority() then return end
    if not M.config(gm, "TestAutoReviveEnabled") then return end
    local pawn = nil
    if respawnedController and KismetSystemLibrary.IsValid(respawnedController) then
        pawn = UGCGameSystem.GetPlayerPawnByPlayerController(respawnedController)
    end
    local key = M.playerKey(respawnedController, pawn)
    local here = M.position(pawn)
    local death = key >= 0 and M.lastDeath[key] or nil
    if death and here then
        local gap = math.sqrt((here.X-death.X)^2 + (here.Y-death.Y)^2 + (here.Z-death.Z)^2)
        M.log(string.format("PlayerKey=%d revived at %s, %.0fcm from the death spot",
            key, M.describe(here), gap))
    else
        M.log("PlayerKey=" .. tostring(key) .. " respawn event received without comparable positions")
    end
    if key >= 0 then M.lastDeath[key] = nil end
end

return M
