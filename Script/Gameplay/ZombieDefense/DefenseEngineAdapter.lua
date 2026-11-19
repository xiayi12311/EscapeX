-- Engine boundary for combat, navigation and world contact.
local Adapter = {}
local bindings = setmetatable({}, {__mode = 'k'})
local Queue

local behaviorPauseReason = "ZombieDefenseNavigation"
local vaultInterruptReason = 1 -- EPESkillDeActivateReason.Interrupt
local pathSuccess = 3 -- ENavigationQueryResult.Success

local function boardAttackActive(binding)
    return binding.BoardAttack and binding.BoardAttack:IsActivating()
end

local function setBehaviorPaused(actor, binding, paused)
    if (binding.BehaviorPaused == true) == paused then return end
    binding.BehaviorPaused = paused
    if paused then
        UGCGenericCharacterSystem.PauseBehavior(actor, behaviorPauseReason)
    else
        UGCGenericCharacterSystem.ResumeBehavior(actor, behaviorPauseReason)
    end
end

local function validateVaultSite(window, point, name, profile, placement, geometry)
    local dx, dy = point.X - geometry.Origin.X, point.Y - geometry.Origin.Y
    if dx*dx + dy*dy < (geometry.GateExtent.X + placement.Radius)^2 then
        return 'WINDOW_' .. name .. '_TOO_CLOSE_TO_GATE: ' .. window.PointId
    end
    local radius = name == 'TAKEOFF' and profile.StartRadius or profile.LandingRadius
    local found, ground = UGCNavigationSystem.ProjectPointToNavigation(window, point,
        {X = radius, Y = radius, Z = profile.NavProjectionHeight})
    if not found or (ground.X-point.X)^2 + (ground.Y-point.Y)^2 > radius^2
        or math.abs(ground.Z-point.Z) > profile.NavProjectionHeight then
        return 'WINDOW_' .. name .. '_OFF_NAVIGATION: ' .. window.PointId
    end
    local tolerance = profile.FootTolerance
    local hits = {}
    KismetSystemLibrary.LineTraceMultiForObjects(window,
        {X = point.X, Y = point.Y, Z = point.Z+tolerance},
        {X = point.X, Y = point.Y, Z = point.Z-tolerance},
        {0}, false, {window}, 0, hits, true, {R=1,G=0,B=0,A=1}, {R=0,G=1,B=0,A=1}, 0)
    local floor = hits[1] and hits[1].ImpactPoint
    if not floor then return 'WINDOW_' .. name .. '_NO_FLOOR: ' .. window.PointId end
    local center = {X = point.X, Y = point.Y,
        Z = math.max(point.Z, floor.Z) + placement.HalfHeight + placement.GroundClearance}
    if KismetSystemLibrary.CapsuleOverlapActors(window, center, placement.Radius, placement.HalfHeight,
        {0}, nil, {window}, {}) then
        return 'WINDOW_' .. name .. '_BLOCKED: ' .. window.PointId
    end
end

function Adapter.PrepareVaults(windows, placement)
    local geometry = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWindowGeometry')
    local result = {}
    for _, window in ipairs(windows) do
        local points, reason = geometry.Build(window)
        if not points then return nil, reason end
        local class = window.VaultSkillClass
        if not class or not KismetSystemLibrary.IsValid(class) then
            return nil, 'VAULT_SKILL_UNAVAILABLE: ' .. window.PointId
        end
        local fault = validateVaultSite(window, points.Outside, 'TAKEOFF', window, placement, points)
            or validateVaultSite(window, points.Inside, 'LANDING', window, placement, points)
        if fault then return nil, fault end
        result[window.PointId] = {
            Class = class, Slot = 'Skill.Slot.Slot0', Window = window, StartRadius = window.StartRadius,
            LandingRadius = window.LandingRadius, FootTolerance = window.FootTolerance, Yaw = points.Rotation.Yaw,
        }
    end
    return result
end

