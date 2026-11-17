-- Start requests only. Wave progression and authoritative team rules remain external.
local World = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local M = {}
M.Config = {Range = 350, Label = '启动', StartedLabel = '已启动', PendingLabel = '启动中'}
local serial = 0
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end
function M.InRange(point, pawn)
    if not (valid(point) and valid(pawn)) then return false end
    local a, b = point:K2_GetActorLocation(), pawn:K2_GetActorLocation()
    return (a.X-b.X)^2 + (a.Y-b.Y)^2 + (a.Z-b.Z)^2 <= M.Config.Range^2
end
-- Player-facing wording only; the raw code stays in the log for diagnosis. Registry
-- failures stay structured (Code[PointId.Field]) because they name a configuration
-- defect the map author must fix, not a player mistake.
local Message = {
    DRIVER_DISABLED = '当前地图未开启自动波次',
    INVALID_PLAYER_COUNT = '参战人数不合法',
    PARTICIPANT_NOT_ALIVE = '有队友当前不在存活状态',
    PARTICIPANT_COUNT_CHANGED = '参战人数在启动时发生变化',
    PARTICIPANT_ALREADY_ASSIGNED = '已有其他防守正在进行',
    OUT_OF_RANGE = '离启动点太远',
    ENCOUNTER_ALREADY_STARTED = '本防守已经启动',
    POINT_DISABLED = '启动点已停用',
    UNREGISTERED_START_POINT = '启动点未注册或重复',
    INVALID_START_POINT = '启动点类型不匹配',
    GAMEMODE_UNAVAILABLE = 'GameMode 不可用',
    INVALID_START_REQUEST = '启动请求无效',
}
function M.ErrorText(reason)
    if type(reason) ~= 'table' then
        return Message[reason] or tostring(reason)
    end
    local parts = {}
    for _, issue in ipairs(reason) do
        parts[#parts+1] = tostring(issue.Code) .. '[' .. tostring(issue.PointId)
            .. '.' .. tostring(issue.Field) .. ']'
    end
    return table.concat(parts, '; ')
end
function M.Request(controller, point)
    if not (valid(controller) and controller:HasAuthority() and valid(point)) then
        return false, 'INVALID_START_REQUEST'
    end
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Start))
    if not class or not UE.IsA(point, class) then return false, 'INVALID_START_POINT' end
    local matches, found = 0, false
    for _, actor in pairs(UGCActorComponentUtility.GetAllActorsOfClass(controller, class)) do
        if valid(actor) and actor.Enabled and actor.EncounterId == point.EncounterId then
            matches = matches + 1; if actor == point then found = true end
        end
    end
    if matches ~= 1 or not found then return false, 'UNREGISTERED_START_POINT' end
    local pawn = UGCGameSystem.GetPlayerPawnByPlayerController(controller)
    if not M.InRange(point, pawn) then return false, 'OUT_OF_RANGE' end
    if point.Enabled ~= true then return false, 'POINT_DISABLED' end
    if point.DefenseStarted then return false, 'ENCOUNTER_ALREADY_STARTED' end
    local gm = UGCGameSystem.GetGameMode()
    if not valid(gm) then return false, 'GAMEMODE_UNAVAILABLE' end
    -- Only the unique registered Start Actor may request this encounter.
    if gm.ZombieDefenseService then
        local starts = gm.ZombieDefenseService.Registry:GetPoints(point.EncounterId, 'Start')
        if not starts or #starts ~= 1 or starts[1] ~= point then return false, 'UNREGISTERED_START_POINT' end
    end
    local players = UGCGameSystem.GetAllPlayerController(false)
    local count, contains = 0, false
    for _, pc in pairs(players) do
        if valid(pc) then count = count + 1; if pc == controller then contains = true end end
    end
    if not contains or count < 1 or count > 4 then return false, 'INVALID_PLAYER_COUNT' end
    serial = serial + 1
    local Driver = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver')
    local ok, reason = Driver.Start(gm, point,
        point.EncounterId .. ':interaction:' .. serial, count)
    if not ok then return false, reason end
    point.DefenseStarted = true
    return true
end
return M
