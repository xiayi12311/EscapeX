-- Engine boundary only; no target-selection, timers, or team-rule defaults.
local Adapter = {}
local bindings = setmetatable({}, {__mode = 'k'})

local vaultPauseReason = "ZombieDefenseVault"
local vaultInterruptReason = 1 -- EPESkillDeActivateReason.Interrupt

function Adapter.PrepareVaults(windows, configs)
    local result = {}
    for _, window in ipairs(windows) do
        local profile = configs and configs[window.PointId]
        if profile then
            for _, key in ipairs({"Travel", "StartRadius", "LandingRadius", "FootTolerance"}) do
                local value = profile[key]
                if type(value) ~= "number" or value <= 0 or value >= math.huge or value ~= value then
                    return nil, "INVALID_VAULT_CONFIG: " .. window.PointId
                end
            end
            local windowStart = window.OutsideApproach:K2_GetComponentLocation()
            local windowEnd = window.InsideLanding:K2_GetComponentLocation()
            local dx, dy = windowEnd.X - windowStart.X, windowEnd.Y - windowStart.Y
            if math.abs(math.sqrt(dx*dx + dy*dy) - profile.Travel) > profile.StartRadius
                or math.abs(windowEnd.Z - windowStart.Z) > profile.FootTolerance then
                return nil, "VAULT_GEOMETRY_MISMATCH: " .. window.PointId
            end
            local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(profile.ClassPath))
            if not class then return nil, "VAULT_SKILL_UNAVAILABLE: " .. window.PointId end
            result[window.PointId] = {
                Class = class, Slot = profile.Slot, Window = window, StartRadius = profile.StartRadius,
                LandingRadius = profile.LandingRadius, FootTolerance = profile.FootTolerance,
                Yaw = UGCMathUtility.FindLookAtRotation(windowStart, windowEnd).Yaw,
            }
        end
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
        and nearAnchor(actor, plan.Window.OutsideApproach:K2_GetComponentLocation(),
            plan.StartRadius, plan.FootTolerance)
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
    if UGCGenericCharacterSystem.IsAlive(actor) then
        UGCGenericCharacterSystem.ResumeBehavior(actor, vaultPauseReason)
    end
end

function Adapter.StartVault(actor, plan)
    if not Adapter.VaultReady(actor, plan) then return false, "VAULT_NOT_READY" end
    local skill = UGCPersistEffectSystem.AddSkillByClass(actor, plan.Class, -1, plan.Slot)
    if not skill then return false, "VAULT_SKILL_GRANT_FAILED" end
    if not skill:CanActivateSkill() then
        UGCPersistEffectSystem.RemoveSkillInstance(actor, skill)
        return false, "VAULT_SKILL_BLOCKED"
    end
    UGCGenericCharacterSystem.PauseBehavior(actor, vaultPauseReason)
    UGCGenericCharacterSystem.StopMove(actor)
    bindings[actor].Vault = {Skill = skill}
    if actor:K2_SetActorRotation({Pitch=0, Yaw=plan.Yaw, Roll=0}, false) then
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
        plans[#plans + 1] = {Point = point, Class = class, Placement = placement}
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
    bindings[actor] = {Context = context, OnDeath = onDeath, Placement = plan.Placement}
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
    return true
end

function Adapter.Release(actor)
    Adapter.StopVault(actor, false)
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
    if not KismetSystemLibrary.IsValid(actor) then return false end
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
    return (anchor.X-at.X)^2 + (anchor.Y-at.Y)^2 + (anchor.Z-at.Z)^2 <= range^2
end

-- Match the window interaction's WorldStatic and WorldDynamic object filter.
local obstructionTypes = {0, 1}
local function clearBoardContact(enemy, window, from, to)
    return not KismetSystemLibrary.LineTraceSingleForObjects(
        enemy, from, to, obstructionTypes, false, {enemy, window}, 0, {}, true,
        {R=1,G=0,B=0,A=1}, {R=0,G=1,B=0,A=1}, 0)
end
-- Use the window anchors to distinguish exterior attackers from indoor enemies.
function Adapter.CollectBoardContacts(barricade, actors, assault, dying)
    assert(type(barricade) == 'table', 'MISSING_BARRICADE')
    assert(type(actors) == 'table', 'MISSING_ACTORS')
    assert(type(assault) == 'table', 'MISSING_ASSAULT')
    local skip = dying or {}
    local contacts = {}
    for _, window in ipairs(barricade.List) do
        local range = assault:Range(window.PointId)
        local actor = window.Actor
        local outside = actor.OutsideApproach:K2_GetComponentLocation()
        local inside = actor.InsideLanding:K2_GetComponentLocation()
        local board = actor.BoardRoot:K2_GetComponentLocation()
        local dx, dy = outside.X - inside.X, outside.Y - inside.Y
        local function side(location)
            return (location.X - board.X)*dx + (location.Y - board.Y)*dy
        end
        if side(outside) <= 0 or side(inside) >= 0 then
            return nil, "INVALID_WINDOW_APPROACH: " .. window.PointId
        end
        local found = {}
        for enemyId, actor in pairs(actors) do
            -- A zombie already queued as dead this frame is a corpse even if
            -- the engine still reports it alive, so it gets no last hit.
            if not skip[enemyId] and KismetSystemLibrary.IsValid(actor)
                and UGCGenericCharacterSystem.IsAlive(actor) then
                local at = actor:K2_GetActorLocation()
                if at and side(at) > 0
                    and (outside.X-at.X)^2 + (outside.Y-at.Y)^2
                        + (outside.Z-at.Z)^2 <= range^2
                    and clearBoardContact(actor, window.Actor, at, board) then
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