local function nearAnchor(actor, anchor, radius, footTolerance)
    local position = actor:K2_GetActorLocation()
    local bottom = position.Z - actor.CapsuleComponent:GetScaledCapsuleHalfHeight()
    return (position.X-anchor.X)^2 + (position.Y-anchor.Y)^2 <= radius^2
        and math.abs(bottom-anchor.Z) <= footTolerance
end

function Adapter.VaultReady(actor, plan)
    local binding = bindings[actor]
    return plan and binding and not binding.Vault and KismetSystemLibrary.IsValid(actor)
        and UGCGenericCharacterSystem.IsAlive(actor)
        and not boardAttackActive(binding)
        and (not binding.QueueMember or (binding.QueueMember.Queue.LandingClear
            and binding.QueueMember.Queue.LaunchClear))
        and nearAnchor(actor, plan.Window.OutsideApproach:K2_GetComponentLocation(),
            plan.StartRadius, plan.FootTolerance)
end

function Adapter.PrepareBoardAttack(profile)
    if type(profile) ~= 'table' or type(profile.ClassPath) ~= 'string'
        or type(profile.Slot) ~= 'string' then
        return nil, 'INVALID_BOARD_ATTACK_SKILL_CONFIG'
    end
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(profile.ClassPath))
    if not class then return nil, 'BOARD_ATTACK_SKILL_UNAVAILABLE: ' .. profile.ClassPath end
    return {Class = class, Slot = profile.Slot}
end

function Adapter.StartBoardAttack(actor, window, plan)
    local binding = bindings[actor]
    if not binding or binding.Vault or not KismetSystemLibrary.IsValid(actor)
        or not UGCGenericCharacterSystem.IsAlive(actor) then
        return false, 'BOARD_ATTACKER_UNAVAILABLE'
    end
    local controller = actor:GetController()
    if not KismetSystemLibrary.IsValid(controller) then return false, 'BOARD_ATTACK_CONTROLLER_UNAVAILABLE' end
    local skill = binding.BoardAttack
    if not skill then
        skill = UGCPersistEffectSystem.AddSkillByClass(actor, plan.Class, -1, plan.Slot)
        if not skill then return false, 'BOARD_ATTACK_SKILL_GRANT_FAILED' end
        binding.BoardAttack = skill
    end
    if skill:IsActivating() or not skill:CanActivateSkill() then return false, 'BOARD_ATTACK_SKILL_BLOCKED' end
    local yaw = UGCMathUtility.FindLookAtRotation(actor:K2_GetActorLocation(),
        window.BoardRoot:K2_GetComponentLocation()).Yaw
    local facing = {Pitch = 0, Yaw = yaw, Roll = 0}
    controller:StopMovement()
    controller:K2_ClearFocus()
    actor.CharacterMovement:StopMovementImmediately()
    controller:SetControlRotation(facing)
    if not actor:K2_SetActorRotation(facing, false) then return false, 'BOARD_ATTACK_FACING_FAILED' end
    skill:ActivateSkill()
    if not skill:IsActivating() then return false, 'BOARD_ATTACK_ACTIVATION_FAILED' end
    return true
end

function Adapter.StopBoardAttack(actor, release)
    local binding = bindings[actor]
    local skill = binding and binding.BoardAttack
    if not skill or not KismetSystemLibrary.IsValid(actor) then return end
    if skill:IsActivating() then skill:DeActivateSkill(vaultInterruptReason) end
    if release then
        UGCPersistEffectSystem.RemoveSkillInstance(actor, skill)
        binding.BoardAttack = nil
    end
end

function Adapter.IsBoardAttackActive(actor)
    local binding = bindings[actor]
    return binding and KismetSystemLibrary.IsValid(actor) and boardAttackActive(binding)
end

