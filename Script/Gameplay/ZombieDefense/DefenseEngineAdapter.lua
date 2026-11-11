-- Engine boundary only; no target-selection, timers, or team-rule defaults.
local Adapter = {}
local bindings = setmetatable({}, {__mode = 'k'})

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
    bindings[actor] = nil
    if not KismetSystemLibrary.IsValid(binding.Context) then
        return false, 'WORLD_CONTEXT_ENDED'
    end
    binding.OnDeath(actor)
    return true
end

function Adapter.Release(actor)
    bindings[actor] = nil
end

return Adapter
