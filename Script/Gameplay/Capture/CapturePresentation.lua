-- Client-only side of capture/imprison. The captured player attaches their OWN pawn
-- to the carrier: measured 2026-10-26 that a server-only attach keeps the server's
-- copy in place while the player's own screen stays where they were standing.
-- No gameplay decision happens here; the server state is the only input.
local Camera = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureCamera')
local StruggleUI = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.StrugglePresentation')
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureConfig')
local P = {}

local LOG = '[HTCapture]'
local function log(t) ugcprint(LOG .. ' client ' .. tostring(t)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local holding = nil          -- {actor = carrier, kind = 'carry'|'bind'}
local applied = {}           -- actor -> highest revision consumed
local appliedSession = {}    -- actor -> session that produced it
local carryAnimations = {} -- carrier -> {pawn, mesh, previous animation mode}
-- Visibility: do NOT hide the captured player during grab/carry (user request 2026-11-06).
-- Collision: carried pawn capsule overlaps the carrier body once offsets hang them on-side;
-- mutual IgnoreActorWhenMoving + NoCollision on the pawn capsule stops the carrier from jittering.

local function setMoveIgnore(comp, actor, ignore)
    if not (valid(comp) and valid(actor)) then return end
    pcall(function() return comp:IgnoreActorWhenMoving(actor, ignore == true) end)
end

local function applyCarryCollision(pawn, carrier, enable)
    if not valid(pawn) then return end
    if enable then
        if not valid(carrier) then return end
        local saved = holding and holding.collision
        if not saved then
            local enabled = 3
            pcall(function()
                if valid(pawn.CapsuleComponent) then
                    enabled = pawn.CapsuleComponent:GetCollisionEnabled()
                end
            end)
            if holding then holding.collision = {carrier = carrier, capsuleEnabled = enabled} end
        elseif holding then
            holding.collision.carrier = carrier
        end
        setMoveIgnore(pawn.CapsuleComponent, carrier, true)
        setMoveIgnore(carrier.CapsuleComponent, pawn, true)
        if valid(carrier.HitBox) then setMoveIgnore(carrier.HitBox, pawn, true) end
        pcall(function()
            if valid(pawn.CapsuleComponent) then
                pawn.CapsuleComponent:SetCollisionEnabled(0) -- NoCollision
            end
        end)
    else
        local saved = holding and holding.collision
        local c = carrier or (saved and saved.carrier)
        if valid(c) and valid(pawn) then
            setMoveIgnore(pawn.CapsuleComponent, c, false)
            setMoveIgnore(c.CapsuleComponent, pawn, false)
            if valid(c.HitBox) then setMoveIgnore(c.HitBox, pawn, false) end
        end
        local restore = (saved and saved.capsuleEnabled) or 3
        pcall(function()
            if valid(pawn.CapsuleComponent) then
                pawn.CapsuleComponent:SetCollisionEnabled(restore)
            end
        end)
        if holding then holding.collision = nil end
    end
end

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

local function pawnOf(key)
    if type(key) ~= 'number' or key < 0 then return nil end
    local ok, pawn = pcall(function() return UGCGameSystem.GetPlayerPawnByPlayerKey(key) end)
    if not (ok and valid(pawn)) then return nil end
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


local function stopCarryAnimation(carrier)
    local saved = carryAnimations[carrier]
    if not saved then return end
    carryAnimations[carrier] = nil
    if valid(saved.mesh) then
        local ok, err = pcall(function()
            saved.mesh:Stop()
            saved.mesh:SetAnimationMode(saved.mode)
        end)
        if not ok then log('restore carry animation failed: ' .. tostring(err)) end
    end
end

local function startCarryAnimation(carrier, pawn)
    local current = carryAnimations[carrier]
    if current and current.pawn == pawn then return end
    stopCarryAnimation(carrier)
    if not (valid(pawn) and valid(pawn.Mesh)) then
        log('cannot play carry animation: player mesh unavailable')
        return
    end
    local mesh = pawn.Mesh
    local ok, err = pcall(function()
        local path = UGCGameSystem.GetUGCResourcesFullPath(Config.CarryPresentation.AnimationPath)
        local anim = UGCObjectUtility.LoadObject(path)
        if not valid(anim) then error('animation unavailable: ' .. tostring(path)) end
        local mode = mesh:GetAnimationMode()
        mesh:PlayAnimation(anim, Config.CarryPresentation.Loop)
        carryAnimations[carrier] = {pawn = pawn, mesh = mesh, mode = mode}
    end)
    if not ok then log('carry animation failed: ' .. tostring(err)) end
end

local function release(keep)
    if not holding or (keep and holding.actor == keep) then return end
    -- Release the pawn we acquired; a respawn may already have replaced localPawn().
    local pawn = holding.pawn
    if valid(pawn) then
        applyCarryCollision(pawn, holding.actor, false)
        pcall(function() return pawn:K2_DetachFromActor(2, 2, 2) end)
        -- restore local prediction only once the attach is gone
        pcall(function()
            pawn.CharacterMovement:SetMovementMode(1) -- Walking
            pawn.CharacterMovement:SetComponentTickEnabled(holding.movementTick)
        end)
        log('detached from ' .. tostring(holding.kind))
    end
    holding = nil
end

local function grab(actor, kind, socketName, state)
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
        if ok then
            local ox = state and state.CarryOffsetX
            local oy = state and state.CarryOffsetY
            local oz = state and state.CarryOffsetZ
            local op = state and state.CarryOffsetPitch
            local oya = state and state.CarryOffsetYaw
            local orl = state and state.CarryOffsetRoll
            if type(ox) ~= 'number' then ox = actor.HTCarryOffsetX end
            if type(oy) ~= 'number' then oy = actor.HTCarryOffsetY end
            if type(oz) ~= 'number' then oz = actor.HTCarryOffsetZ end
            if type(op) ~= 'number' then op = actor.HTCarryOffsetPitch end
            if type(oya) ~= 'number' then oya = actor.HTCarryOffsetYaw end
            if type(orl) ~= 'number' then orl = actor.HTCarryOffsetRoll end
            ox = tonumber(ox) or 0; oy = tonumber(oy) or 0; oz = tonumber(oz) or 0
            op = tonumber(op) or 0; oya = tonumber(oya) or 0; orl = tonumber(orl) or 0
            ok, err = pcall(function()
                return pawn:K2_SetActorRelativeLocation({X = ox, Y = oy, Z = oz}, false, {}, true)
            end)
            if ok and (op ~= 0 or oya ~= 0 or orl ~= 0) then
                ok, err = pcall(function()
                    return pawn:K2_SetActorRelativeRotation(
                        {Pitch = op, Yaw = oya, Roll = orl}, false, {}, true)
                end)
            end
        end
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
    holding = {actor = actor, kind = kind, pawn = pawn,
        movementTick = pawn.CharacterMovement:IsComponentTickEnabled()}
    -- None stops locomotion, but native movement Tick still corrected the attached
    -- pawn's relative position. Suspend it for the hold and restore the saved state.
    pawn.CharacterMovement:SetMovementMode(0) -- MOVE_None
    pawn.CharacterMovement:SetComponentTickEnabled(false)
    if kind == 'carry' then
        applyCarryCollision(pawn, actor, true)
    end
    log('attached local pawn to ' .. kind)
end

-- Called from TheHeadTeacher:OnRep_HTCaptureState on every client.
function P.Carrier(actor, state)
    if not valid(actor) then return end
    if not accepts(actor, state) then return end
    local stage = state and (state.Stage or state.State)
    if stage == 'Grabbing' then
        stopCarryAnimation(actor)
        -- Keep the player visible for the whole grab/carry (no SetActorHiddenInGame).
    elseif stage == 'Carrying' or stage == 'PuttingDown' then
        local pawn = pawnOf(state.PlayerKey)
        if pawn then startCarryAnimation(actor, pawn) end
    else
        stopCarryAnimation(actor)
    end
    if wants(state, {'Grabbing', 'Carrying', 'PuttingDown'}) then
        Camera.Start(actor, 'carry')
    else
        Camera.Stop(actor)
    end
    if wants(state, {'Carrying', 'PuttingDown'}) then
        grab(actor, 'carry', state.CarrySocket, state)
    elseif holding and holding.actor == actor then
        release(nil)
    end
end

-- Called from BP_PrisonPost:OnRep_PrisonState on every client.
function P.Bind(actor, state)
    if not valid(actor) then return end
    if not accepts(actor, state) then return end
    StruggleUI.Update(actor, state)
    if wants(state, {'Imprisoned'}) then
        Camera.Start(actor, 'bind')
        grab(actor, 'bind', nil, state)
    elseif holding and holding.actor == actor then
        Camera.Stop(actor)
        release(nil)
    else
        Camera.Stop(actor)
    end
end

function P.End(actor)
    StruggleUI.End(actor)
    Camera.Stop(actor)
    stopCarryAnimation(actor)
    if holding and holding.actor == actor then release(nil) end
    applied[actor] = nil
end

-- Kept for call-site compatibility. Hiding the captured player was removed
-- (2026-11-06): only force-visible when asked to show; never hide.
function P.SetConcealed(pawn, hidden)
    if not valid(pawn) then return end
    if hidden then return end
    pcall(function() return pawn:SetActorHiddenInGame(false) end)
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