function Adapter.StopVault(actor, landed)
    local binding = bindings[actor]
    local cast = binding and binding.Vault
    if not cast then return end
    binding.Vault = nil
    if not KismetSystemLibrary.IsValid(actor) then return end
    if cast.Skill:IsActivating() then
        cast.Skill:DeActivateSkill(landed and 0 or vaultInterruptReason)
    end
    UGCPersistEffectSystem.RemoveSkillInstance(actor, cast.Skill)
    if binding.QueueMember then Queue.AfterVault(binding.QueueMember, landed) end
    binding.RepathAt = nil
    if not binding.Targeting and UGCGenericCharacterSystem.IsAlive(actor) then
        setBehaviorPaused(actor, binding, false)
    end
end

function Adapter.StartVault(actor, plan)
    if not Adapter.VaultReady(actor, plan) then return false, "VAULT_NOT_READY" end
    local controller = actor:GetController()
    if not KismetSystemLibrary.IsValid(controller) then return false, "VAULT_CONTROLLER_UNAVAILABLE" end
    local skill = UGCPersistEffectSystem.AddSkillByClass(actor, plan.Class, -1, plan.Slot)
    if not skill then return false, "VAULT_SKILL_GRANT_FAILED" end
    if not skill:CanActivateSkill() then
        UGCPersistEffectSystem.RemoveSkillInstance(actor, skill)
        return false, "VAULT_SKILL_BLOCKED"
    end
    setBehaviorPaused(actor, bindings[actor], true)
    UGCGenericCharacterSystem.StopMove(actor)
    controller:StopMovement()
    controller:K2_ClearFocus()
    actor.CharacterMovement:StopMovementImmediately()
    bindings[actor].Vault = {Skill = skill}
    local facing = {Pitch=0, Yaw=plan.Yaw, Roll=0}
    controller:SetControlRotation(facing)
    if actor:K2_SetActorRotation(facing, false) then
        skill:ActivateSkill()
        if skill:IsActivating() then return true end
    end
    Adapter.StopVault(actor, false)
    return false, "VAULT_ACTIVATION_FAILED"
end

function Adapter.VaultStatus(actor, plan)
    local binding = bindings[actor]
    local cast = binding and binding.Vault
    if not cast or not KismetSystemLibrary.IsValid(actor) or not UGCGenericCharacterSystem.IsAlive(actor) then
        return "Interrupted"
    end
    if nearAnchor(actor, plan.Window.InsideLanding:K2_GetComponentLocation(), plan.LandingRadius,
        plan.FootTolerance) then return "Landed" end
    return cast.Skill:IsActivating() and "Moving" or "Interrupted"
end


function Adapter.ValidateContext(context)
    assert(context and KismetSystemLibrary.IsValid(context), 'INVALID_WORLD_CONTEXT')
    assert(context:HasAuthority(), 'DEFENSE_SERVER_ONLY')
end

function Adapter.Prepare(context, points, catalog)
    Adapter.ValidateContext(context)
    local plans = {}
    for _, point in ipairs(points) do
        local enemy = catalog.Enemies[point.EnemyConfigId]
        if type(enemy) ~= 'table' then
            return nil, 'ENEMY_CONFIG_REMOVED: ' .. point.EnemyConfigId
        end
        if type(enemy.ClassPath) ~= 'string' or enemy.ClassPath == '' then
            return nil, 'MISSING_ENEMY_CLASS_PATH: ' .. point.EnemyConfigId
        end
        -- Explicit contract: this class must forward its authoritative BPDie event.
        if enemy.DeathEvent ~= 'NormalZombie.BPDie' then
            return nil, 'UNSUPPORTED_DEATH_EVENT: ' .. point.EnemyConfigId
        end
        local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(enemy.ClassPath))
        if not class then return nil, 'ENEMY_CLASS_UNAVAILABLE: ' .. enemy.ClassPath end
        local placement = enemy.Placement
        if placement then
            assert(placement.SearchRadius > 0 and placement.Rings >= 1 and placement.Rings%1 == 0
                and placement.SamplesPerRing >= 1 and placement.SamplesPerRing%1 == 0
                and placement.Radius > 0 and placement.HalfHeight >= placement.Radius+placement.Spacing
                and placement.Spacing >= 0 and placement.GroundClearance > 0, 'INVALID_SPAWN_PLACEMENT')
            local copy = {}
            for k,v in pairs(placement) do
                if type(v)=='table' then local t={};for a,b in pairs(v)do t[a]=b end;copy[k]=t
                else copy[k]=v end
            end
            placement=copy
        end
        local dropChance = enemy.BoardDropChance
        if dropChance ~= nil and (type(dropChance) ~= 'number' or dropChance ~= dropChance
            or dropChance < 0 or dropChance > 1 or not catalog.BoardItemId) then
            return nil, 'INVALID_BOARD_DROP_CONFIG: ' .. point.EnemyConfigId
        end
        plans[#plans + 1] = {Point = point, Class = class, Placement = placement,
            BoardDropChance = dropChance, BoardItemId = catalog.BoardItemId}
    end
    return plans
