-- Monster-side stage machine for the capture sequence, driven from BTT_HTCatch's tick.
-- The manager owns all timing and rules; this file only moves the monster, picks and
-- claims a prison post, and reports arrival. Nothing here decides gameplay outcomes.
local H = UGCGameSystem.UGCRequire('Script.AI.HeadTeacher.HTCommon')
local Service = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureService')
local C = {}

local function gm()
    local ok, mode = pcall(function() return UGCGameSystem.GetGameMode() end)
    if not (ok and H.valid(mode)) then return nil end
    return mode
end

local function trace(p, target, text)
    -- Diagnostics must never abort a phase transition: H.snapshot is evaluated for
    -- every traceEvent call regardless of the M.TRACE switch.
    if not H.TRACE then return end
    local ok, snapshot = pcall(function() return H.snapshot(p, target) end)
    H.traceEvent(text .. (ok and (' ' .. snapshot) or ' snapshot=unavailable'))
end

-- returns started, reason
function C.begin(p, target)
    if not p:HasAuthority() then return false, 'NOT_AUTHORITY' end
    local mode = gm()
    if not mode then return false, 'NO_GAMEMODE' end
    local d = H.data(p)
    if d.capture then return false, 'ALREADY_CAPTURING' end
    local started, detail = Service.StartCapture(mode, p, target)
    if not started then return false, detail end
    d.capture = {id = detail, elapsed = 0, claimTried = 0}
    H.stop(p)
    trace(p, target, string.format('capture_begin session=%s', tostring(detail)))
    return true, detail
end

-- Escort movement. Re-uses H.moveTick so the anti-stutter cadence measured in
-- recipes/chase-moveto-stutter.md applies to the carried target too.
local function escort(task, p, mode, cap, snap, dt)
    if not snap.PostId then
        local from = p:K2_GetActorLocation()
        local candidates = Service.NearestFreePosts(mode, {X = from.X, Y = from.Y, Z = from.Z}, 4)
        if #candidates == 0 then
            cap.claimTried = cap.claimTried + 1
            if cap.claimTried % 20 == 1 then
                H.log(p, 'capture-claim', 'No free prison post; keep escorting until timeout')
            end
            return
        end
        for _, candidate in ipairs(candidates) do
            local ok = Service.ClaimPost(mode, cap.id, candidate.PostId)
            if ok then
                H.traceEvent(string.format('capture_claim session=%d post=%s dist=%.0f',
                    cap.id, tostring(candidate.PostId), candidate.Distance))
                return
            end
        end
        return
    end
    local post = Service.PostById(mode, snap.PostId)
    if not post then
        H.log(p, 'capture-post', 'Claimed post ' .. tostring(snap.PostId) .. ' is gone; re-picking')
        return
    end
    local target = post.location
    H.moveTick(task, p, target, H.config(p, 'HTEscortSpeed'), dt)
    local here = p:K2_GetActorLocation()
    local gap = H.distance({X = here.X, Y = here.Y, Z = target.Z}, target)
    if gap <= H.config(p, 'HTArriveRadius') then
        local ok, detail = Service.MarkArrived(mode, cap.id)
        H.traceEvent(string.format('capture_arrive session=%d post=%s gap=%.0f ok=%s %s',
            cap.id, tostring(snap.PostId), gap, tostring(ok), tostring(detail)))
    end
end

-- returns finished, reason
function C.update(task, p, dt)
    local d = H.data(p)
    local cap = d.capture
    if not cap then return true, 'NO_CAPTURE' end
    local mode = gm()
    if not mode then
        -- The handle belongs to this pawn: leaving it set would make the monster refuse
        -- every later catch with ALREADY_CAPTURING while nothing drives the session.
        d.capture = nil
        return true, 'NO_GAMEMODE'
    end
    local snap = Service.Snapshot(mode, cap.id)
    if not snap then
        d.capture = nil
        return true, 'SESSION_GONE'
    end
    local state = snap.State
    if state == 'Grabbing' then
        H.stop(p)
        return false
    elseif state == 'Carrying' then
        escort(task, p, mode, cap, snap, dt)
        return false
    elseif state == 'PuttingDown' then
        H.stop(p)
        return false
    elseif state == 'Imprisoned' then
        d.capture = nil
        trace(p, nil, string.format('capture_done session=%d post=%s',
            cap.id, tostring(snap.PostId)))
        return true, 'IMPRISONED'
    end
    d.capture = nil
    trace(p, nil, string.format('capture_end session=%d state=%s reason=%s',
        cap.id, tostring(state), tostring(snap.Reason)))
    return true, tostring(snap.Reason or state)
end

-- BT abort or actor teardown. A player who is already bound belongs to the post, not
-- to this monster: releasing them here would silently skip the whole imprisonment.
function C.cancel(p, reason)
    local d = p.HTRuntime
    local cap = d and d.capture
    if not cap then return false end
    d.capture = nil
    local mode = gm()
    if not mode then return false end
    local snap = Service.Snapshot(mode, cap.id)
    if snap and snap.State == 'Imprisoned' then
        H.traceEvent(string.format('capture_keep_bound session=%d monster_gone=%s',
            cap.id, tostring(reason)))
        return false
    end
    local ok, detail = Service.CancelMonster(mode, p, reason or 'MONSTER_DESTROYED')
    H.traceEvent(string.format('capture_cancel session=%d ok=%s %s',
        cap.id, tostring(ok), tostring(detail)))
    return ok
end

function C.active(p)
    local d = p.HTRuntime
    return d and d.capture and d.capture.id or nil
end

return C
