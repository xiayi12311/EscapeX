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

local function publishBoardInteraction(barricade, enabled)
    if not barricade then return end
    for _, window in ipairs(barricade.List) do
        local actor = window.Actor
        if KismetSystemLibrary.IsValid(actor) then
            local installer = enabled and window.Installer or nil
            local available = enabled and actor.Enabled == true and installer == nil and #window.Climbers == 0
                and #window.Boards < window.Config.BoardsPerWindow
            local old = actor.DefenseBoardInteractionState
            if not old or old.Available ~= available or old.Installer ~= installer then
                actor.DefenseBoardInteractionState = {Available = available, Installer = installer}
            end
        end
    end
end

local function stopWindowCombat(run)
    if not run.Barricade or run.WindowCombatStopped then return end
    run.WindowCombatStopped = true
    run.Barricade.Assault:InterruptAll()
    for _, window in ipairs(run.Barricade.List) do window.Climbers = {} end
    for _, actor in pairs(run.Actors) do
        Engine.StopVault(actor, false)
        Engine.StopBoardAttack(actor, true)
    end
    publishBoardInteraction(run.Barricade, true)
end

-- One explicit lifecycle per context/encounter; no automatic BeginPlay or timer.
function Service.New(context, catalog)
    Engine.ValidateContext(context)
    assert(type(catalog) == 'table', 'INVALID_CATALOG')
    if active[context] then return nil, 'CONTEXT_ALREADY_REGISTERED' end
    local registry, errors = WorldPoints.Collect(context, catalog)
    if not registry then return nil, errors end
    local self = setmetatable({Context = context, Catalog = catalog, Registry = registry,
        Barricades = {}, Runs = {}, UsedInstances = {}, Closed = false}, Service)
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
    if mode.Load then
        local config, reason = mode.Load()
        if not config then return false, reason end
        mode = config
    end
    -- Session copies and validates all wave/difficulty numbers before any engine spawn.
    local ok, session = pcall(Session.New, mode, instanceId, playerCount)
    if not ok then
        local reason = tostring(session):gsub('^.-:%d+:%s*', '')
        return false, reason
    end
    local plans, errorCode = Engine.Prepare(self.Context,
        self.Registry:GetPoints(encounterId, 'Spawn'), self.Catalog)
    if not plans then return false, errorCode end
    local barricade, boardError = self:_barricade(encounterId)
    if boardError then return false, boardError end
    local assault, assaultError = self:_buildAssault(barricade)
    if assaultError then return false, assaultError end
    local boardAttack
    if barricade then
        boardAttack, assaultError = Engine.PrepareBoardAttack(self.Catalog.BoardAttackSkill)
        if not boardAttack then return false, assaultError end
    end
    local windows = self.Registry:GetPoints(encounterId, "Window")
    local placement = self.Catalog.Enemies.NormalZombie and self.Catalog.Enemies.NormalZombie.Placement
    local vaults, vaultError = Engine.PrepareVaults(windows, placement)
    if not vaults then return false, vaultError end
    local targeting
    local targetConfig = self.Catalog.Targeting and self.Catalog.Targeting[encounterId]
    if targetConfig then
        local targetError
        targeting, targetError = Engine.PrepareTargeting(windows, targetConfig, self.Catalog.WindowQueue)
        if not targeting then return false, targetError end
        for _, window in ipairs(windows) do
            if not vaults[window.PointId] then return false, 'MISSING_WINDOW_VAULT: ' .. window.PointId end
            if targeting.WindowStopRadius > vaults[window.PointId].StartRadius then
                return false, 'WINDOW_STOP_OUTSIDE_VAULT_RADIUS: ' .. window.PointId
            end
        end
    end
    session:Start(now)
    if barricade then barricade.Assault = assault end
    self.Runs[encounterId] = {Session = session, Plans = plans, Deaths = {}, Actors = {},
        Cursor = 0, Error = nil, StartPoint = start, Deferred = {}, RetryAt = 0,
        Barricade = barricade, BoardAttack = boardAttack, Vaults = vaults, Targeting = targeting}
    publishBoardInteraction(barricade, true)
    encounterOwners[start] = self
    self.UsedInstances[instanceId] = true
    return true