end

function Adapter.Spawn(context, plan, onDeath)
    Adapter.ValidateContext(context)
    local point = plan.Point
    if not KismetSystemLibrary.IsValid(point) or not point.Enabled
        or not KismetSystemLibrary.IsValid(point.SpawnDirection) then
        return nil, 'SPAWN_POINT_UNAVAILABLE'
    end
    local location = point:K2_GetActorLocation()
    if plan.Placement then
        local Placement = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseSpawnPlacement')
        local reason
        location, reason = Placement.Find(context,location,plan.Placement,bindings,plan.Class)
        if not location then return nil,reason end
    end
    local actor = UGCGenericCharacterSystem.SpawnGenericCharacter(context, plan.Class,
        location, point.SpawnDirection:K2_GetComponentRotation())
    if not actor or not KismetSystemLibrary.IsValid(actor) then
        return nil, 'ENGINE_SPAWN_FAILED'
    end
    if bindings[actor] then return nil, 'ENEMY_ALREADY_BOUND' end
    bindings[actor] = {Context = context, OnDeath = onDeath, Placement = plan.Placement,
        BoardDropChance = plan.BoardDropChance, BoardItemId = plan.BoardItemId}
    return actor
end

function Adapter.NotifyDeath(actor)
    if not actor:HasAuthority() then return false, 'DEFENSE_SERVER_ONLY' end
    local binding = bindings[actor]
    if not binding then return false, 'UNTRACKED_ENEMY' end
    Adapter.Release(actor)
    if not KismetSystemLibrary.IsValid(binding.Context) then
        return false, 'WORLD_CONTEXT_ENDED'
    end
    binding.OnDeath(actor)
    local chance = binding.BoardDropChance
    if chance and chance > 0 and math.random() < chance then
        local at = actor:K2_GetActorLocation()
        local pickup = UGCItemSystemV2.SpawnPickupWrapper(at, binding.BoardItemId, 1)
        if not KismetSystemLibrary.IsValid(pickup) then
            ugcprint('[ZombieDefense] Failed to spawn board pickup: ' .. tostring(binding.BoardItemId))
        end
    end
    return true
end

function Adapter.Release(actor)
    local binding = bindings[actor]
    if not binding then return end
    Adapter.StopVault(actor, false)
    Adapter.StopBoardAttack(actor, true)
    if (binding.Player or binding.BehaviorPaused) and KismetSystemLibrary.IsValid(actor)
        and UGCGenericCharacterSystem.IsAlive(actor) then
        if binding.Player then actor:RemoveForceHatredTarget() end
        if binding.BehaviorPaused then
            UGCGenericCharacterSystem.StopMove(actor)
            setBehaviorPaused(actor, binding, false)
        end
    end
    bindings[actor] = nil
end

