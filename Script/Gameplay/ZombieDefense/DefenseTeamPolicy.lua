-- Server encounter roster and elimination policy. Session remains the result owner.
-- Approved rules: no auto revive in-encounter; all dead fails immediately;
-- disconnect is ignored while a teammate is alive, but does not hold the team
-- open; mid-encounter joins count as participants.
local M = {Config={AllowRevive=false, JoinGraceSeconds=10}, MaxParticipants=4}
local owners = setmetatable({}, {__mode='k'})
local function server(gm) assert(gm and gm:HasAuthority(), 'DEFENSE_SERVER_ONLY') end
local function active(snapshot)
    return snapshot and snapshot.State ~= 'Succeeded' and snapshot.State ~= 'Failed'
end
local function terminal(snapshot)
    return snapshot and (snapshot.State == 'Succeeded' or snapshot.State == 'Failed')
end
local function clock()
    return UGCGameSystem.GetServerTimeSec and UGCGameSystem.GetServerTimeSec() or 0
end
local function snapshotOf(gm, encounter)
    return gm.ZombieDefenseService and gm.ZombieDefenseService:Snapshot(encounter)
end
local function cancelAutoRevive(key)
    local Revive = UGCGameSystem.UGCRequire('Script.Common.TestAutoRevive')
    Revive.cancel(key)
end
function M.Capture(gm, count)
    server(gm)
    local keys = {}
    for _, pc in pairs(UGCGameSystem.GetAllPlayerController(false)) do
        if KismetSystemLibrary.IsValid(pc) then
            local key = UGCGameSystem.GetPlayerKeyByPlayerController(pc)
            if type(key) ~= 'number' or key < 0 or keys[key] then return nil, 'INVALID_PARTICIPANT' end
            if not UGCPlayerStateSystem.IsAlive(key) then return nil, 'PARTICIPANT_NOT_ALIVE' end
            if M.Assigned(gm,key) then return nil, 'PARTICIPANT_ALREADY_ASSIGNED' end
            keys[key] = {Dead=false, Offline=false, Pending=false, JoinedAt=clock()}
        end
    end
    local size=0; for _ in pairs(keys) do size=size+1 end
    if size ~= count or size < 1 or size > M.MaxParticipants then return nil, 'PARTICIPANT_COUNT_CHANGED' end
    return keys
end
-- Join/start eligibility only: is this player already owned by a *running* encounter?
-- Deliberately narrower than BlocksAutoRevive, which also protects an eliminated member
-- of a finished encounter. Reusing the wider predicate here rejected a wiped player
-- from every later encounter and told them "another defense is running".
function M.Assigned(gm,key)
    for encounter, keys in pairs(owners[gm] or {}) do
        if keys[key] and active(snapshotOf(gm,encounter)) then return true end
    end
    return false
end
function M.Attach(gm, encounter, keys)
    server(gm)
    owners[gm] = owners[gm] or {}
    -- A finished encounter keeps its roster for reconnect/audit, but it must not keep
    -- owning these players: their Dead flag is what blocks the test revive, and a new
    -- encounter has just taken responsibility for them.
    for other, roster in pairs(owners[gm]) do
        if other ~= encounter and terminal(snapshotOf(gm, other)) then
            for key in pairs(keys) do roster[key] = nil end
        end
    end
    owners[gm][encounter] = keys
    for key in pairs(keys) do cancelAutoRevive(key) end
end
function M.BlocksAutoRevive(gm,key)
    -- A running encounter owns the player's revive behaviour. After the terminal
    -- result the roster entry stays for reconnect/audit, but a *surviving* participant
    -- must get their normal (test) revive back; otherwise a finished encounter would
    -- silently disable it for the rest of the match.
    -- A participant the encounter eliminated stays blocked even after the result is
    -- terminal: the failure is caused by that very death, so releasing the block at
    -- that moment would let the test module revive the corpse one second later and
    -- contradict the approved "no revive in this encounter" rule.
    for encounter, keys in pairs(owners[gm] or {}) do
        local member = keys[key]
        if member then
            if active(snapshotOf(gm,encounter)) then return true end
            if member.Dead then return true end
        end
    end
    return false
