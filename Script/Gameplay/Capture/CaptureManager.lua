-- Server-owned capture/carry/imprison state machine. Engine access is injected and
-- callbacks run after commit, so every rule here is testable offline (see
-- Tests/capture_test.txt). Same contract as DeskSearchManager: no engine call, no
-- global state, and a consumer may re-enter from the emit callback.
local Manager = {}
Manager.__index = Manager

function Manager.new(deps, config)
    assert(deps and deps.now and deps.validatePlayer and deps.validateRescuer and deps.emit,
        'capture manager needs now/validatePlayer/validateRescuer/emit')
    assert(config and config.Check and config.Defaults, 'capture manager needs config')
    return setmetatable({
        deps = deps, config = config,
        posts = {}, sessions = {},
        byPlayer = {}, byMonster = {}, byPostActor = {},
        serial = 0, revision = 0, events = {},
    }, Manager)
end

local function value(s, key)
    local v = s[key]
    if v == nil then return nil end
    return v
end

local function option(self, options, key)
    local v = value(options or {}, key)
    if v == nil then return self.config.Defaults[key] end
    return v
end

local function finite(v)
    return type(v) == 'number' and v == v and math.abs(v) < math.huge
end

local function distance(a, b)
    local x, y, z = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(x * x + y * y + z * z)
end

local function snapshot(s)
    return {
        SessionId = s.id, PlayerKey = s.player,
        PostId = s.post and s.post.id or nil,
        State = s.state, Reason = s.reason, Revision = s.revision,
        StartedAt = s.startedAt, EscortDeadline = s.deadline,
        StruggleReady = s.ready == true, StruggleExpiresAt = s.unlockAt,
        Struggle = s.struggle, StruggleNeed = s.strugglePresses,
        StruggleInterval = s.struggleInterval,
        RescuerKey = s.rescuer, RescueEndsAt = s.rescueEndsAt,
        RescueDuration = s.rescueDuration, RescueRadius = s.rescueRadius,
        ArrivedAt = s.arrivedAt, PutDownUntil = s.putUntil,
        -- The engine adapter needs the socket on every transition, not only at start.
        CarrySocket = s.carrySocket,
        -- Released must know whether the player was ever actually bound: an escort that
        -- failed halfway releases the player where they stand, not at the post.
        WasBound = s.bound == true,
    }
end

function Manager:snapshotFor(s)
    if not s then return nil end
    return snapshot(s)
end

-- Detach the queue before dispatch: an emit callback may release or claim another
-- session, and re-iterating a growing table would skip or repeat events.
function Manager:FlushEvents()
    local events = self.events
    self.events = {}
    for _, e in ipairs(events) do
        local ok, err = pcall(self.deps.emit, e.data, e.kind, e.reason, e.post, e.monster)
        if not ok and self.deps.log then self.deps.log('capture emit failed: ' .. tostring(err)) end
    end
end

function Manager:publish(s, kind, reason)
    self.revision = self.revision + 1
    s.revision = self.revision
    if reason then s.reason = reason end
    self.events[#self.events + 1] = {
        data = snapshot(s), kind = kind, reason = reason,
        post = s.post, monster = s.monster,
    }
end

-- ---------------------------------------------------------------- posts

function Manager:RegisterPost(actor, id, options)
    if actor == nil or id == nil or id == '' then return false, 'INVALID_POST' end
    if self.posts[id] or self.byPostActor[actor] then return false, 'DUPLICATE_POST' end
    local location = (options or {}).Location
    if type(location) ~= 'table' or not finite(location.X) or not finite(location.Y)
        or not finite(location.Z) then
        return false, 'POST_LOCATION_REQUIRED'
    end
    local rescueRadius = (options or {}).RescueRadius
    local rescueDuration = (options or {}).RescueDuration
    local presses = (options or {}).StrugglePresses
    -- Values the post does not configure stay nil: they must not overwrite the
    -- session's own options with a module-level default at registration time.
    if rescueRadius ~= nil and (not finite(rescueRadius) or rescueRadius <= 0) then
        return false, 'INVALID_RESCUE_RADIUS'
    end
    if rescueDuration ~= nil and (not finite(rescueDuration) or rescueDuration <= 0) then
        return false, 'INVALID_RESCUE_DURATION'
    end
    if presses ~= nil and (type(presses) ~= 'number' or presses < 1 or presses ~= math.floor(presses)) then
        return false, 'INVALID_STRUGGLE_PRESSES'
    end
    local post = {
        id = id, actor = actor, location = {X = location.X, Y = location.Y, Z = location.Z},
        rescueRadius = rescueRadius, rescueDuration = rescueDuration,
        strugglePresses = presses, session = nil,
    }
    self.posts[id] = post
    self.byPostActor[actor] = post
    return true, post.id
