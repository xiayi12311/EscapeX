-- Server-side board entry points. The window point is authoritative for which
-- encounter it belongs to; the client never supplies an encounter id, a player
-- key, or a board count. Every refusal is a named code so the focus layer can
-- show the player something specific instead of a silent no-op.
local World = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local M = {}
M.Config = {Label = '安装木板', BusyLabel = '安装中', FullLabel = '已封满',
    CancelLabel = '取消安装', InstalledLabel = '已装一块'}
local Message = {
    NO_WINDOWS_IN_ENCOUNTER = '本防守没有可封的窗户',
    UNKNOWN_WINDOW = '未找到该窗户',
    WINDOW_FULL = '这个窗户已经封满',
    WINDOW_BUSY = '队友正在封这个窗户',
    ALREADY_INSTALLING = '你已经在安装木板',
    CLIMB_IN_PROGRESS = '有僵尸正在翻窗',
    INSTALLER_INELIGIBLE = '离窗户太远或已无法安装',
    ENCOUNTER_NOT_STARTED = '本防守还没开始',
    ENCOUNTER_ENDED = '本防守已经结束',
    WINDOW_SEALED = '窗户已封住',
    CLIMB_CAPACITY_FULL = '翻窗通道已满',
    NOT_INSTALLING = '你没有在安装木板',
    NOT_CLIMBING = '该僵尸没有在翻窗',
    INVALID_BOARD_REQUEST = '安装请求无效',
    SERVICE_UNAVAILABLE = 'GameMode 不可用',
}
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

function M.ErrorText(reason)
    if type(reason) == 'table' then
        local parts = {}
        for _, issue in ipairs(reason) do
            parts[#parts+1] = tostring(issue.Code) .. '[' .. tostring(issue.PointId)
                .. '.' .. tostring(issue.Field) .. ']'
        end
        return table.concat(parts, '; ')
    end
    return Message[reason] or tostring(reason)
end

local function service(controller)
    local gm = UGCGameSystem.GetGameMode()
    if not valid(gm) then return nil, 'SERVICE_UNAVAILABLE' end
    if not gm.ZombieDefenseService then return nil, 'ENCOUNTER_NOT_STARTED' end
    return gm.ZombieDefenseService
end

-- A window point is only usable when it is the registered Actor of that
-- encounter; a look-alike placed elsewhere must not open a board slot.
local function registered(controller, point)
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Window))
    if not class or not UE.IsA(point, class) then return false, 'UNKNOWN_WINDOW' end
    if not valid(point.InteractionPoint) then return false, 'UNKNOWN_WINDOW' end
    return true
end

function M.RequestInstall(controller, point)
    if not (valid(controller) and controller:HasAuthority() and valid(point)) then
        return false, 'INVALID_BOARD_REQUEST'
    end
    local ok, reason = registered(controller, point)
    if not ok then return false, reason end
    local svc, serviceError = service(controller)
    if not svc then return false, serviceError end
    local key = UGCGameSystem.GetPlayerKeyByPlayerController(controller)
    if type(key) ~= 'number' or key < 0 then return false, 'INVALID_BOARD_REQUEST' end
    return svc:InstallBoard(point.EncounterId, point.PointId, key,
        UGCGameSystem.GetServerTimeSec())
end

function M.CancelInstall(controller)
    if not (valid(controller) and controller:HasAuthority()) then
        return false, 'INVALID_BOARD_REQUEST'
    end
    local svc, serviceError = service(controller)
    if not svc then return false, serviceError end
    local key = UGCGameSystem.GetPlayerKeyByPlayerController(controller)
    if type(key) ~= 'number' or key < 0 then return false, 'INVALID_BOARD_REQUEST' end
    -- Cancel is encounter-agnostic: one player can only ever install one board,
    -- so the service is asked across the encounters it owns instead of being
    -- handed an encounter id the client could spoof.
    for encounterId in pairs(svc.Runs) do
        local cancelled, pointId = svc:CancelBoard(encounterId, key)
        if cancelled then return true, pointId end
    end
    return false, 'NOT_INSTALLING'
end

-- Death, disconnect and leaving the encounter all use this so a board cannot be
-- finished from a corpse or by a player whose controller is already gone.
function M.ReleasePlayer(gm, playerKey)
    if not valid(gm) or not gm.ZombieDefenseService then return nil end
    if type(playerKey) ~= 'number' or playerKey < 0 then return nil end
    local svc = gm.ZombieDefenseService
    for encounterId in pairs(svc.Runs) do
        local pointId = svc:BoardPlayerLeft(encounterId, playerKey)
        if pointId then return pointId end
    end
    return nil
end

function M.Status(gm, point)
    if not (valid(gm) and gm.ZombieDefenseService and valid(point)) then return nil end
    return gm.ZombieDefenseService:Board(point.EncounterId, point.PointId)
end

return M
