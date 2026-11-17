local Session = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseSession')
local WorldPoints = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local Engine = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseEngineAdapter')
local Service = {}
Service.__index = Service
local active = setmetatable({}, {__mode = 'k'})
local encounterOwners = setmetatable({}, {__mode = 'k'})

local function publishBoardSlots(window, slots)
    local actor = window.Actor
    if KismetSystemLibrary.IsValid(actor) and actor.DefenseBoardSlots ~= slots then
        actor:SetDefenseBoardSlots(slots)
    end
end

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
    local barricade, boardError = self:_barricade(encounterId)
    if boardError then return false, boardError end
    local windows = self.Registry:GetPoints(encounterId, "Window")
    local vaults, vaultError = Engine.PrepareVaults(windows, self.Catalog.Vaults and self.Catalog.Vaults[encounterId])
    if not vaults then return false, vaultError end
    local targeting
    local targetConfig = self.Catalog.Targeting and self.Catalog.Targeting[encounterId]
    if targetConfig then
        local targetError
        targeting, targetError = Engine.PrepareTargeting(windows, targetConfig)
        if not targeting then return false, targetError end
        for _, window in ipairs(windows) do
            if not vaults[window.PointId] then return false, 'MISSING_WINDOW_VAULT: ' .. window.PointId end
            if targeting.WindowStopRadius > vaults[window.PointId].StartRadius then
                return false, 'WINDOW_STOP_OUTSIDE_VAULT_RADIUS: ' .. window.PointId
            end
        end
    end
    session:Start(now)
    self.Runs[encounterId] = {Session = session, Plans = plans, Deaths = {}, Actors = {},
        Cursor = 0, Error = nil, StartPoint = start, Deferred = {}, RetryAt = 0,
        Barricade = barricade, Vaults = vaults, Targeting = targeting}
    encounterOwners[start] = self
    self.UsedInstances[instanceId] = true
    return true
end