end

function Manager:FindPost(actor)
    return self.byPostActor[actor]
end

function Manager:UnregisterPost(actor)
    local post = self.byPostActor[actor]
    if not post then return false, 'UNKNOWN_POST' end
    local released
    if post.session then
        released = post.session
        self:Release(released, 'POST_REMOVED')
    end
    self.byPostActor[actor] = nil
    self.posts[post.id] = nil
    return true, post.id, released
end

function Manager:PostCount()
    local n = 0
    for _ in pairs(self.posts) do n = n + 1 end
    return n
end

-- Nearest free posts first. The caller (monster escort step) claims one of these;
-- returning the ordered list instead of a single post lets it try the next candidate
-- when the escort step cannot reach the one it holds (reachability is judged by the
-- caller: the manager only knows time and occupancy).
function Manager:NearestFreePosts(fromVec, limit)
    if type(fromVec) ~= 'table' or not finite(fromVec.X) or not finite(fromVec.Y)
        or not finite(fromVec.Z) then
        return {}, 'INVALID_POSITION'
    end
    local list = {}
    for _, post in pairs(self.posts) do
        if not post.session then
            list[#list + 1] = {
                PostId = post.id, Post = post,
                Distance = distance(fromVec, post.location),
                Location = post.location,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.Distance == b.Distance then return tostring(a.PostId) < tostring(b.PostId) end
        return a.Distance < b.Distance
    end)
    if limit and limit > 0 then
        for i = #list, (limit + 1), -1 do list[i] = nil end
    end
    return list
end

-- ---------------------------------------------------------------- sessions

function Manager:StartSession(playerKey, monster, options, postOptions)
    if type(playerKey) ~= 'number' or playerKey < 0 then return false, 'INVALID_PLAYER' end
    if monster == nil then return false, 'INVALID_MONSTER' end
    if self.byPlayer[playerKey] then return false, 'PLAYER_BUSY' end
    if self.byMonster[monster] then return false, 'MONSTER_BUSY' end
    if self:PostCount() == 0 then return false, 'NO_POST' end
    local ok, detail = self.config.Check(options)
    if not ok then return false, 'INVALID_CONFIG:' .. tostring(detail) end
    local valid, reason = self.deps.validatePlayer(playerKey)
    if not valid then return false, reason or 'PLAYER_UNAVAILABLE' end
    local now = self.deps.now()
    self.serial = self.serial + 1
    local s = {
        id = self.serial, player = playerKey, monster = monster, options = options,
        postOptions = postOptions, state = 'Grabbing', revision = 0,
        startedAt = now, grabUntil = now + option(self, options, 'PickupDuration'),
        arrived = false, arrivedAt = nil, struggle = 0, ready = false,
        lastPressAt = nil, rescueStartsAt = nil, rescueEndsAt = nil, rescuer = nil,
        post = nil,
        rescueRadius = option(self, postOptions, 'RescueRadius'),
        rescueDuration = option(self, postOptions, 'RescueDuration'),
        strugglePresses = option(self, postOptions, 'StrugglePresses'),
        struggleInterval = option(self, options, 'StruggleInterval'),
        carrySocket = option(self, options, 'CarrySocket'),
    }
    self.sessions[self.serial] = s
    self.byPlayer[playerKey] = self.serial
    self.byMonster[monster] = self.serial
    self:publish(s, 'SessionStarted')
    return true, s.id, now
end

function Manager:GetSession(id)
    return self.sessions[id]
end

function Manager:GetSnapshot(sessionId)
    local s = self.sessions[sessionId]
    if not s then return nil end
    return snapshot(s)
end

function Manager:SessionOfPlayer(playerKey)
    local id = self.byPlayer[playerKey]
    if not id then return nil end
    return self.sessions[id]
end

function Manager:SessionOfMonster(monster)
    local id = self.byMonster[monster]
    if not id then return nil end
    return self.sessions[id]
