-- Server-only integration for the once-per-match desk milestone.
local Service = {}
local Route = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCommon")
local TEACHER_CLASS = '/EscapeX/Asset/Blueprint/Prefabs/Monsters/TheHeadTeacher.TheHeadTeacher_C'
-- Count trigger entry: DeskOutcomeConfig.CountTriggers dispatches by opened count.
local SECOND_ROUTE_GROUP = 'HT_Route1'
local function valid(x) return x ~= nil and KismetSystemLibrary.IsValid(x) end
local function log(message) ugcprint('[DeskTeacherSpawner] '..message) end

-- Switch the second patrol group on, once. The route list rebuilds within
-- HTRouteRefreshInterval on the monster after the control's bEnabled flips.
local function enableSecondRoute(gm)
    if gm.DeskSecondRouteEnabled then return true end
    local mob = gm.DeskTeacherSpawnedActor
    if not valid(mob) then return false end
    if not Route.setGroupEnabled(mob, SECOND_ROUTE_GROUP, true) then
        log('ERROR: no route group control named '..SECOND_ROUTE_GROUP)
        return false
    end
    gm.DeskSecondRouteEnabled = true
    log('Enabled second patrol group '..SECOND_ROUTE_GROUP)
    return true
end

local function trySpawn(gm)
    if gm.DeskTeacherSpawned or gm.DeskTeacherSpawnInProgress or gm.DeskTeacherSpawnFailed or not gm.DeskTeacherReached then return false end
    local marker = gm.DeskTeacherSpawnPoint
    if not valid(marker) then return false end
    if not valid(marker.SpawnPoint) then
        gm.DeskTeacherSpawnFailed = true
        log('ERROR: marker has no SpawnPoint component')
        return false
    end
    local cls = UGCObjectUtility.LoadClass(TEACHER_CLASS)
    if not cls then
        gm.DeskTeacherSpawnFailed = true
        log('ERROR: cannot load teacher class '..TEACHER_CLASS)
        return false
    end
    gm.DeskTeacherSpawnInProgress = true
    local ok, mob = pcall(UGCMobPawnSystem.SpawnMob, marker, cls,
        marker.SpawnPoint:K2_GetComponentLocation(), marker.SpawnPoint:K2_GetComponentRotation())
    gm.DeskTeacherSpawnInProgress = false
    if not ok or not valid(mob) then
        gm.DeskTeacherSpawnFailed = true
        log('ERROR: SpawnMob failed: '..tostring(mob))
        return false
    end
    gm.DeskTeacherSpawned = true
    gm.DeskTeacherSpawnedActor = mob
    log('Spawned teacher after two completed desk searches')
    -- A route milestone may have fired before the teacher existed.
    if gm.DeskSecondRoutePending then
        gm.DeskSecondRoutePending = nil
        enableSecondRoute(gm)
    end
    return true
end

function Service.Register(gm, marker)
    if not valid(gm) or not gm:HasAuthority() or not valid(marker) then return false end
    if valid(gm.DeskTeacherSpawnPoint) and gm.DeskTeacherSpawnPoint ~= marker then
        log('ERROR: multiple desk teacher spawn markers; keep exactly one')
        return false
    end
    gm.DeskTeacherSpawnPoint = marker
    trySpawn(gm)
    return true
end

function Service.Unregister(gm, marker)
    if valid(gm) and gm:HasAuthority() and gm.DeskTeacherSpawnPoint == marker then
        gm.DeskTeacherSpawnPoint = nil
    end
end

function Service.OnCompleted(gm, count)
    if not valid(gm) or not gm:HasAuthority() then return end
    if type(count) ~= 'number' then log('ERROR: completed event missing count'); return end
    if count == 2 then
        gm.DeskTeacherReached = true
        if not valid(gm.DeskTeacherSpawnPoint) then log('Waiting for the desk teacher spawn marker') end
        trySpawn(gm)
    end
    -- Retry a milestone that could not apply earlier (e.g. class still loading).
    if gm.DeskSecondRoutePending and enableSecondRoute(gm) then
        gm.DeskSecondRoutePending = nil
    end
end

-- Count-trigger entry point (DeskOutcomeConfig.CountTriggers). Enables the second
-- patrol group once; when the teacher is not alive yet it retries after spawning.
function Service.OnRouteMilestone(gm)
    if not valid(gm) or not gm:HasAuthority() then return end
    if not enableSecondRoute(gm) then gm.DeskSecondRoutePending = true end
end

return Service
