local Session = {}
Session.__index = Session

local function number(value, name, minimum, integer)
    assert(type(value) == 'number' and value == value and value < math.huge
        and value >= minimum and (not integer or value == math.floor(value)), name)
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

function Session.New(config, instanceId, playerCount)
    assert(type(instanceId) == 'string' and instanceId ~= '', 'INVALID_INSTANCE')
    number(playerCount, 'INVALID_PLAYER_COUNT', 1, true)
    assert(playerCount <= 4, 'INVALID_PLAYER_COUNT')
    assert(type(config) == 'table' and type(config.Version) == 'string', 'INVALID_CONFIG')
    number(config.PreparationSeconds, 'INVALID_PREPARATION', 0)
    assert(type(config.Waves) == 'table' and #config.Waves > 0, 'INVALID_WAVES')
    local waveCount = 0
    for index in pairs(config.Waves) do
        number(index, 'INVALID_WAVE_INDEX', 1, true)
        waveCount = waveCount + 1
    end
    assert(waveCount == #config.Waves, 'NONCONTIGUOUS_WAVES')
    for index, wave in ipairs(config.Waves) do
        number(wave.Count, 'INVALID_COUNT', 1, true)
        number(wave.BatchSize, 'INVALID_BATCH', 1, true)
        number(wave.IntervalSeconds, 'INVALID_INTERVAL', 0)
        assert(wave.IntervalSeconds > 0, 'INVALID_INTERVAL')
        number(wave.RestSeconds, 'INVALID_REST', 0)
        assert(index ~= #config.Waves or wave.RestSeconds == 0, 'FINAL_WAVE_REST')
    end
    assert(type(config.Difficulties) == 'table', 'INVALID_DIFFICULTIES')
    for count = 1, 4 do
        local difficulty = config.Difficulties[count]
        assert(type(difficulty) == 'table', 'MISSING_DIFFICULTY')
        number(difficulty.CountMultiplier, 'INVALID_MULTIPLIER', 0)
        number(difficulty.IntervalMultiplier, 'INVALID_INTERVAL_MULTIPLIER', 0)
        assert(difficulty.CountMultiplier > 0 and difficulty.IntervalMultiplier > 0,
            'INVALID_MULTIPLIER')
        number(difficulty.AliveLimit, 'INVALID_LIMIT', 1, true)
    end
    return setmetatable({Config = copy(config), InstanceId = instanceId,
        PlayerCount = playerCount, State = 'Idle',
        WaveIndex = 0, Serial = 0, Pending = {}, Alive = {}, SeenEnemies = {},
        PendingCount = 0, AliveCount = 0, Generated = 0, Total = 0}, Session)
end

function Session:_time(now)
    number(now, 'INVALID_TIME', 0)
    assert(not self.LastTime or now >= self.LastTime, 'TIME_REVERSED')
    self.LastTime = now
end

function Session:Start(now)
    self:_time(now)
    if self.State ~= 'Idle' then return false, 'ALREADY_STARTED' end
    self.State = 'Preparing'
    self.StartedAt = now
    self.ReadyAt = now + self.Config.PreparationSeconds
    return true
end

function Session:_openWave(now)
    self.WaveIndex = self.WaveIndex + 1
    local wave = self.Config.Waves[self.WaveIndex]
    local difficulty = self.Config.Difficulties[self.PlayerCount]
    self.Total = math.ceil(wave.Count * difficulty.CountMultiplier)
    self.Generated = 0
    self.NextBatchAt = now
    self.State = 'Fighting'
end

function Session:Tick(now)
    self:_time(now)
    if (self.State == 'Preparing' or self.State == 'Resting') and now >= self.ReadyAt then
        self:_openWave(now)
    end
end

function Session:ClaimSpawns(now)
    self:Tick(now)
    if self.State ~= 'Fighting' then return {} end
    if self.Error then return nil, self.Error end
    if now < self.NextBatchAt then return {} end
    local wave = self.Config.Waves[self.WaveIndex]
    local difficulty = self.Config.Difficulties[self.PlayerCount]
    local count = math.min(wave.BatchSize, self.Total - self.Generated - self.PendingCount,
        difficulty.AliveLimit - self.AliveCount - self.PendingCount)
    self.NextBatchAt = now + wave.IntervalSeconds * difficulty.IntervalMultiplier
    local requests = {}
    for _ = 1, count do
        self.Serial = self.Serial + 1
        local token = self.Serial
        self.Pending[token] = true
        self.PendingCount = self.PendingCount + 1
        requests[#requests + 1] = {InstanceId = self.InstanceId, WaveIndex = self.WaveIndex,
            Token = token}
    end
    return requests
end

function Session:ConfirmSpawn(instanceId, waveIndex, token, enemyId)
    if self.State ~= 'Fighting' or instanceId ~= self.InstanceId
        or waveIndex ~= self.WaveIndex or not self.Pending[token] then
        return false, 'STALE_SPAWN'
    end
    if type(enemyId) ~= 'string' or enemyId == '' or self.SeenEnemies[enemyId] then
        return false, 'INVALID_ENEMY_ID'
    end
    self.Pending[token] = nil
    self.PendingCount = self.PendingCount - 1
    self.Generated = self.Generated + 1
    self.Alive[enemyId] = true
    self.SeenEnemies[enemyId] = true
    self.AliveCount = self.AliveCount + 1
    return true
end

function Session:ReportSpawnFailure(instanceId, waveIndex, token, reason)
    if instanceId ~= self.InstanceId or waveIndex ~= self.WaveIndex
        or not self.Pending[token] or self.State ~= 'Fighting' then
        return false, 'STALE_SPAWN'
    end
    assert(type(reason) == 'string' and reason ~= '', 'MISSING_REASON')
    self.Error = 'SPAWN_FAILED: ' .. reason
    return true
end

-- Submit the authoritative team state before checking the same frame's final kill.
function Session:ResolveFrame(now, deaths, teamFailed)
    self:_time(now)
    assert(type(deaths) == 'table', 'INVALID_DEATHS')
    assert(type(teamFailed) == 'boolean', 'INVALID_TEAM_STATE')
    if self.State ~= 'Fighting' and self.State ~= 'Preparing' and self.State ~= 'Resting' then
        return {}, 'NOT_ACTIVE'
    end
    if teamFailed then
        self.State = 'Failed'
        self.ResultReason = 'TEAM_FAILED'
        self.EndedAt = now
        return {}
    end
    if self.State ~= 'Fighting' then return {} end
    local accepted = {}
    for _, event in ipairs(deaths) do
        if event.InstanceId == self.InstanceId and event.WaveIndex == self.WaveIndex
            and self.Alive[event.EnemyId] then
            self.Alive[event.EnemyId] = nil
            self.AliveCount = self.AliveCount - 1
            accepted[#accepted + 1] = event.EnemyId
        end
    end
    if not self.Error and self.Generated == self.Total and self.PendingCount == 0
        and self.AliveCount == 0 then
        if self.WaveIndex == #self.Config.Waves then
            self.State = 'Succeeded'
            self.EndedAt = now
        else
            self.State = 'Resting'
            self.ReadyAt = now + self.Config.Waves[self.WaveIndex].RestSeconds
        end
    end
    return accepted
end

function Session:Snapshot()
    return {InstanceId = self.InstanceId, Version = self.Config.Version,
        State = self.State, WaveIndex = self.WaveIndex,
        WaveCount = #self.Config.Waves, Total = self.Total, Generated = self.Generated,
        RemainingToGenerate = self.Total - self.Generated,
        PendingCount = self.PendingCount, AliveCount = self.AliveCount,
        StartedAt = self.StartedAt, ReadyAt = self.ReadyAt, EndedAt = self.EndedAt,
        Error = self.Error, ResultReason = self.ResultReason}
end

return Session