end

-- Installed and pending boards belong to the world, so starting waves reuses them.
function Service:_barricade(encounterId)
    if self.Barricades[encounterId] then return self.Barricades[encounterId] end
    local windows = self.Registry:GetPoints(encounterId, 'Window') or {}
    if #windows == 0 then return nil end
    local Barricade = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBarricade')
    local entries = {}
    for _, actor in ipairs(windows) do
        entries[#entries + 1] = {PointId = actor.PointId, Actor = actor, Config = {
            BoardsPerWindow = actor.BoardsPerWindow, BoardDurability = actor.BoardDurability,
            PreinstalledBoards = actor.PreinstalledBoards,
            InstallSeconds = actor.InstallSeconds, InstallRange = actor.InstallRange, ClimbCapacity = 1,
        }}
    end
    local ok, built = pcall(Barricade.New, entries)
    if not ok then return nil, 'INVALID_BARRICADE_CONFIG' end
    for _, window in ipairs(built.List) do
        publishBoardSlots(window, table.concat(window.VisualSlots, ','))
    end
    self.Barricades[encounterId] = built
    return built
end

function Service:_buildAssault(barricade)
    if not barricade then return nil end
    local Assault = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseZombieAssault')
    local config = self.Catalog.BoardAssault
    if type(config) ~= 'table' then return nil, 'MISSING_BOARD_ASSAULT_CONFIG' end
    local assaultConfigs = {}
    for _, window in ipairs(barricade.List) do
        assaultConfigs[window.PointId] = config
    end
    local ok, assault = pcall(Assault.New, assaultConfigs)
    if not ok then return nil, 'INVALID_ASSAULT_CONFIG' end
    return assault
end

function Service:PrepareBoards()
    self:_check()
    for encounterId in pairs(self.Registry.Groups) do
        local _, reason = self:_barricade(encounterId)
        if reason then return false, reason end
    end
    for _, barricade in pairs(self.Barricades) do publishBoardInteraction(barricade, true) end
    return true
end

function Service:_validateBoardInstalls(encounterId)
    local barricade = self.Barricades[encounterId]
    if not barricade or not next(barricade.Installer) then return end
    local changed = false
    for _, window in ipairs(barricade.List) do
        local key = window.Installer
        if key and not Engine.InstallEligible(self.Context, key, window.Actor, window.Config.InstallRange) then
            barricade:ReleasePlayer(key)
            changed = true
        end
    end
    if changed then publishBoardInteraction(barricade, true) end
end

