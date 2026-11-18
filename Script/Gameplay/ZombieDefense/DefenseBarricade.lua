-- Server-authoritative board state for placed window points. No timers and no
-- engine calls: every entry point takes trusted server time, and install
-- completion takes the caller's eligibility predicate, so the same object can
-- be exercised offline. Boards are stored outermost first; zombie damage always
-- hits the outermost surviving board and never carries into the next one.
local Barricade = {}
Barricade.__index = Barricade

local function positive(value, name, integer)
    assert(type(value) == 'number' and value == value and value > 0 and value < math.huge,
        name)
    if integer then assert(value == math.floor(value), name) end
end

local function windowConfig(config)
    assert(type(config) == 'table', 'INVALID_BARRICADE_CONFIG')
    positive(config.BoardsPerWindow, 'INVALID_BOARD_COUNT', true)
    positive(config.BoardDurability, 'INVALID_BOARD_DURABILITY')
    positive(config.InstallSeconds, 'INVALID_INSTALL_SECONDS')
    positive(config.InstallRange, 'INVALID_INSTALL_RANGE')
    positive(config.ClimbCapacity, 'INVALID_CLIMB_CAPACITY', true)
    return {BoardsPerWindow = config.BoardsPerWindow,
        BoardDurability = config.BoardDurability,
        InstallSeconds = config.InstallSeconds,
        InstallRange = config.InstallRange,
        ClimbCapacity = config.ClimbCapacity}
end