-- Board install eligibility: the installer must still be an alive participant
-- standing at their own window. The board module never calls the engine itself,
-- so this predicate is the single place where "still allowed to finish" is
-- decided, and it is re-evaluated at completion rather than at start.
function Adapter.InstallEligible(context, playerKey, actor, range)
    Adapter.ValidateContext(context)
    assert(type(playerKey) == 'number' and playerKey >= 0, 'INVALID_PLAYER_KEY')
    assert(type(range) == 'number' and range > 0, 'INVALID_INSTALL_RANGE')
    if not KismetSystemLibrary.IsValid(actor) or actor.Enabled ~= true then return false end
    if type(UGCPlayerStateSystem) == 'table'
        and UGCPlayerStateSystem.IsAlive and not UGCPlayerStateSystem.IsAlive(playerKey) then
        return false
    end
    local pawn = UGCGameSystem.GetPlayerPawnByPlayerKey(playerKey)
    if not pawn or not KismetSystemLibrary.IsValid(pawn) then return false end
    local anchor = KismetSystemLibrary.IsValid(actor.InteractionPoint)
        and actor.InteractionPoint:K2_GetComponentLocation()
        or actor:K2_GetActorLocation()
    local at = pawn:K2_GetActorLocation()
    if not (anchor and at) then return false end
    if (anchor.X-at.X)^2 + (anchor.Y-at.Y)^2 + (anchor.Z-at.Z)^2 > range^2 then return false end
    return pawn
end