end

-- Used by the AI lock step so a carried or imprisoned player is not re-targeted.
function Manager:IsBusy(playerKey)
    return self.byPlayer[playerKey] ~= nil
end

function Manager:BusyPlayerKeys()
    local keys = {}
    for key in pairs(self.byPlayer) do keys[key] = true end
    return keys
end

function Manager:ClaimPost(sessionId, postId)
    local s = self.sessions[sessionId]
    if not s then return false, 'UNKNOWN_SESSION' end
    if s.state ~= 'Carrying' and s.state ~= 'Grabbing' then return false, 'WRONG_STATE' end
    local post = self.posts[postId]
    if not post then return false, 'UNKNOWN_POST' end
    if post.session and post.session ~= s.id then return false, 'POST_BUSY' end
    if s.post == post then return true, post.id end
    if s.post then s.post.session = nil end
    s.post = post
    post.session = s.id
    -- Per-post tuning only becomes known at claim time; only values the post actually
    -- configured override what the caller passed for this session.
    if post.rescueRadius then s.rescueRadius = post.rescueRadius end
    if post.rescueDuration then s.rescueDuration = post.rescueDuration end
    if post.strugglePresses then s.strugglePresses = post.strugglePresses end
    self:publish(s, 'PostClaimed')
    return true, post.id
end

function Manager:ReleasePost(sessionId)
    local s = self.sessions[sessionId]
    if not s then return false, 'UNKNOWN_SESSION' end
    if s.post then s.post.session = nil end
    s.post = nil
    self:publish(s, 'PostReleased')
    return true
end

-- The escort leg reports arrival; the transition itself still happens in Update so
-- that PutDownDuration is measured on the server clock, not on the caller's frame.
function Manager:MarkArrived(sessionId)
    local s = self.sessions[sessionId]
    if not s then return false, 'UNKNOWN_SESSION' end
    if s.state ~= 'Carrying' then return false, 'WRONG_STATE' end
    if not s.post then return false, 'NO_POST_CLAIMED' end
    if s.arrived then return true end
    s.arrived = true
    s.arrivedAt = self.deps.now()
    self:publish(s, 'Arrived')
    return true
end

local function clear(self, s)
    if s.post then
        if s.post.session == s.id then s.post.session = nil end
        s.post = nil
    end
    self.sessions[s.id] = nil
    if self.byPlayer[s.player] == s.id then self.byPlayer[s.player] = nil end
    if self.byMonster[s.monster] == s.id then self.byMonster[s.monster] = nil end
end

function Manager:Release(sessionId, reason)
    local s = self.sessions[sessionId]
    if not s then return false, 'UNKNOWN_SESSION' end
    if s.state == 'Released' then return false, 'ALREADY_RELEASED' end
    s.state = 'Released'
    self:publish(s, 'Released', reason or 'CANCELLED')
    clear(self, s)
    return true
end

function Manager:CancelPlayer(playerKey, reason)
    local s = self:SessionOfPlayer(playerKey)
    if not s then return false, 'NO_SESSION' end
    return self:Release(s.id, reason or 'PLAYER_UNAVAILABLE')
end

function Manager:CancelMonster(monster, reason)
    local s = self:SessionOfMonster(monster)
    if not s then return false, 'NO_SESSION' end
    return self:Release(s.id, reason or 'MONSTER_DESTROYED')
end

-- ---------------------------------------------------------------- struggle / rescue

function Manager:RegisterStruggle(playerKey)
    local s = self:SessionOfPlayer(playerKey)
    if not s then return false, 'NO_SESSION' end
    if s.state ~= 'Imprisoned' then return false, 'WRONG_STATE' end
    local now = self.deps.now()
    if not s.ready then return false, 'NOT_YET' end
    if s.lastPressAt and (now - s.lastPressAt) < s.struggleInterval then
        return false, 'TOO_FAST'
    end
    s.lastPressAt = now
    s.struggle = s.struggle + 1
    self:publish(s, 'Struggle')
    if s.struggle >= s.strugglePresses then
        self:Release(s.id, 'BROKE_FREE')
        return true, s.strugglePresses, s.strugglePresses
    end
    return true, s.struggle, s.strugglePresses
end

