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
        plans[#plans + 1] = {Point = point, Class = class}
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
    local actor = UGCGenericCharacterSystem.SpawnGenericCharacter(context, plan.Class,
        point:K2_GetActorLocation(), point.SpawnDirection:K2_GetComponentRotation())
    if not actor or not KismetSystemLibrary.IsValid(actor) then
        return nil, 'ENGINE_SPAWN_FAILED'
    end
    if bindings[actor] then return nil, 'ENEMY_ALREADY_BOUND' end
    bindings[actor] = {Context = context, OnDeath = onDeath}
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