function Service:TickBoardInstalls()
    self:_check()
    for encounterId in pairs(self.Barricades) do self:_validateBoardInstalls(encounterId) end
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
    self:_validateBoardInstalls(encounterId)
    run.BoardEvents, run.PendingBoardEvents = run.PendingBoardEvents, nil
    local session = run.Session
    local state = session:Snapshot().State
    if state ~= 'Succeeded' and state ~= 'Failed' then
        if not run.Error then
            local valid, reason = self.Registry:ValidateForStart(encounterId)
            if not valid then run.Error = reason end
        end
        -- Adapter faults freeze progression, but never mask authoritative team failure.
        if run.Error and not teamFailed then
            stopWindowCombat(run)
            return self:Snapshot(encounterId), run.Error
        end
    end
    local dying = {}
    for _, death in ipairs(run.Deaths) do dying[death.EnemyId] = true end
    local running = not run.WindowCombatStopped and not teamFailed and state ~= 'Succeeded' and state ~= 'Failed'
    if running and run.Targeting and next(run.Actors) then
        local ok, reason = Engine.UpdateTargeting(run.Targeting, run.Actors, dying, now, run.Barricade, run.Vaults)
        if not ok then
            run.Error = reason
            stopWindowCombat(run)
            return self:Snapshot(encounterId), reason
        end
    end
    if run.Barricade and running then
        -- The zombie side reads the same board state: contacts are measured by
        -- the adapter against each window's own attack range, and damage/climb
        -- then go through the barricade object, so there is still exactly one
        -- owner of "how many boards are left". Enemies already queued as dead in
        -- this frame are excluded: their death is consumed below, and a corpse
        -- must not land one last board hit.
        local contacts, contactError = Engine.CollectBoardContacts(run.Barricade, run.Actors,
            run.Barricade.Assault, dying, run.Targeting)
        if not contacts then
            run.Error = contactError
            stopWindowCombat(run)
            return self:Snapshot(encounterId), contactError
        end
        run.AssaultEvents = run.Barricade.Assault:Advance(run.Barricade, contacts, now, {
            IsAttacking = function(enemyId)
                return Engine.IsBoardAttackActive(run.Actors[enemyId])
            end,
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
        for _, event in ipairs(run.AssaultEvents) do
            if event.Kind == 'BoardSwing' then
                local window = run.Barricade.ById[event.PointId].Actor
                local ok, reason = Engine.StartBoardAttack(run.Actors[event.EnemyId], window, run.BoardAttack)
                if not ok then
                    run.Barricade.Assault:CancelSwing(event.EnemyId)
                    event.Kind, event.Reason = 'Rejected', reason
                end
            elseif event.Kind == 'BoardSwingInterrupted' then
                Engine.StopBoardAttack(run.Actors[event.EnemyId], false)
            end
        end
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
        stopWindowCombat(run)
        for _, actor in pairs(run.Actors) do Engine.Release(actor) end
        return self:Snapshot(encounterId)
    end
    if session.Error then
        stopWindowCombat(run)
        return self:Snapshot(encounterId), session.Error
    end
    local requests, spawnError = {}, nil
    if #run.Deferred == 0 then requests, spawnError = session:ClaimSpawns(now) end
    if not requests then
        stopWindowCombat(run)
        return self:Snapshot(encounterId), spawnError
    end
    for _, request in ipairs(requests) do run.Deferred[#run.Deferred+1] = request end
    if #run.Deferred > 0 and now >= run.RetryAt then
        local deferred = {}
        for _, request in ipairs(run.Deferred) do
            local ok, errorCode = self:_spawn(run, request)
            if not ok then
                if errorCode ~= 'SPAWN_SPACE_OCCUPIED' then
                    stopWindowCombat(run)
                    return self:Snapshot(encounterId), errorCode
                end
                deferred[#deferred+1] = request
            end
        end
        run.Deferred = deferred
        run.RetryAt = now + session.Config.Waves[session.WaveIndex].IntervalSeconds
            * session.Config.Difficulties[session.PlayerCount].IntervalMultiplier
    end
    publishBoardInteraction(run.Barricade, true)
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
function Service:InstallBoard(encounterId, pointId, playerKey, requestedActor)
    self:_check()
    local barricade = self.Barricades[encounterId]
    if not barricade then return false, 'NO_WINDOWS_IN_ENCOUNTER' end
    local window = barricade.ById[pointId]
    if not window or (requestedActor and requestedActor ~= window.Actor) then return false, 'UNKNOWN_WINDOW' end
    local pawn = Engine.InstallEligible(self.Context, playerKey, window.Actor, barricade:Range(pointId))
    if not pawn then return false, 'INSTALLER_INELIGIBLE' end
    if UGCBackPackSystem.GetItemCount(pawn, self.Catalog.BoardItemId) < 1 then
        return false, 'BOARD_ITEM_REQUIRED'
    end
    for _, other in pairs(self.Barricades) do
        if other ~= barricade and other.Installer[playerKey] then return false, 'ALREADY_INSTALLING' end
    end
    local ok, reason = barricade:TryInstall(pointId, playerKey)
    if ok then publishBoardInteraction(barricade, true) end
    return ok, reason
end

function Service:CompleteBoard(encounterId, pointId, playerKey, requestedActor)
    self:_check()
    local barricade = self.Barricades[encounterId]
    local window = barricade and barricade.ById[pointId]
    if not window or (requestedActor and requestedActor ~= window.Actor) then return false, 'UNKNOWN_WINDOW' end
    if window.Installer == nil or window.Installer ~= playerKey then return false, 'NOT_INSTALLING' end
    local pawn = Engine.InstallEligible(self.Context, playerKey, window.Actor, window.Config.InstallRange)
    if not pawn then
        self:BoardPlayerLeft(encounterId, playerKey)
        return false, 'INSTALLER_INELIGIBLE'
    end
    local ok, result = barricade:CompleteInstall(pointId, playerKey, function()
        local itemId = self.Catalog.BoardItemId
        if pawn.EscapeXGMFreeSupplies then return UGCBackPackSystem.GetItemCount(pawn, itemId) > 0 end
        for _, item in pairs(UGCBackPackSystem.GetAllItemData(pawn)) do
            if item.ItemID == itemId and item.Count > 0 then
                return UGCBackPackSystem.DropItemByInstanceID(pawn, item.InstanceID, 1, true)
            end
        end
        return false
    end)
    if ok then
        publishBoardSlots(window, table.concat(window.VisualSlots, ','))
        local run = self.Runs[encounterId]
        if run and not run.WindowCombatStopped then
            run.PendingBoardEvents = run.PendingBoardEvents or {}
            run.PendingBoardEvents[#run.PendingBoardEvents + 1] = {
                Kind = 'Installed', PointId = pointId, PlayerKey = playerKey, Boards = result,
            }
        end
    end
    publishBoardInteraction(barricade, true)
    return ok, result
end

function Service:CancelBoard(encounterId, playerKey)
    self:_check()
    if not self.Barricades[encounterId] then return false, 'NO_WINDOWS_IN_ENCOUNTER' end
    local pointId = self:BoardPlayerLeft(encounterId, playerKey)
    if not pointId then return false, 'NOT_INSTALLING' end
    return true, pointId
end

-- Called by the authoritative death hook so a dead installer cannot finish a
-- board from the corpse position on the next tick.
function Service:BoardPlayerLeft(encounterId, playerKey)
    local barricade = self.Barricades[encounterId]
    if not barricade then return nil end
    local pointId = barricade:ReleasePlayer(playerKey)
    if pointId then publishBoardInteraction(barricade, true) end
    return pointId
end

function Service:ReleaseBoardPlayer(playerKey)
    for encounterId in pairs(self.Barricades) do
        local pointId = self:BoardPlayerLeft(encounterId, playerKey)
        if pointId then return pointId end
    end
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
        publishBoardInteraction(run.Barricade, true)
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
    local ok, result = run.Barricade:BeginClimb(pointId, enemyId)
    if ok then publishBoardInteraction(run.Barricade, true) end
    return ok, result
end

function Service:EndClimb(encounterId, pointId, enemyId)
    local run = self.Runs[encounterId]
    if not run or not run.Barricade then return false, 'NO_WINDOWS_IN_ENCOUNTER' end
    local ok, reason = run.Barricade:EndClimb(pointId, enemyId)
    if ok then publishBoardInteraction(run.Barricade, true) end
    return ok, reason
end

function Service:Board(encounterId, pointId)
    local barricade = self.Barricades[encounterId]
    if not barricade then return nil, 'NO_WINDOWS_IN_ENCOUNTER' end
    return barricade:Snapshot(pointId)
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
    stopWindowCombat(run)
    return true
end

function Service:Shutdown(resetForGM)
    if self.Closed then return end
    self.Closed = true
    for _, run in pairs(self.Runs) do
        stopWindowCombat(run)
        for _, actor in pairs(run.Actors) do
            Engine.Release(actor)
            if resetForGM and KismetSystemLibrary.IsValid(actor) then actor:K2_DestroyActor() end
        end
        encounterOwners[run.StartPoint] = nil
        if resetForGM and KismetSystemLibrary.IsValid(run.StartPoint) then
            run.StartPoint.DefenseStarted = false
            run.StartPoint.DefenseStatusText = ''
        end
    end
    for _, barricade in pairs(self.Barricades) do
        barricade:InterruptAll()
        for _, window in ipairs(barricade.List) do publishBoardSlots(window, '') end
        publishBoardInteraction(barricade, false)
    end
    active[self.Context] = nil
end

return Service
