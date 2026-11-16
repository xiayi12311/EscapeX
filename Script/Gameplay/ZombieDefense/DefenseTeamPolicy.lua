-- Server encounter roster and elimination policy. Session remains the result owner.
local M = {Config={AllowRevive=false}}
local owners = setmetatable({}, {__mode='k'})
local function server(gm) assert(gm and gm:HasAuthority(), 'DEFENSE_SERVER_ONLY') end
function M.Capture(gm, count)
    server(gm)
    local keys = {}
    for _, pc in pairs(UGCGameSystem.GetAllPlayerController(false)) do
        if KismetSystemLibrary.IsValid(pc) then
            local key = UGCGameSystem.GetPlayerKeyByPlayerController(pc)
            if type(key) ~= 'number' or key < 0 or keys[key] then return nil, 'INVALID_PARTICIPANT' end
            if not UGCPlayerStateSystem.IsAlive(key) then return nil, 'PARTICIPANT_NOT_ALIVE' end
            if M.BlocksAutoRevive(gm,key) then return nil, 'PARTICIPANT_ALREADY_ASSIGNED' end
            keys[key] = {Dead=false, Pending=false}
        end
    end
    local size=0; for _ in pairs(keys) do size=size+1 end
    if size ~= count or size < 1 or size > 4 then return nil, 'PARTICIPANT_COUNT_CHANGED' end
    return keys
end
function M.Attach(gm, encounter, keys)
    server(gm)
    owners[gm] = owners[gm] or {}
    owners[gm][encounter] = keys
    local Revive = UGCGameSystem.UGCRequire('Script.Common.TestAutoRevive')
    for key in pairs(keys) do Revive.cancel(key) end
end
function M.BlocksAutoRevive(gm,key)
    for _, keys in pairs(owners[gm] or {}) do if keys[key] then return true end end
    return false
end
function M.TeamFailed(gm,encounter)
    server(gm)
    local keys = assert(owners[gm] and owners[gm][encounter], 'DEFENSE_ROSTER_MISSING')
    for key, member in pairs(keys) do
        if not member.Dead and UGCPlayerStateSystem.IsAlive(key) then return false end
    end
    return true
end
function M.OnKilled(gm,key)
    server(gm)
    local encounters = {}
    for encounter, keys in pairs(owners[gm] or {}) do
        if keys[key] then keys[key].Dead=true;keys[key].Pending=false;encounters[#encounters+1]=encounter end
    end
    return encounters
end
-- Reserved server entry; no RPC, purchase, retry, or success claim on request return.
function M.RequestRevive(gm,encounter,key)
    server(gm)
    if not M.Config.AllowRevive then return false, 'REVIVE_DISABLED' end
    local member = owners[gm] and owners[gm][encounter] and owners[gm][encounter][key]
    if not member then return false, 'NOT_PARTICIPANT' end
    local snapshot = gm.ZombieDefenseService and gm.ZombieDefenseService:Snapshot(encounter)
    if not snapshot or snapshot.State=='Succeeded' or snapshot.State=='Failed' or snapshot.Error or snapshot.AdapterError then return false, 'ENCOUNTER_NOT_ACTIVE' end
    if M.TeamFailed(gm,encounter) then return false, 'TEAM_ELIMINATED' end
    if not member.Dead or UGCPlayerStateSystem.IsAlive(key) then return false, 'PLAYER_NOT_DEAD' end
    if member.Pending then return false, 'REVIVE_PENDING' end
    member.Pending=true -- Native call may synchronously emit RespawnEvent.
    UGCPlayerPawnSystem.RespawnPlayer(key,0,false,0.01)
    return true, 'REVIVE_REQUESTED'
end
function M.OnRespawn(gm,key)
    server(gm)
    for encounter, keys in pairs(owners[gm] or {}) do
        local member=keys[key]
        if member then
            local snapshot=gm.ZombieDefenseService and gm.ZombieDefenseService:Snapshot(encounter)
            if member.Pending and snapshot and snapshot.State~='Failed' and snapshot.State~='Succeeded' then member.Pending=false;member.Dead=false
            else member.Pending=false;ugcprint('[ZombieDefense] Unexpected external respawn PlayerKey='..tostring(key)) end
        end
    end
end
function M.Shutdown(gm) owners[gm]=nil end
return M
