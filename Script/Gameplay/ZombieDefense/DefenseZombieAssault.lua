-- Zombie side of the window boards: how standing enemies chew through boards and
-- how they occupy an opened window. Pure state machine, no timers and no engine
-- calls: the caller supplies trusted server time plus the contacts it already
-- measured (which enemies actually stand at which window), so the same object
-- runs offline. Damage accrues per window and is only applied once it reaches a
-- whole point, because Barricade:Damage hits the outermost board and drops any
-- overflow: carrying a fraction keeps a slow nibble from stalling forever, while
-- never letting one tick eat two boards.
local Assault = {}
Assault.__index = Assault

local function positive(value, name, integer)
    assert(type(value) == 'number' and value == value and value > 0 and value < math.huge, name)
    if integer then assert(value == math.floor(value), name) end
end

local function config(entry)
    assert(type(entry) == 'table', 'INVALID_ASSAULT_CONFIG')
    positive(entry.DamagePerSecond, 'INVALID_ASSAULT_DPS')
    positive(entry.AttackRange, 'INVALID_ASSAULT_RANGE')
    positive(entry.ClimbSeconds, 'INVALID_CLIMB_SECONDS')
    positive(entry.MaxAttackers, 'INVALID_MAX_ATTACKERS', true)
    return {DamagePerSecond = entry.DamagePerSecond, AttackRange = entry.AttackRange,
        ClimbSeconds = entry.ClimbSeconds, MaxAttackers = entry.MaxAttackers}
end

-- configs: map of PointId -> assault profile, so two windows of different types
-- can be attacked at different speeds without touching the board rules.
function Assault.New(configs)
    assert(type(configs) == 'table', 'INVALID_ASSAULT_CONFIGS')
    local byPoint = {}
    local count = 0
    for pointId, entry in pairs(configs) do
        assert(type(pointId) == 'string' and pointId ~= '', 'INVALID_WINDOW_ID')
        byPoint[pointId] = config(entry)
        count = count + 1
    end
    assert(count > 0, 'INVALID_ASSAULT_CONFIGS')
    return setmetatable({ByPoint = byPoint, Time = nil, Pending = {}, Climbs = {}}, Assault)
end

function Assault:Config(pointId)
    local entry = self.ByPoint[pointId]
    assert(entry, 'UNKNOWN_WINDOW: ' .. tostring(pointId))
    return entry
end

function Assault:Range(pointId)
    return self:Config(pointId).AttackRange
end

function Assault:_time(now)
    assert(type(now) == 'number' and now == now and now >= 0, 'INVALID_TIME')
    assert(not self.Time or now >= self.Time, 'TIME_REVERSED')
    local delta = self.Time and (now - self.Time) or 0
    self.Time = now
    return delta
end

function Assault:_dropClimb(barricade, pointId)
    local climb = self.Climbs[pointId]
    if not climb then return nil end
    self.Climbs[pointId] = nil
    if barricade.ById[pointId] then barricade:EndClimb(pointId, climb.EnemyId) end
    return climb
end

-- contacts: array of {PointId = string, EnemyIds = {string, ...}}
-- Only windows listed here have enemies standing at them; anything absent counts
-- as unattacked rather than being guessed from distance here.
function Assault:Advance(barricade, contacts, now, vault)
    assert(type(barricade) == 'table', 'MISSING_BARRICADE')
    assert(type(contacts) == 'table', 'MISSING_CONTACTS')
    local delta = self:_time(now)
    local events, seen, ended = {}, {}, {}
    for pointId, climb in pairs(self.Climbs) do
        local status = vault.Status(pointId, climb.EnemyId)
        if status ~= "Moving" or now >= climb.EndsAt then
            local landed = status == "Landed"
            self:_dropClimb(barricade, pointId)
            vault.Stop(climb.EnemyId, landed)
            ended[pointId] = true
            events[#events + 1] = {Kind = landed and "ClimbFinished" or "ClimbAbandoned",
                PointId = pointId, EnemyId = climb.EnemyId}
        end
    end
    for _, contact in ipairs(contacts) do
        local pointId = contact.PointId
        local window = barricade.ById[pointId]
        assert(window, 'UNKNOWN_WINDOW: ' .. tostring(pointId))
        assert(not seen[pointId], 'DUPLICATE_CONTACT: ' .. pointId)
        assert(type(contact.EnemyIds) == 'table', 'INVALID_CONTACT')
        seen[pointId] = true
        local profile = self:Config(pointId)
        local attackers = #contact.EnemyIds
        if attackers > profile.MaxAttackers then attackers = profile.MaxAttackers end
        if #window.Boards > 0 then
            if attackers > 0 and delta > 0 then
                local pending = (self.Pending[pointId] or 0)
                    + profile.DamagePerSecond * attackers * delta
                local whole = math.floor(pending)
                self.Pending[pointId] = pending - whole
                if whole > 0 then
                    local hit, reason = barricade:Damage(pointId, whole, now)
                    if not hit then
                        events[#events + 1] = {Kind = 'Rejected', PointId = pointId, Reason = reason}
                    else
                        events[#events + 1] = {Kind = 'BoardDamaged', PointId = pointId,
                            By = attackers, Boards = hit.Boards, Destroyed = hit.Destroyed,
                            Passable = hit.Passable}
                    end
                end
            end
        else
            self.Pending[pointId] = nil
            if vault and not ended[pointId] and not self.Climbs[pointId] then
                for _, enemyId in ipairs(contact.EnemyIds) do
                    if vault.Ready(pointId, enemyId) then
                        local ok, interrupted = barricade:BeginClimb(pointId, enemyId)
                        if ok then
                            local started, reason = vault.Start(pointId, enemyId)
                            if started then
                                self.Climbs[pointId] = {EnemyId = enemyId,
                                    EndsAt = now + profile.ClimbSeconds}
                                events[#events + 1] = {Kind = "ClimbStarted", PointId = pointId,
                                    EnemyId = enemyId, Interrupted = interrupted}
                            else
                                barricade:EndClimb(pointId, enemyId)
                                events[#events + 1] = {Kind = "Rejected", PointId = pointId, Reason = reason}
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    return events
end

-- A dead climber must let go even while other enemies still stand at the window,
-- otherwise the window stays occupied by a corpse until they all leave.
function Assault:ReleaseEnemy(barricade, enemyId)
    assert(type(barricade) == 'table', 'MISSING_BARRICADE')
    local events = {}
    for pointId, climb in pairs(self.Climbs) do
        if climb.EnemyId == enemyId then
            self.Climbs[pointId] = nil
            if barricade.ById[pointId] then barricade:EndClimb(pointId, enemyId) end
            events[#events + 1] = {Kind = 'ClimbAbandoned', PointId = pointId, EnemyId = enemyId}
        end
    end
    return events
end

function Assault:InterruptAll()
    local count = 0
    for _ in pairs(self.Climbs) do count = count + 1 end
    self.Climbs, self.Pending = {}, {}
    return count
end

function Assault:Snapshot()
    local climbs = {}
    for pointId, climb in pairs(self.Climbs) do
        climbs[#climbs + 1] = {PointId = pointId, EnemyId = climb.EnemyId, EndsAt = climb.EndsAt}
    end
    table.sort(climbs, function(a, b) return a.PointId < b.PointId end)
    return {Climbs = climbs, Climbing = #climbs}
end

return Assault
