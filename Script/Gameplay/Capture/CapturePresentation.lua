-- Client-only side of capture/imprison. The captured player attaches their OWN pawn
-- to the carrier: measured 2026-10-26 that a server-only attach keeps the server's
-- copy in place while the player's own screen stays where they were standing.
-- No gameplay decision happens here; the server state is the only input.
local P = {}

local LOG = '[HTCapture]'
local function log(t) ugcprint(LOG .. ' client ' .. tostring(t)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local holding = nil          -- {actor = carrier, kind = 'carry'|'bind'}
local applied = {}           -- actor -> highest revision consumed
local appliedSession = {}    -- actor -> session that produced it

-- Replication can hand us a payload that is older than what we already acted on. The
-- revision counter is server-session scoped, however: a rebuilt service starts over at 1
-- (and did so while these clients still remembered 99), so a new SessionId always wins
-- over the per-actor high-water mark.
local function accepts(actor, state)
    local revision = state and state.Revision
    if type(revision) ~= 'number' then return state ~= nil end
    local last = applied[actor]
    local isNewSession = state.SessionId ~= nil and state.SessionId ~= appliedSession[actor]
    if type(last) == 'number' and revision <= last and not isNewSession then
        log('ignore revision ' .. tostring(revision) .. ' (already at ' .. tostring(last) .. ')')
        return false
    end
    applied[actor] = revision
    appliedSession[actor] = state.SessionId
    return true
end

local function localKey()
    local ok, pc = pcall(function() return UGCGameSystem.GetLocalPlayerController() end)
    if not (ok and valid(pc)) then return -1 end
    local okKey, key = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerController(pc) end)
    if not (okKey and type(key) == 'number') then return -1 end
    return key
end

local function localPawn()
    local ok, pc = pcall(function() return UGCGameSystem.GetLocalPlayerController() end)
    if not (ok and valid(pc)) then return nil end
    local okPawn, pawn = pcall(function() return pc:K2_GetPawn() end)
    if not (okPawn and valid(pawn)) then return nil end
    return pawn
end

-- Does this replicated state name the local player and ask them to be held here?
-- No caching: OnRep already fires only when the synced table changed.
local function wants(state, stages)
    if not state then return false end
    if type(state.PlayerKey) ~= 'number' or state.PlayerKey ~= localKey() then return false end
    local name = state.Stage or state.State
    if type(stages) ~= 'table' then stages = {stages} end
    for _, want in ipairs(stages) do if name == want then return true end end
    return false
end

local function release(keep)
    if not holding or (keep and holding.actor == keep) then return end
    local pawn = localPawn()
    if pawn then
        pcall(function() return pawn:K2_DetachFromActor(2, 2, 2) end)
        log('detached from ' .. tostring(holding.kind))
    end
    holding = nil
end

local function grab(actor, kind, socketName)
    if holding and holding.actor == actor and holding.kind == kind then return end
    release(nil)
    local pawn = localPawn()
    if not pawn then log('no local pawn to attach') return end
    local ok, err
    if kind == 'carry' then
        if not (valid(actor.Mesh)) then log('carrier has no mesh') return end
        ok, err = pcall(function()
            return pawn:K2_AttachToActor(actor, socketName or 'headSocket', 2, 2, 2, false)
        end)
        if ok and err == false then ok, err = false, 'carry attach returned false' end
    else
        if not valid(actor.BindPoint) then log('post has no BindPoint') return end
        ok, err = pcall(function()
            return pawn:K2_AttachToComponent(actor.BindPoint, '', 2, 2, 2, false)
        end)
        if ok and err == false then ok, err = false, 'bind attach returned false' end
        -- The server applies the same offset after binding; without it the client and
        -- the authoritative copy disagree by the bind height.
        if ok then
            local offset = actor.BindHeightOffset
            if type(offset) == 'number' and offset ~= 0 then
                ok, err = pcall(function()
                    return pawn:K2_SetActorRelativeLocation({X = 0, Y = 0, Z = offset}, false, {}, true)
                end)
            end
        end
    end
    if not ok then
        pcall(function() return pawn:K2_DetachFromActor(2, 2, 2) end)
        log('local attach failed: ' .. tostring(err))
        return
    end
    holding = {actor = actor, kind = kind}
    log('attached local pawn to ' .. kind)
end

-- Called from TheHeadTeacher:OnRep_HTCaptureState on every client.
function P.Carrier(actor, state)
    if not valid(actor) then return end
    if not accepts(actor, state) then return end
    if wants(state, {'Carrying', 'PuttingDown'}) then
        grab(actor, 'carry', state.CarrySocket)
    elseif holding and holding.actor == actor then
        release(nil)
    end
end

-- Called from BP_PrisonPost:OnRep_PrisonState on every client.
function P.Bind(actor, state)
    if not valid(actor) then return end
    if not accepts(actor, state) then return end
    if wants(state, {'Imprisoned'}) then
        grab(actor, 'bind', nil)
    elseif holding and holding.actor == actor then
        release(nil)
    end
end

function P.End(actor)
    if holding and holding.actor == actor then release(nil) end
    applied[actor] = nil
end

-- Used by presentation tests and by the debug log line only.
function P.DebugState(state)
    if not state then return 'nil' end
    return string.format('player=%s stage=%s/%s rev=%s struggle=%s/%s ready=%s rescuer=%s',
        tostring(state.PlayerKey), tostring(state.Stage), tostring(state.State),
        tostring(state.Revision), tostring(state.Struggle), tostring(state.StruggleNeed),
        tostring(state.StruggleReady), tostring(state.RescuerKey))
end

return P