-- Boards are built from the same validated registry as spawns, so a window that
-- fails config validation stops the start instead of becoming an open hole. The
-- zombie-side assault profile is resolved here too: a window whose assault
-- profile vanished must fail loudly rather than silently become invulnerable.
function Service:_barricade(encounterId)
    local windows = self.Registry:GetPoints(encounterId, 'Window') or {}
    if #windows == 0 then return nil end
    local Barricade = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBarricade')
    local Assault = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseZombieAssault')
    local entries, assaultConfigs = {}, {}
    for _, actor in ipairs(windows) do
        local config = self.Catalog.Barricades[actor.BarricadeConfigId]
        if type(config) ~= 'table' then
            return nil, 'BARRICADE_CONFIG_REMOVED: ' .. tostring(actor.BarricadeConfigId)
        end
        local assaultConfig
        if config.AssaultConfigId and type(self.Catalog.Assaults) == 'table' then
            assaultConfig = self.Catalog.Assaults[config.AssaultConfigId]
        end
        if type(assaultConfig) ~= 'table' then
            return nil, 'ASSAULT_CONFIG_REMOVED: ' .. tostring(config.AssaultConfigId)
        end
        entries[#entries + 1] = {PointId = actor.PointId, Actor = actor, Config = config}
        assaultConfigs[actor.PointId] = assaultConfig
    end
    local ok, built = pcall(Barricade.New, entries)
    if not ok then return nil, 'INVALID_BARRICADE_CONFIG' end
    local assault
    ok, assault = pcall(Assault.New, assaultConfigs)
    if not ok then return nil, 'INVALID_ASSAULT_CONFIG' end
    built.Assault = assault
    return built
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
        if reason == 'SPAWN_SPACE_OCCUPIED' then return false, reason end
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
function Service:Step(encounterId, now, teamFailed, deferVictory)
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
    local dying = {}
    for _, death in ipairs(run.Deaths) do dying[death.EnemyId] = true end
    local running = not teamFailed and state ~= 'Succeeded' and state ~= 'Failed'
    if running and run.Targeting and next(run.Actors) then
        local ok, reason = Engine.UpdateTargeting(run.Targeting, run.Actors, dying, now)
        if not ok then
            run.Error = reason
            return self:Snapshot(encounterId), reason
        end
    end
    -- Boards keep progressing independently of the wave clock, but a finished
    -- encounter grants nothing: installers are simply dropped with the run.
    if run.Barricade and running then
        -- The zombie side reads the same board state: contacts are measured by
        -- the adapter against each window's own attack range, and damage/climb
        -- then go through the barricade object, so there is still exactly one
        -- owner of "how many boards are left". Enemies already queued as dead in
        -- this frame are excluded: their death is consumed below, and a corpse
        -- must not land one last board hit.
        local contacts, contactError = Engine.CollectBoardContacts(run.Barricade, run.Actors,
            run.Barricade.Assault, dying, run.Targeting ~= nil)
        if not contacts then
            run.Error = contactError
            return self:Snapshot(encounterId), contactError
        end
        run.BoardEvents = run.Barricade:Advance(now, function(key, pointId, actor)
            return Engine.InstallEligible(self.Context, key, actor,
                run.Barricade:Range(pointId))
        end)
        run.AssaultEvents = run.Barricade.Assault:Advance(run.Barricade, contacts, now, {
            Ready = function(pointId, enemyId)
                return Engine.VaultReady(run.Actors[enemyId], run.Vaults[pointId])
            end,
            Start = function(pointId, enemyId)
                return Engine.StartVault(run.Actors[enemyId], run.Vaults[pointId])
            end,
            Status = function(pointId, enemyId)
                if dying[enemyId] then return "Interrupted" end
                return Engine.VaultStatus(run.Actors[enemyId], run.Vaults[pointId])
            end,
            Stop = function(enemyId, landed)
                Engine.StopVault(run.Actors[enemyId], landed)
            end,
        })
        for _, window in ipairs(run.Barricade.List) do
            publishBoardSlots(window, table.concat(window.VisualSlots, ','))
        end
    end
    local accepted = session:ResolveFrame(now, run.Deaths, teamFailed, deferVictory)
    run.Deaths = {}
    for _, enemyId in ipairs(accepted) do
        -- A climber that died releases the window immediately, otherwise the
        -- occupancy would linger until the next contact sweep.
        if run.Barricade then
            run.Barricade.Assault:ReleaseEnemy(run.Barricade, enemyId)
        end
        Engine.Release(run.Actors[enemyId])
        run.Actors[enemyId] = nil
    end
    state = session:Snapshot().State
    if state == 'Succeeded' or state == 'Failed' then
        -- Unfinished boards die with the result; the encounter never hands out
        -- a board that the player earned after the round was already decided.
        if run.Barricade then
            run.Barricade:InterruptAll()
            run.Barricade.Assault:InterruptAll()
        end
        for _, actor in pairs(run.Actors) do Engine.Release(actor) end
        return self:Snapshot(encounterId)
    end
    if session.Error then return self:Snapshot(encounterId), session.Error end
    local requests, spawnError = {}, nil
    if #run.Deferred == 0 then requests, spawnError = session:ClaimSpawns(now) end
    if not requests then return self:Snapshot(encounterId), spawnError end
    for _, request in ipairs(requests) do run.Deferred[#run.Deferred+1] = request end
    if #run.Deferred > 0 and now >= run.RetryAt then
        local deferred = {}
        for _, request in ipairs(run.Deferred) do
            local ok, errorCode = self:_spawn(run, request)
            if not ok then
                if errorCode ~= 'SPAWN_SPACE_OCCUPIED' then return self:Snapshot(encounterId), errorCode end
                deferred[#deferred+1] = request
            end
        end
        run.Deferred = deferred
        run.RetryAt = now + session.Config.Waves[session.WaveIndex].IntervalSeconds
            * session.Config.Difficulties[session.PlayerCount].IntervalMultiplier
    end
    return self:Snapshot(encounterId)
end

function Service:Snapshot(encounterId)
    local run = self.Runs[encounterId]
    if not run then return nil, 'ENCOUNTER_NOT_STARTED' end
    local snapshot = run.Session:Snapshot()
    snapshot.AdapterError = run.Error
    if run.Barricade then
        local boards = run.Barricade:Summary()
        snapshot.Boards = boards.Boards
        snapshot.BoardCapacity = boards.Capacity
        snapshot.OpenWindows = boards.Open
        snapshot.InstallingWindows = boards.Installing
        snapshot.BoardEvents = run.BoardEvents
        snapshot.Climbers = run.Barricade.Assault:Snapshot().Climbing
        snapshot.AssaultEvents = run.AssaultEvents
    end
    return snapshot
end

-- Board requests are separate entry points, not extra parameters on Step, so the
-- wave/team contract cannot be bent by an interaction caller.
function Service:InstallBoard(encounterId, pointId, playerKey, now)
    self:_check()
    local run = self.Runs[encounterId]
    if not run then return false, 'ENCOUNTER_NOT_STARTED' end
    if not run.Barricade then return false, 'NO_WINDOWS_IN_ENCOUNTER' end
    local state = run.Session:Snapshot().State
    if state == 'Succeeded' or state == 'Failed' then return false, 'ENCOUNTER_ENDED' end
    -- The window must still be the registered one, and the player must be close
    -- enough at the moment of the request; completion re-checks both.
    local window = run.Barricade.ById[pointId]
    if not window then return false, 'UNKNOWN_WINDOW' end
    if not Engine.InstallEligible(self.Context, playerKey, window.Actor,
        run.Barricade:Range(pointId)) then
        return false, 'INSTALLER_INELIGIBLE'
    end
    return run.Barricade:TryInstall(pointId, playerKey, now)
end

function Service:CancelBoard(encounterId, playerKey)
    self:_check()
    local run = self.Runs[encounterId]
    if not run then return false, 'ENCOUNTER_NOT_STARTED' end
    if not run.Barricade then return false, 'NO_WINDOWS_IN_ENCOUNTER' end
    local pointId = run.Barricade:ReleasePlayer(playerKey)
    if not pointId then return false, 'NOT_INSTALLING' end
    return true, pointId
end

-- Called by the authoritative death hook so a dead installer cannot finish a
-- board from the corpse position on the next tick.
function Service:BoardPlayerLeft(encounterId, playerKey)
    local run = self.Runs[encounterId]
    if not run or not run.Barricade then return nil end
    return run.Barricade:ReleasePlayer(playerKey)
end

function Service:DamageBoard(encounterId, pointId, amount, now)
    self:_check()
    local run = self.Runs[encounterId]
    if not run then return nil, 'ENCOUNTER_NOT_STARTED' end
    if not run.Barricade then return nil, 'NO_WINDOWS_IN_ENCOUNTER' end
    local state = run.Session:Snapshot().State
    if state == 'Succeeded' or state == 'Failed' then return nil, 'ENCOUNTER_ENDED' end
    local hit, reason = run.Barricade:Damage(pointId, amount, now)
    if hit and hit.Destroyed > 0 then
        local window = run.Barricade.ById[pointId]
        publishBoardSlots(window, table.concat(window.VisualSlots, ','))
    end
    return hit, reason
end

-- Reserved zombie traversal entry; the AI side is not wired yet, so this is the
-- contract the behavior tree task will call rather than a claimed working climb.
function Service:BeginClimb(encounterId, pointId, enemyId)
    local run = self.Runs[encounterId]
    if not run then return false, 'ENCOUNTER_NOT_STARTED' end
    if not run.Barricade then return false, 'NO_WINDOWS_IN_ENCOUNTER' end
    local state = run.Session:Snapshot().State
    if state == 'Succeeded' or state == 'Failed' then return false, 'ENCOUNTER_ENDED' end
    return run.Barricade:BeginClimb(pointId, enemyId)
end

function Service:EndClimb(encounterId, pointId, enemyId)
    local run = self.Runs[encounterId]
    if not run or not run.Barricade then return false, 'NO_WINDOWS_IN_ENCOUNTER' end
    return run.Barricade:EndClimb(pointId, enemyId)
end

function Service:Board(encounterId, pointId)
    local run = self.Runs[encounterId]
    if not run or not run.Barricade then return nil, 'NO_WINDOWS_IN_ENCOUNTER' end
    return run.Barricade:Snapshot(pointId)
end

-- Freeze a running encounter with a named diagnostic. Used by the roster when reality
-- contradicts the approved rule (a player standing again inside an encounter that is
-- not allowed to revive). Freezing is deliberate: a silent roster rewrite would hide
-- the very engine path that must be switched off.
function Service:ReportError(encounterId, code)
    local run = self.Runs[encounterId]
    if not run or run.Error then return false end
    local state = run.Session:Snapshot().State
    if state == 'Succeeded' or state == 'Failed' then return false end
    run.Error = code
    return true
end

function Service:Shutdown()
    if self.Closed then return end
    for _, run in pairs(self.Runs) do
        if run.Barricade then
            run.Barricade:InterruptAll()
            run.Barricade.Assault:InterruptAll()
            for _, window in ipairs(run.Barricade.List) do publishBoardSlots(window, '') end
        end
        for _, actor in pairs(run.Actors) do Engine.Release(actor) end
        encounterOwners[run.StartPoint] = nil
    end
    self.Closed = true
    active[self.Context] = nil
    -- No kill/destroy: shutdown is not a combat death or a victory condition.
end

return Service