function Manager:StartRescue(playerKey, rescuerKey)
    local s = self:SessionOfPlayer(playerKey)
    if not s then return false, 'NO_SESSION' end
    if s.state ~= 'Imprisoned' then return false, 'WRONG_STATE' end
    if type(rescuerKey) ~= 'number' or rescuerKey < 0 then return false, 'INVALID_PLAYER' end
    if rescuerKey == s.player then return false, 'SELF_RESCUE' end
    if self:IsBusy(rescuerKey) then return false, 'RESCUER_BUSY' end
    local now = self.deps.now()
    if s.rescuer == rescuerKey and s.rescueEndsAt and now < s.rescueEndsAt then
        return true, s.rescueEndsAt - now
    end
    if s.rescuer and s.rescuer ~= rescuerKey then return false, 'RESCUE_IN_PROGRESS' end
    local valid, reason = self.deps.validateRescuer(s.post, rescuerKey, s.rescueRadius)
    if not valid then return false, reason or 'RESCUER_INVALID' end
    s.rescuer = rescuerKey
    s.rescueStartsAt = now
    s.rescueEndsAt = now + s.rescueDuration
    self:publish(s, 'RescueStarted')
    return true, s.rescueDuration
end

function Manager:CancelRescue(playerKey, reason)
    local s = self:SessionOfPlayer(playerKey)
    if not s then return false, 'NO_SESSION' end
    if not s.rescuer then return false, 'NOT_RESCUING' end
    s.rescuer = nil
    s.rescueStartsAt = nil
    s.rescueEndsAt = nil
    self:publish(s, 'RescueCancelled', reason)
    return true
end

-- ---------------------------------------------------------------- clock

function Manager:_enter(s, state, now)
    s.state = state
    if state == 'Carrying' then
        -- The escort deadline counts from the moment the monster can actually move,
        -- so the pickup phase does not eat into it.
        s.carryingSince = now
        s.deadline = now + option(self, s.options, 'EscortTimeout')
    elseif state == 'PuttingDown' then
        s.putUntil = now + option(self, s.options, 'PutDownDuration')
    elseif state == 'Imprisoned' then
        s.unlockAt = now + option(self, s.options, 'ImprisonDuration')
        s.struggle, s.ready, s.lastPressAt = 0, false, nil
        s.bound = true
        -- The carrier is finished with this session and goes back to patrolling, so it
        -- must be able to catch somebody else while this player is still held at the
        -- post. The session keeps its monster reference so the eventual release can
        -- still clear that monster's replicated state.
        if self.byMonster[s.monster] == s.id then self.byMonster[s.monster] = nil end
    end
    self:publish(s, state)
end

function Manager:Update()
    local now = self.deps.now()
    -- Collect first: Release mutates self.sessions during iteration.
    local ids = {}
    for id in pairs(self.sessions) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local s = self.sessions[id]
        if s then
            -- The captured player can leave the round in any phase, so the liveness
            -- check runs before every transition instead of per state.
            local valid, reason = self.deps.validatePlayer(s.player)
            if not valid then
                self:Release(id, reason or 'PLAYER_UNAVAILABLE')
            elseif s.state == 'Grabbing' then
                if now >= s.grabUntil then self:_enter(s, 'Carrying', now) end
            elseif s.state == 'Carrying' then
                if s.arrived and s.post then
                    self:_enter(s, 'PuttingDown', now)
                elseif now >= s.deadline then
                    self:Release(id, s.post and 'ESCORT_TIMEOUT' or 'NO_POST')
                end
            elseif s.state == 'PuttingDown' then
                if now >= s.putUntil then self:_enter(s, 'Imprisoned', now) end
            elseif s.state == 'Imprisoned' then
                if not s.ready and now >= s.unlockAt then
                    s.ready = true
                    self:publish(s, 'StruggleReady')
                end
                if s.rescuer and s.post then
                    local ok, why = self.deps.validateRescuer(s.post, s.rescuer, s.rescueRadius)
                    if not ok then
                        self:CancelRescue(s.player, why or 'RESCUER_LEFT')
                    elseif now >= s.rescueEndsAt then
                        self:Release(id, 'RESCUED')
                    end
                end
            end
        end
    end
    self:FlushEvents()
end

function Manager:ReleaseAll(reason)
    local ids = {}
    for id in pairs(self.sessions) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do self:Release(id, reason or 'SERVER_SHUTDOWN') end
    self:FlushEvents()
    return #ids
end

return Manager