-- windows: array of {PointId = string, Actor = any, Config = authored board settings}
function Barricade.New(windows)
    assert(type(windows) == 'table', 'INVALID_WINDOWS')
    local list, byId = {}, {}
    for index, entry in ipairs(windows) do
        assert(index == #list + 1, 'NONCONTIGUOUS_WINDOWS')
        local pointId = entry.PointId
        assert(type(pointId) == 'string' and pointId ~= '', 'INVALID_WINDOW_ID')
        assert(not byId[pointId], 'DUPLICATE_WINDOW_ID: ' .. pointId)
        local window = {PointId = pointId, Actor = entry.Actor,
            Config = windowConfig(entry.Config), Boards = {}, VisualSlots = {}, Installer = nil, Climbers = {}}
        byId[pointId] = window
        list[#list + 1] = window
    end
    return setmetatable({List = list, ById = byId, Installer = {}, Time = nil}, Barricade)
end

function Barricade:_time(now)
    assert(type(now) == 'number' and now == now and now >= 0, 'INVALID_TIME')
    assert(not self.Time or now >= self.Time, 'TIME_REVERSED')
    self.Time = now
end

function Barricade:_window(pointId)
    local window = self.ById[pointId]
    if not window then return nil, 'UNKNOWN_WINDOW' end
    return window
end

function Barricade:Range(pointId)
    local window = self:_window(pointId)
    return window and window.Config.InstallRange
end

function Barricade:IsPassable(pointId)
    local window = self.ById[pointId]
    return window ~= nil and #window.Boards == 0
end

function Barricade:Snapshot(pointId)
    local window, reason = self:_window(pointId)
    if not window then return nil, reason end
    local durability = 0
    for _, value in ipairs(window.Boards) do durability = durability + value end
    return {PointId = pointId, Boards = #window.Boards,
        MaxBoards = window.Config.BoardsPerWindow, Durability = durability,
        Installer = window.Installer,
        InstallRange = window.Config.InstallRange,
        Passable = #window.Boards == 0, Climbers = #window.Climbers}
end

function Barricade:Summary()
    local summary = {Windows = 0, Open = 0, Installing = 0, Boards = 0, Capacity = 0}
    for _, window in ipairs(self.List) do
        summary.Windows = summary.Windows + 1
        summary.Boards = summary.Boards + #window.Boards
        summary.Capacity = summary.Capacity + window.Config.BoardsPerWindow
        if #window.Boards == 0 then summary.Open = summary.Open + 1 end
        if window.Installer then summary.Installing = summary.Installing + 1 end
    end
    return summary
end

-- One installer per window and one window per player; a passing zombie blocks a
-- new board, because the board would otherwise seal the entrance mid-climb.
function Barricade:TryInstall(pointId, playerKey)
    assert(type(playerKey) == 'number' and playerKey >= 0, 'INVALID_PLAYER_KEY')
    local window, reason = self:_window(pointId)
    if not window then return false, reason end
    if #window.Boards >= window.Config.BoardsPerWindow then return false, 'WINDOW_FULL' end
    if window.Installer then
        if window.Installer == playerKey then return false, 'ALREADY_INSTALLING' end
        return false, 'WINDOW_BUSY'
    end
    if self.Installer[playerKey] then return false, 'ALREADY_INSTALLING' end
    if #window.Climbers > 0 then return false, 'CLIMB_IN_PROGRESS' end
    window.Installer = playerKey
    self.Installer[playerKey] = pointId
    return true
end

-- Returns the interrupted window id, or nil when this player was not installing.
function Barricade:ReleasePlayer(playerKey)
    local pointId = self.Installer[playerKey]
    if not pointId then return nil end
    local window = self.ById[pointId]
    self.Installer[playerKey] = nil
    if window and window.Installer == playerKey then
        window.Installer = nil
    end
    return pointId
end

function Barricade:CancelWindow(pointId, playerKey)
    local window, reason = self:_window(pointId)
    if not window then return false, reason end
    if not window.Installer then return false, 'NOT_INSTALLING' end
    if window.Installer ~= playerKey then return false, 'NOT_INSTALLER' end
    self:ReleasePlayer(playerKey)
    return true
end

function Barricade:InterruptAll()
    local interrupted = 0
    for _, window in ipairs(self.List) do
        if window.Installer then
            self.Installer[window.Installer] = nil
            window.Installer = nil
            interrupted = interrupted + 1
        end
    end
    return interrupted
end

local function nextVisualSlot(window)
    local used = {}
    for _, slot in ipairs(window.VisualSlots) do used[slot] = true end
    for slot = 1, window.Config.BoardsPerWindow do
        if not used[slot] then return slot end
    end
end

function Barricade:CompleteInstall(pointId, playerKey)
    local window, reason = self:_window(pointId)
    if not window then return false, reason end
    if window.Installer == nil or window.Installer ~= playerKey then return false, 'NOT_INSTALLING' end
    self:ReleasePlayer(playerKey)
    if #window.Climbers > 0 then return false, 'CLIMB_IN_PROGRESS' end
    if #window.Boards >= window.Config.BoardsPerWindow then return false, 'WINDOW_FULL' end
    local slot = assert(nextVisualSlot(window), 'NO_FREE_BOARD_VISUAL_SLOT')
    window.Boards[#window.Boards + 1] = window.Config.BoardDurability
    window.VisualSlots[#window.VisualSlots + 1] = slot
    return true, #window.Boards
end

-- Reserved contract for the zombie-side traversal integration. Climbing wins
-- over an unfinished board: the installer is interrupted rather than the climb.
function Barricade:BeginClimb(pointId, enemyId)
    local window, reason = self:_window(pointId)
    if not window then return false, reason end
    if #window.Boards > 0 then return false, 'WINDOW_SEALED' end
    if #window.Climbers >= window.Config.ClimbCapacity then return false, 'CLIMB_CAPACITY_FULL' end
    for _, existing in ipairs(window.Climbers) do
        if existing == enemyId then return false, 'ALREADY_CLIMBING' end
    end
    local interrupted = nil
    if window.Installer then
        interrupted = window.Installer
        self.Installer[interrupted] = nil
        window.Installer = nil
    end
    window.Climbers[#window.Climbers + 1] = enemyId
    return true, interrupted
end

function Barricade:EndClimb(pointId, enemyId)
    local window, reason = self:_window(pointId)
    if not window then return false, reason end
    for index, existing in ipairs(window.Climbers) do
        if existing == enemyId then
            table.remove(window.Climbers, index)
            return true
        end
    end
    return false, 'NOT_CLIMBING'
end

-- One hit damages one board only: no overflow, so a single burst cannot clear
-- several independent boards and the board count stays readable to players.
function Barricade:Damage(pointId, amount, now)
    self:_time(now)
    assert(type(amount) == 'number' and amount > 0 and amount < math.huge, 'INVALID_DAMAGE')
    local window, reason = self:_window(pointId)
    if not window then return nil, reason end
    if #window.Boards == 0 then return nil, 'WINDOW_OPEN' end
    local remaining = window.Boards[1] - amount
    local destroyed = 0
    if remaining > 0 then
        window.Boards[1] = remaining
    else
        table.remove(window.Boards, 1)
        table.remove(window.VisualSlots, 1)
        destroyed = 1
    end
    return {PointId = pointId, Destroyed = destroyed, Boards = #window.Boards,
        Durability = window.Boards[1] or 0, Passable = #window.Boards == 0}
end

return Barricade
