local Session = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseSession')
local WorldPoints = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local Engine = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseEngineAdapter')
local Service = {}
Service.__index = Service
local active = setmetatable({}, {__mode = 'k'})
local encounterOwners = setmetatable({}, {__mode = 'k'})

-- One explicit lifecycle per context/encounter; no automatic BeginPlay or timer.
function Service.New(context, catalog)
    Engine.ValidateContext(context)
    assert(type(catalog) == 'table', 'INVALID_CATALOG')
    if active[context] then return nil, 'CONTEXT_ALREADY_REGISTERED' end
    local registry, errors = WorldPoints.Collect(context, catalog)
    if not registry then return nil, errors end
    local self = setmetatable({Context = context, Catalog = catalog, Registry = registry,
        Runs = {}, UsedInstances = {}, Closed = false}, Service)
    active[context] = self
    return self
end

function Service:_check()
    assert(not self.Closed, 'SERVICE_CLOSED')
    Engine.ValidateContext(self.Context)
end

function Service:Start(encounterId, instanceId, playerCount, now)
    self:_check()
    if self.Runs[encounterId] then return false, 'ENCOUNTER_ALREADY_STARTED' end
    if self.UsedInstances[instanceId] then return false, 'INSTANCE_ALREADY_USED' end
    local valid, reason = self.Registry:ValidateForStart(encounterId)
    if not valid then return false, reason end
    local start = self.Registry:GetPoints(encounterId, 'Start')[1]
    if encounterOwners[start] then return false, 'ENCOUNTER_ALREADY_OWNED' end
    local mode = self.Catalog.Modes[start.ModeConfigId]
    if not mode then return false, 'MODE_CONFIG_REMOVED' end
    -- Session copies and validates all wave/difficulty numbers before any engine spawn.
    local session = Session.New(mode, instanceId, playerCount)
    local plans, errorCode = Engine.Prepare(self.Context,
        self.Registry:GetPoints(encounterId, 'Spawn'), self.Catalog)
    if not plans then return false, errorCode end
    session:Start(now)
    self.Runs[encounterId] = {Session = session, Plans = plans, Deaths = {}, Actors = {},
        Cursor = 0, Error = nil, StartPoint = start}
    encounterOwners[start] = self
    self.UsedInstances[instanceId] = true
    return true
end

function Service:_spawn(run, request)
    run.Cursor = run.Cursor % #run.Plans + 1
    local enemyId = request.InstanceId .. ':' .. request.Token
    local actor, reason = Engine.Spawn(self.Context, run.Plans[run.Cursor], function(dead)
        if not self.Closed then
            run.Deaths[#run.Deaths + 1] = {InstanceId = request.InstanceId,
                WaveIndex = request.WaveIndex, EnemyId = enemyId}
        end
    end)
    if not actor then
        run.Session:ReportSpawnFailure(request.InstanceId, request.WaveIndex,
            request.Token, reason)
        return false, reason
    end
    local ok, confirmError = run.Session:ConfirmSpawn(request.InstanceId,
        request.WaveIndex, request.Token, enemyId)
    if not ok then
        Engine.Release(actor)
        run.Error = 'SPAWN_CONFIRM_FAILED: ' .. confirmError
        return false, run.Error
    end
    run.Actors[enemyId] = actor
    return true
end

-- Caller must provide trusted server time AND the complete authoritative team result.
-- BPDie only queues events; victory is evaluated here, never inside the callback.
function Service:Step(encounterId, now, teamFailed)
    self:_check()
    assert(type(teamFailed) == 'boolean', 'INVALID_TEAM_STATE')
    local run = self.Runs[encounterId]
    if not run then return nil, 'ENCOUNTER_NOT_STARTED' end
    local session = run.Session
    local state = session:Snapshot().State
    if state ~= 'Succeeded' and state ~= 'Failed' then
        if not run.Error then
            local valid, reason = self.Registry:ValidateForStart(encounterId)
            if not valid then run.Error = reason end
        end
        -- Adapter faults freeze progression, but never mask authoritative team failure.
        if run.Error and not teamFailed then
            return self:Snapshot(encounterId), run.Error
        end
    end
    local accepted = session:ResolveFrame(now, run.Deaths, teamFailed)
    run.Deaths = {}
    for _, enemyId in ipairs(accepted) do
        Engine.Release(run.Actors[enemyId])
        run.Actors[enemyId] = nil
    end
    state = session:Snapshot().State
    if state == 'Succeeded' or state == 'Failed' then
        for _, actor in pairs(run.Actors) do Engine.Release(actor) end
        return self:Snapshot(encounterId)
    end
    local requests, spawnError = session:ClaimSpawns(now)
    if not requests then return self:Snapshot(encounterId), spawnError end
    for _, request in ipairs(requests) do
        local ok, errorCode = self:_spawn(run, request)
        if not ok then return self:Snapshot(encounterId), errorCode end
    end
    return self:Snapshot(encounterId)
end

function Service:Snapshot(encounterId)
    local run = self.Runs[encounterId]
    if not run then return nil, 'ENCOUNTER_NOT_STARTED' end
    local snapshot = run.Session:Snapshot()
    snapshot.AdapterError = run.Error
    return snapshot
end

function Service:Shutdown()
    if self.Closed then return end
    for _, run in pairs(self.Runs) do
        for _, actor in pairs(run.Actors) do Engine.Release(actor) end
        encounterOwners[run.StartPoint] = nil
    end
    self.Closed = true
    active[self.Context] = nil
    -- No kill/destroy: shutdown is not a combat death or a victory condition.
end

return Service