end
function M.CanShop(gm, encounter, key)
    server(gm)
    local roster = owners[gm] and owners[gm][encounter]
    local member = key and roster and roster[key]
    return member ~= nil and not member.Dead and not member.Offline and UGCPlayerStateSystem.IsAlive(key)
end

-- Approved rules: all dead fails; a disconnect does not fail by itself. If the
-- players still online are wiped the encounter fails even while someone else is
-- offline; if nobody is online but a member is still alive, the team waits for
-- that player to reconnect instead of failing.
-- The roster is authoritative for elimination: Killed marks Dead before the
-- player state's IsAlive catches up, and a reconnect can briefly read not-alive
-- while the pawn is rebuilt. IsAlive is only used for join eligibility, never to
-- turn a roster-alive participant into a failure.
function M.TeamFailed(gm,encounter)
    server(gm)
    local keys = assert(owners[gm] and owners[gm][encounter], 'DEFENSE_ROSTER_MISSING')
    local online = 0
    for _, member in pairs(keys) do
        if not member.Offline then
            online = online + 1
            if not member.Dead then return false end
        end
    end
    if online == 0 then
        for _, member in pairs(keys) do if not member.Dead then return false end end
    end
    return true
end
-- The victim's key could not be resolved (controller/pawn both unusable). The roster
-- is the only source left, so reconcile it against the authoritative alive query.
-- Deliberately conservative: a reconnect legitimately reads not-alive while its pawn
-- is being rebuilt, so freshly joined members and members with a revive in flight are
-- skipped, and an ambiguous frame (more than one candidate) marks nobody. Failing a
-- team is irreversible, so a spurious wipe is worse than waiting for the next kill
-- event, which resolves normally once the victim key is readable again.
function M.OnKilled(gm,key)
    server(gm)
    local encounters = {}
    if type(key) == 'number' and key >= 0 then
        for encounter, keys in pairs(owners[gm] or {}) do
            if keys[key] then keys[key].Dead=true;keys[key].Pending=false;encounters[#encounters+1]=encounter end
        end
        return encounters
    end
    local now = clock()
    for encounter, keys in pairs(owners[gm] or {}) do
        local candidates = {}
        for memberKey, member in pairs(keys) do
            if not member.Dead and not member.Offline and not member.Pending
                and now - (member.JoinedAt or now) >= M.Config.JoinGraceSeconds
                and not UGCPlayerStateSystem.IsAlive(memberKey) then
                candidates[#candidates+1] = memberKey
            end
        end
        if #candidates == 1 then
            local member = keys[candidates[1]]
            member.Dead=true; member.Pending=false
            encounters[#encounters+1]=encounter
        elseif #candidates > 1 then
            ugcprint('[ZombieDefense] unattributable kill in Encounter='..tostring(encounter)
                ..': '..tostring(#candidates)..' candidates; roster left unchanged')
        end
    end
    return encounters
end
function M.Detach(gm,encounter)
    server(gm)
    if owners[gm] then owners[gm][encounter]=nil end
end
-- PlayerExitEvent runs while the controller still exists, so the key is readable.
function M.OnExit(gm,key)
    server(gm)
    local changed = false
    for _, keys in pairs(owners[gm] or {}) do
        local member = keys[key]
        if member then member.Offline=true;member.Pending=false;changed=true end
    end
    return changed
end
-- Login covers both a reconnect and a mid-encounter join. A known participant is
-- re-marked online without changing death state; an unknown player joins at most
-- ONE running encounter (joining every encounter would double-count that player in
-- TeamFailed and in BlocksAutoRevive). Difficulty was frozen at start.
-- knownAlive skips the IsAlive probe: the respawn path calls this right after the
-- authoritative respawn event, where the pawn may not be rebuilt yet and the probe
-- would read false, silently keeping a genuinely alive player out of the encounter.
function M.OnLogin(gm,key,knownAlive)
    server(gm)
    local encounters = {}
    for encounter, keys in pairs(owners[gm] or {}) do
        local member = keys[key]
        if member then
            member.Offline=false
            member.JoinedAt = member.JoinedAt or clock()
            encounters[#encounters+1]=encounter
        end
    end
    -- A player eliminated by a finished encounter still has a roster entry (it blocks
    -- the test revive); that entry must not stop them joining a later one. Only an
    -- entry inside a *running* encounter owns the player.
    if M.Assigned(gm,key) then return encounters end
    if not knownAlive and not UGCPlayerStateSystem.IsAlive(key) then return encounters end
    local names = {}
    for encounter in pairs(owners[gm] or {}) do names[#names+1]=encounter end
    table.sort(names)
    for _, encounter in ipairs(names) do
        local keys = owners[gm][encounter]
        if active(snapshotOf(gm,encounter)) and M._size(keys) < M.MaxParticipants then
            keys[key] = {Dead=false, Offline=false, Pending=false, JoinedAt=clock()}
            cancelAutoRevive(key)
            encounters[#encounters+1]=encounter
            break
        end
    end
    return encounters
end
function M.Encounters(gm)
    server(gm)
    local list = {}
    for encounter in pairs(owners[gm] or {}) do list[#list+1]=encounter end
    return list
end
-- Number of roster members currently connected. Zero means nobody is present to
-- fight, so wave progression must pause rather than keep spawning at an empty map.
function M.Online(gm,encounter)
    server(gm)
    local count=0
    for _, member in pairs(owners[gm] and owners[gm][encounter] or {}) do
        if not member.Offline then count=count+1 end
    end
    return count
end
function M._size(keys)
    local size=0; for _ in pairs(keys) do size=size+1 end
    return size
end
-- Reserved server entry; no RPC, purchase, retry, or success claim on request return.
function M.RequestRevive(gm,encounter,key)
    server(gm)
    if not M.Config.AllowRevive then return false, 'REVIVE_DISABLED' end
    local member = owners[gm] and owners[gm][encounter] and owners[gm][encounter][key]
    if not member then return false, 'NOT_PARTICIPANT' end
    local snapshot = snapshotOf(gm,encounter)
    if not active(snapshot) or snapshot.Error or snapshot.AdapterError then return false, 'ENCOUNTER_NOT_ACTIVE' end
    if M.TeamFailed(gm,encounter) then return false, 'TEAM_ELIMINATED' end
    if not member.Dead or member.Offline or UGCPlayerStateSystem.IsAlive(key) then return false, 'PLAYER_NOT_DEAD' end
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
            local running=active(snapshotOf(gm,encounter))
            if member.Pending and running then
                member.Pending=false;member.Dead=false;member.Offline=false
            elseif member.Offline then
                -- A player disconnected while dead gets a fresh pawn on reconnect; that
                -- rebuild raises the same respawn event. It is not a revive of this
                -- encounter, so the roster stays eliminated and the run is not frozen.
                member.Pending=false
            elseif not running then
                member.Pending=false
            else
                -- Something outside this encounter brought an online player back (engine
                -- or blueprint revive path). The approved rule is that this encounter
                -- never revives on its own, so this is a configuration defect, not a
                -- normal outcome: freeze the run with a named error so the driver/HUD
                -- surface it instead of quietly rewriting the roster.
                member.Pending=false
                local service = gm.ZombieDefenseService
                if service and service.ReportError then
                    service:ReportError(encounter, 'EXTERNAL_REVIVE_BLOCKED')
                end
                ugcprint('[ZombieDefense] External respawn inside encounter PlayerKey='
                    ..tostring(key)..' Encounter='..tostring(encounter)
                    ..'; run frozen (engine/blueprint revive path must be disabled)')
            end
        end
    end
end
function M.Shutdown(gm) owners[gm]=nil end
return M