-- Match the window interaction's WorldStatic and WorldDynamic object filter.
local obstructionTypes = {0, 1}
local function clearBoardContact(enemy, window, from, to)
    local ignored = {enemy, window}
    local view = window.DefenseBoardView
    if view then
        for _, board in pairs(view.Boards) do ignored[#ignored + 1] = board end
    end
    return not KismetSystemLibrary.LineTraceSingleForObjects(
        enemy, from, to, obstructionTypes, false, ignored, 0, {}, true,
        {R=1,G=0,B=0,A=1}, {R=0,G=1,B=0,A=1}, 0)
end

local function windowGeometry(actor, pointId)
    local outside = actor.OutsideApproach:K2_GetComponentLocation()
    local inside = actor.InsideLanding:K2_GetComponentLocation()
    local board = actor.BoardRoot:K2_GetComponentLocation()
    local dx, dy = outside.X - inside.X, outside.Y - inside.Y
    local function exterior(location)
        return (location.X - board.X)*dx + (location.Y - board.Y)*dy > 0
    end
    local insideSide = (inside.X - board.X)*dx + (inside.Y - board.Y)*dy
    if not exterior(outside) or insideSide >= 0 then
        return nil, "INVALID_WINDOW_APPROACH: " .. pointId
    end
    return {Outside = outside, Board = board, Exterior = exterior}
end

function Adapter.PrepareTargeting(windows, config, queueConfig)
    if type(config) ~= 'table' or type(config.RepathSeconds) ~= 'number'
        or not (config.RepathSeconds > 0 and config.RepathSeconds < math.huge)
        or type(config.WindowStopRadius) ~= 'number'
        or not (config.WindowStopRadius > 0 and config.WindowStopRadius < math.huge) then
        return nil, 'INVALID_TARGETING_CONFIG'
    end
    local class = UE.LoadClass('/Script/Engine.NavigationSystem')
    local navigation = class and UGCObjectUtility.GetClassDefaultObject(class)
    if not navigation or not navigation.GetPathLength then
        return nil, 'ZOMBIE_NAV_QUERY_UNAVAILABLE'
    end
    local entries, queues = {}, {}
    for _, actor in ipairs(windows) do
        local geometry, reason = windowGeometry(actor, actor.PointId)
        if not geometry then return nil, reason end
        local queue
        if actor.QueueEnabled then
            if not queueConfig then return nil, 'MISSING_WINDOW_QUEUE_CONFIG: ' .. actor.PointId end
            Queue = Queue or UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWindowQueue')
            local detail
            queue, detail = Queue.Prepare(actor, geometry, queueConfig)
            if not queue then return nil, 'INVALID_WINDOW_QUEUE: ' .. actor.PointId .. ' ' .. detail end
            queues[actor.PointId] = queue
        end
        entries[#entries + 1] = {PointId = actor.PointId, Window = geometry, Actor = actor, Queue = queue}
    end
    return {PathLength = navigation.GetPathLength, Windows = entries, RepathSeconds = config.RepathSeconds,
        WindowStopRadius = config.WindowStopRadius, Queues = queues}
end

local GMState = UGCGameSystem.UGCRequire('Script.Gameplay.Debug.GMPlayerState')

local function livingPlayers()
    local players, keys = {}, {}
    for _, controller in pairs(UGCGameSystem.GetAllPlayerController(false)) do
        if KismetSystemLibrary.IsValid(controller) then
            local key = UGCGameSystem.GetPlayerKeyByPlayerController(controller)
            if type(key) == 'number' and key >= 0 and UGCPlayerStateSystem.IsAlive(key) then
                local pawn = UGCGameSystem.GetPlayerPawnByPlayerKey(key)
                if KismetSystemLibrary.IsValid(pawn) and not GMState.IsInvisible(pawn) then
                    players[key] = pawn
                    keys[#keys + 1] = key
                end
            end
        end
    end
    table.sort(keys)
    return players, keys
end

local function applyTarget(actor, binding, target, controller, stopRadius)
    local player = target and target.Player
    local pointId = target and target.PointId
    local destination = pointId and target.Destination
    local changed = not binding.Targeting or binding.Player ~= player or binding.PointId ~= pointId
        or binding.Destination ~= destination
    binding.Targeting = true
    if changed then
        Adapter.StopBoardAttack(actor, false)
        UGCGenericCharacterSystem.StopMove(actor)
        if binding.Player and not player then actor:RemoveForceHatredTarget() end
        if player then actor:SetForceHatredTarget(player) end
        binding.Player, binding.PlayerKey, binding.PointId = player, target and target.PlayerKey, pointId
        binding.Destination = destination
        setBehaviorPaused(actor, binding, player == nil)
    end
    -- Idle requests can be retried when navigation or crowd movement clears.
    if pointId and not boardAttackActive(binding) and (changed or controller:GetMoveStatus() == 0) then
        local from = actor:GetNavAgentLocation()
        local dx,dy = from.X-destination.X,from.Y-destination.Y
        if target.Queue and dx*dx+dy*dy <= stopRadius^2 then return end
        controller:MoveToLocation(destination, stopRadius, false, true, false, false,
            controller.DefaultNavigationFilterClass, false, false)
    end
end

function Adapter.UpdateTargeting(plan, actors, dying, now, barricade, vaults)
    local players, keys = livingPlayers()
    local ids = {}
    for id in pairs(actors) do ids[#ids+1] = id end
    if next(plan.Queues) then
        local positions = {}
        for id, actor in pairs(actors) do
            if bindings[actor] and not dying[id] and KismetSystemLibrary.IsValid(actor)
                and UGCGenericCharacterSystem.IsAlive(actor) then
                positions[actor] = actor:GetNavAgentLocation()
            end
        end
        for _, pawn in pairs(players) do positions[pawn] = pawn:GetNavAgentLocation() end
        for id, queue in pairs(plan.Queues) do
            Queue.Update(queue, positions, now, vaults[id].StartRadius, not barricade:IsPassable(id))
        end
        table.sort(ids)
    end
    for _, enemyId in ipairs(ids) do
        local actor = actors[enemyId]
        local binding = bindings[actor]
        if binding and not binding.Vault and not dying[enemyId]
            and KismetSystemLibrary.IsValid(actor) and UGCGenericCharacterSystem.IsAlive(actor)
            and (not binding.RepathAt or now >= binding.RepathAt
                or (binding.Player and players[binding.PlayerKey] ~= binding.Player)) then
            local controller = actor:GetController()
            if KismetSystemLibrary.IsValid(controller) then
                local from = actor:GetNavAgentLocation()
                local filter = controller.DefaultNavigationFilterClass
                local target, shortest, previous = nil, math.huge, false
                local function consider(to, player, key, pointId, queue, slot)
                    local result, length = plan.PathLength(controller, from, to, -1, nil, filter)
                    if result == pathSuccess and queue and slot ~= queue then
                        result, length = plan.PathLength(controller, from, queue.Start, -1, nil, filter)
                    end
                    -- Recast can fill the length for a partial route while returning Fail.
                    if result ~= pathSuccess then return end
                    if type(length) ~= 'number' or not (length >= 0 and length < math.huge) then
                        return 'ZOMBIE_NAV_LENGTH_UNAVAILABLE'
                    end
                    local current = player and binding.Player == player or pointId and binding.PointId == pointId
                    if length < shortest or (length == shortest and current and not previous) then
                        shortest, previous = length, current
                        target = {Player = player, PlayerKey = key, PointId = pointId, Destination = to,
                            Queue=queue, Slot=slot}
                    end
                end
                if not binding.QueueMember then
                    for _, key in ipairs(keys) do
                        local player = players[key]
                        local err = consider(player:GetNavAgentLocation(), player, key)
                        if err then return false, err end
                    end
                    for _, entry in ipairs(plan.Windows) do
                        if entry.Actor.Enabled and entry.Window.Exterior(from) then
                            local queue = entry.Queue
                            local slot = queue and Queue.Offer(queue, binding, now, not barricade:IsPassable(entry.PointId))
                            if not queue or slot then
                                local goal = slot and slot.Goal or entry.Window.Outside
                                local err = consider(goal, nil, nil, entry.PointId, queue, slot)
                                if err then return false, err end
                            end
                        end
                    end
                    if target and target.Queue then Queue.Assign(target.Queue, target.Slot, actor, binding) end
                end
                local member = binding.QueueMember
                local radius = plan.WindowStopRadius
                if member then
                    target = {PointId=member.Queue.Id, Destination=Queue.Destination(member), Queue=member.Queue}
                    if member.Slot or member.Withdrawing then radius = member.Queue.Config.StopRadius end
                end
                applyTarget(actor, binding, target, controller, radius)
                binding.RepathAt = now + plan.RepathSeconds
            end
        end
    end
    return true
end

-- Use the window anchors to distinguish exterior attackers from indoor enemies.
function Adapter.CollectBoardContacts(barricade, actors, assault, dying, targeting)
    assert(type(barricade) == 'table', 'MISSING_BARRICADE')
    assert(type(actors) == 'table', 'MISSING_ACTORS')
    assert(type(assault) == 'table', 'MISSING_ASSAULT')
    local skip = dying or {}
    local contacts = {}
    for _, window in ipairs(barricade.List) do
        local range = assault:Range(window.PointId)
        local actor = window.Actor
        local geometry, reason = windowGeometry(actor, window.PointId)
        if not geometry then return nil, reason end
        local outside = geometry.Outside
        local queue = targeting and targeting.Queues[window.PointId]
        local found = {}
        for enemyId, actor in pairs(actors) do
            -- A zombie already queued as dead this frame is a corpse even if
            -- the engine still reports it alive, so it gets no last hit.
            local binding = bindings[actor]
            if not skip[enemyId] and (not targeting or binding and not binding.Vault
                and binding.PointId == window.PointId) and (not queue
                or queue.Lead and queue.Lead.Actor == actor and not queue.Lead.Withdrawing)
                and KismetSystemLibrary.IsValid(actor)
                and UGCGenericCharacterSystem.IsAlive(actor) then
                local at = actor:K2_GetActorLocation()
                if at and geometry.Exterior(at)
                    and (outside.X-at.X)^2 + (outside.Y-at.Y)^2
                        + (outside.Z-at.Z)^2 <= range^2
                    and clearBoardContact(actor, window.Actor, at, geometry.Board) then
                    found[#found + 1] = enemyId
                end
            end
        end
        if #found > 0 then
            -- Deterministic order so the same tick always picks the same lead
            -- attacker for a climb, regardless of table iteration order.
            table.sort(found)
            contacts[#contacts + 1] = {PointId = window.PointId, EnemyIds = found}
        end
    end
    return contacts
end

return Adapter
