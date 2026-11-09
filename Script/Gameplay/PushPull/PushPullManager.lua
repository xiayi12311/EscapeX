-- Pure PushPull state machine. This module performs no engine calls so grip resolution,
-- input arbitration and force composition can be exercised without a PIE session.
local M = {}

local FACES = {
    [0] = {normalX = 1, normalY = 0, tangentX = 0, tangentY = 1, yaw = 180},  -- Front
    [1] = {normalX = 0, normalY = 1, tangentX = 1, tangentY = 0, yaw = -90},  -- Right
    [2] = {normalX = -1, normalY = 0, tangentX = 0, tangentY = -1, yaw = 0},  -- Back
    [3] = {normalX = 0, normalY = -1, tangentX = -1, tangentY = 0, yaw = 90}, -- Left
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function sinCos(yawDegrees)
    local radians = (yawDegrees or 0) * math.pi / 180
    return math.sin(radians), math.cos(radians)
end

local function worldToLocal(dx, dy, yaw)
    local s, c = sinCos(yaw)
    return dx * c + dy * s, -dx * s + dy * c
end

local function localToWorld(x, y, yaw)
    local s, c = sinCos(yaw)
    return x * c - y * s, x * s + y * c
end
local function locationOf(v)
    if type(v) == 'table' or type(v) == 'userdata' then return v.X or 0, v.Y or 0, v.Z or 0 end
    return 0, 0, 0
end

local function forwardOf(v)
    if type(v) == 'table' or type(v) == 'userdata' then return v.X or 0, v.Y or 0 end
    return 0, 0
end

local function markDirty(crate)
    crate._dirty = true
end

local function nextAnim(p)
    p.AnimRevision = (p.AnimRevision or 0) + 1
end

local function duration(self, state)
    local d = self.durations and self.durations[state]
    if type(d) ~= 'number' or d <= 0 then
        error('PushPull animation duration unavailable: ' .. tostring(state))
    end
    return d
end

local function setAnim(p, state, deadline)
    p.AnimState = state
    p._deadline = deadline
    nextAnim(p)
end

local function startAction(self, p, now, intent)
    if intent == 1 then
        setAnim(p, 'PushStart', now + duration(self, 'PushStart'))
    elseif intent == -1 then
        setAnim(p, 'PullStart', now + duration(self, 'PullStart'))
    else
        setAnim(p, 'Idle', nil)
    end
end

local function stopAction(self, p, now)
    local state = p.AnimState
    if state == 'PushStop' or state == 'PullStop' then return end
    if state == 'PushStart' or state == 'Push' then
        setAnim(p, 'PushStop', now + duration(self, 'PushStop'))
    elseif state == 'PullStart' or state == 'Pull' then
        setAnim(p, 'PullStop', now + duration(self, 'PullStop'))
    else
        setAnim(p, 'Idle', nil)
    end
end

local function gripLocal(crate, participant)
    local f = FACES[participant.FaceIndex]
    if not f then error('invalid PushPull face index: ' .. tostring(participant.FaceIndex)) end
    local hx, hy = crate.HalfExtentX, crate.HalfExtentY
    local usableHalf
    if f.normalX ~= 0 then usableHalf = hy - crate.EdgeMargin
    else usableHalf = hx - crate.EdgeMargin end
    if usableHalf <= 0 then error('PushPull EdgeMargin exceeds box face') end
    local tangentOffset = (participant.GripU * 2 - 1) * usableHalf
    local x, y
    if participant.FaceIndex == 0 then
        x, y = hx + participant.GripStandOff, tangentOffset
    elseif participant.FaceIndex == 1 then
        x, y = tangentOffset, hy + participant.GripStandOff
    elseif participant.FaceIndex == 2 then
        x, y = -hx - participant.GripStandOff, -tangentOffset
    else
        x, y = -tangentOffset, -hy - participant.GripStandOff
    end
    return x, y, 0
end

function M.Face(faceIndex)
    return FACES[faceIndex]
end

function M.GripLocal(crate, participant)
    return gripLocal(crate, participant)
end

function M.GripWorld(crate, participant)
    local x, y = gripLocal(crate, participant)
    local wx, wy = localToWorld(x, y, crate.Yaw)
    return {X = crate.X + wx, Y = crate.Y + wy, Z = crate.Z}
end

function M.BodyYaw(crate, participant)
    local f = FACES[participant.FaceIndex]
    if not f then return crate.Yaw end
    return crate.Yaw + f.yaw
end

function M.ChooseFace(crate, playerLocation, verticalBand)
    local px, py, pz = locationOf(playerLocation)
    local lx, ly = worldToLocal(px - crate.X, py - crate.Y, crate.Yaw)
    local ox = math.abs(lx) - crate.HalfExtentX
    local oy = math.abs(ly) - crate.HalfExtentY
    if ox <= 0 and oy <= 0 then return nil, 'WRONG_FACE' end
    local band = verticalBand or crate.HalfExtentZ
    if pz < crate.Z - crate.HalfExtentZ - band or pz > crate.Z + crate.HalfExtentZ + band then
        return nil, 'WRONG_FACE'
    end
    if ox > oy then
        if lx >= 0 then return 0 end
        return 2
    end
    if ly >= 0 then return 1 end
    return 3
end

function M.SurfaceDistance(crate, playerLocation)
    local px, py = locationOf(playerLocation)
    local lx, ly = worldToLocal(px - crate.X, py - crate.Y, crate.Yaw)
    local ox = math.max(0, math.abs(lx) - crate.HalfExtentX)
    local oy = math.max(0, math.abs(ly) - crate.HalfExtentY)
    return math.sqrt(ox * ox + oy * oy)
end

function M.FacingMatches(crate, playerForward, faceIndex, maxAngle)
    local f = FACES[faceIndex]
    if not f then return false end
    local fx, fy = forwardOf(playerForward)
    local mag = math.sqrt(fx * fx + fy * fy)
    if mag <= 0.0001 then return false end
    fx, fy = fx / mag, fy / mag
    local desiredX, desiredY = -f.normalX, -f.normalY
    local threshold = math.cos((maxAngle or 60) * math.pi / 180)
    return fx * desiredX + fy * desiredY >= threshold
end

local function gripAtU(crate, faceIndex, u, standOff)
    local f = FACES[faceIndex]
    local halfLength = f.normalX ~= 0 and crate.HalfExtentY or crate.HalfExtentX
    local usableHalf = halfLength - crate.EdgeMargin
    local tangentOffset = (u * 2 - 1) * usableHalf
    local x, y
    if faceIndex == 0 then
        x, y = crate.HalfExtentX + standOff, tangentOffset
    elseif faceIndex == 1 then
        x, y = tangentOffset, crate.HalfExtentY + standOff
    elseif faceIndex == 2 then
        x, y = -crate.HalfExtentX - standOff, -tangentOffset
    else
        x, y = -tangentOffset, -crate.HalfExtentY - standOff
    end
    local wx, wy = localToWorld(x, y, crate.Yaw)
    return {X = crate.X + wx, Y = crate.Y + wy, Z = crate.Z}
end

local function desiredU(crate, playerLocation, faceIndex)
    local px, py = locationOf(playerLocation)
    local lx, ly = worldToLocal(px - crate.X, py - crate.Y, crate.Yaw)
    local tangent
    if faceIndex == 0 then tangent = ly
    elseif faceIndex == 1 then tangent = lx
    elseif faceIndex == 2 then tangent = -ly
    else tangent = -lx end
    local halfLength
    if faceIndex == 0 or faceIndex == 2 then halfLength = crate.HalfExtentY
    else halfLength = crate.HalfExtentX end
    local usableHalf = halfLength - crate.EdgeMargin
    if usableHalf <= 0 then return nil, 'NO_FREE_GRIP' end
    local clamped = clamp(tangent, -usableHalf, usableHalf)
    return (clamped + usableHalf) / (2 * usableHalf)
end

local function clearance(crate, u, faceIndex, standOff, participants, minSpacing)
    local point = gripAtU(crate, faceIndex, u, standOff)
    local min2 = minSpacing * minSpacing
    for _, other in pairs(participants) do
        local op = M.GripWorld(crate, other)
        local dx, dy = point.X - op.X, point.Y - op.Y
        if dx * dx + dy * dy < min2 then return false end
    end
    return true
end

function M.ResolveGrip(crate, playerLocation, participants, config)
    local faceIndex, reason = M.ChooseFace(crate, playerLocation, config.SurfaceInteractionBand)
    if not faceIndex then return nil, reason end
    local distance = M.SurfaceDistance(crate, playerLocation)
    if distance > config.SurfaceInteractionBand then return nil, 'TOO_FAR' end
    local baseU = desiredU(crate, playerLocation, faceIndex)
    if not baseU then return nil, 'NO_FREE_GRIP' end
    local standOff = config.GripStandOff
    if clearance(crate, baseU, faceIndex, standOff, participants, config.MinGripSpacing) then
        return {FaceIndex = faceIndex, GripU = baseU, GripStandOff = standOff}
    end
    local halfLength
    if faceIndex == 0 or faceIndex == 2 then halfLength = crate.HalfExtentY
    else halfLength = crate.HalfExtentX end
    local usableHalf = halfLength - crate.EdgeMargin
    if usableHalf <= 0 then return nil, 'NO_FREE_GRIP' end
    local maxSteps = math.floor((config.AutoSpreadMax + 0.0001) / config.AutoSpreadStep)
    for step = 1, maxSteps do
        local delta = step * config.AutoSpreadStep / (2 * usableHalf)
        for _, sign in ipairs({-1, 1}) do
            local u = baseU + sign * delta
            if u >= 0 and u <= 1 and clearance(crate, u, faceIndex, standOff, participants, config.MinGripSpacing) then
                return {FaceIndex = faceIndex, GripU = u, GripStandOff = standOff}
            end
        end
    end
    return nil, 'NO_FREE_GRIP'
end

function M.CombineForce(participants, deadzone)
    local fx, fy = 0, 0
    for _, p in pairs(participants) do
        if p.Phase == 'Active' and (p.Intent == -1 or p.Intent == 1) then
            local f = FACES[p.FaceIndex]
            local contribution = -p.Intent
            fx = fx + f.normalX * contribution
            fy = fy + f.normalY * contribution
        end
    end
    local magnitude = math.sqrt(fx * fx + fy * fy)
    if magnitude < (deadzone or 0.15) or magnitude <= 0.0001 then
        return 0, 0, 0, magnitude
    end
    return fx / magnitude, fy / magnitude, magnitude, magnitude
end

function M.New(config, durations)
    local self = setmetatable({}, {__index = M})
    self.config = config
    self.durations = durations
    self.crates = {}
    self.players = {}
    self.nextSession = 1
    return self
end

function M:RegisterCrate(actor, crateId)
    if self.crates[actor] then return self.crates[actor] end
    local rec = {
        Actor = actor,
        CrateId = crateId,
        SessionId = self.nextSession,
        Revision = 0,
        Enabled = true,
        X = 0, Y = 0, Z = 0, Yaw = 0,
        HalfExtentX = 60, HalfExtentY = 60, HalfExtentZ = 55,
        EdgeMargin = self.config.Interaction.EdgeMargin,
        MinGripSpacing = self.config.Interaction.MinGripSpacing,
        Participants = {},
        MotionSpeed = 0,
        MotionDirX = 0,
        MotionDirY = 1,
        Blocked = false,
        _dirty = true,
    }
    self.nextSession = self.nextSession + 1
    self.crates[actor] = rec
    return rec
end

function M:FindCrate(actor)
    return self.crates[actor]
end

function M:SetCrateGeometry(actor, location, yaw, halfExtent)
    local rec = self.crates[actor]
    if not rec then return false end
    rec.X, rec.Y, rec.Z = locationOf(location)
    rec.Yaw = yaw or 0
    if halfExtent then
        rec.HalfExtentX = halfExtent.X
        rec.HalfExtentY = halfExtent.Y
        rec.HalfExtentZ = halfExtent.Z
    end
    return true
end

function M:SetCrateEnabled(actor, enabled)
    local rec = self.crates[actor]
    if not rec then return false end
    rec.Enabled = enabled == true
    markDirty(rec)
    return true
end

function M:ParticipantCount(rec)
    local count = 0
    for _ in pairs(rec.Participants) do count = count + 1 end
    return count
end

function M:RequestEntry(actor, playerKey, playerLocation, playerForward, now)
    local rec = self.crates[actor]
    if not rec then return nil, 'CRATE_DESTROYED' end
    if not rec.Enabled then return nil, 'CRATE_DISABLED' end
    if self.players[playerKey] then return nil, 'PLAYER_BUSY' end
    if self:ParticipantCount(rec) >= self.config.Interaction.MaxParticipants then
        return nil, 'NO_FREE_GRIP'
    end
    if not self.config.Interaction.AllowJoinWhileMoving and rec.MotionSpeed > self.config.Interaction.JoinMaxSpeed then
        return nil, 'WRONG_FACE'
    end
    local grip, reason = M.ResolveGrip(rec, playerLocation, rec.Participants, self.config.Interaction)
    if not grip then return nil, reason end
    local face = FACES[grip.FaceIndex]
    if not M.FacingMatches(rec, playerForward, grip.FaceIndex, self.config.Interaction.MaxFacingAngle) then
        return nil, 'WRONG_FACE'
    end
    local p = {
        PlayerKey = playerKey,
        ParticipantId = 'p' .. tostring(playerKey) .. '-' .. tostring(rec.CrateId) .. '-' .. tostring(rec.SessionId),
        FaceIndex = grip.FaceIndex,
        GripU = grip.GripU,
        GripStandOff = grip.GripStandOff,
        Phase = 'Entering',
        Intent = 0,
        AnimState = 'OnPosition',
        AnimRevision = 1,
        _deadline = now + duration(self, 'OnPosition'),
        _lastIntentAt = now,
        _startAfterIdle = false,
    }
    rec.Participants[playerKey] = p
    self.players[playerKey] = {actor = actor, participant = p}
    markDirty(rec)
    return p
end

local function removeParticipant(self, rec, playerKey)
    local p = rec.Participants[playerKey]
    if not p then return nil end
    rec.Participants[playerKey] = nil
    self.players[playerKey] = nil
    markDirty(rec)
    return p
end

function M:SetIntent(actor, playerKey, sessionId, intent, now)
    local rec = self.crates[actor]
    if not rec or rec.SessionId ~= sessionId then return false, 'STALE_REQUEST' end
    local p = rec.Participants[playerKey]
    if not p then return false, 'PLAYER_UNAVAILABLE' end
    if p.Phase == 'Releasing' then return false, 'PLAYER_UNAVAILABLE' end
    if intent ~= -1 and intent ~= 0 and intent ~= 1 then return false, 'STALE_REQUEST' end
    p._lastIntentAt = now
    if p.Intent == intent then return true end
    p.Intent = intent
    markDirty(rec)
    if p.Phase == 'Active' then
        if p.AnimState == 'Idle' then
            if intent ~= 0 then startAction(self, p, now, intent) end
        elseif p.AnimState == 'Push' or p.AnimState == 'Pull' then
            local activeIntent = p.AnimState == 'Push' and 1 or -1
            if intent ~= activeIntent then stopAction(self, p, now) end
        end
    end
    return true
end

function M:Release(actor, playerKey, sessionId, now, forced)
    local rec = self.crates[actor]
    if not rec or rec.SessionId ~= sessionId then return false, 'STALE_REQUEST' end
    local p = rec.Participants[playerKey]
    if not p then return false, 'PLAYER_UNAVAILABLE' end
    if forced then
        removeParticipant(self, rec, playerKey)
        return true
    end
    if p.Phase == 'Releasing' then return true end
    local moving = p.AnimState == 'Push' or p.AnimState == 'Pull'
        or p.AnimState == 'PushStart' or p.AnimState == 'PullStart'
        or p.AnimState == 'PushStop' or p.AnimState == 'PullStop'
    p.Intent = 0
    markDirty(rec)
    if moving then
        stopAction(self, p, now)
    else
        removeParticipant(self, rec, playerKey)
    end
    return true
end

function M:RemovePlayer(playerKey, forced)
    local owned = self.players[playerKey]
    if not owned then return nil end
    local rec = self.crates[owned.actor]
    if not rec then self.players[playerKey] = nil; return nil end
    return removeParticipant(self, rec, playerKey)
end

function M:UnregisterCrate(actor)
    local rec = self.crates[actor]
    if not rec then return {} end
    local removed = {}
    for key, p in pairs(rec.Participants) do
        self.players[key] = nil
        removed[#removed + 1] = p
    end
    rec.Participants = {}
    self.crates[actor] = nil
    return removed
end

local function updateParticipant(self, rec, p, now)
    if p.Phase == 'Active' and p.Intent ~= 0 and now - p._lastIntentAt > self.config.Input.Lease then
        p.Intent = 0
        markDirty(rec)
        if p.AnimState == 'Push' or p.AnimState == 'Pull' then stopAction(self, p, now) end
    end
    if p._startAfterIdle and p.Phase == 'Active' then
        p._startAfterIdle = false
        if p.Intent ~= 0 then startAction(self, p, now, p.Intent) end
    end
    if not p._deadline or now < p._deadline then return false end
    local state = p.AnimState
    p._deadline = nil
    if state == 'OnPosition' then
        p.Phase = 'Active'
        setAnim(p, 'Idle', nil)
        p._startAfterIdle = true
        markDirty(rec)
    elseif state == 'PushStart' then
        if p.Intent == 1 then setAnim(p, 'Push', nil)
        else stopAction(self, p, now) end
        markDirty(rec)
    elseif state == 'PullStart' then
        if p.Intent == -1 then setAnim(p, 'Pull', nil)
        else stopAction(self, p, now) end
        markDirty(rec)
    elseif state == 'PushStop' or state == 'PullStop' then
        if p.Phase == 'Releasing' then
            removeParticipant(self, rec, p.PlayerKey)
        elseif p.Intent ~= 0 then
            startAction(self, p, now, p.Intent)
            markDirty(rec)
        else
            setAnim(p, 'Idle', nil)
            markDirty(rec)
        end
    end
    return true
end

local function updateMotion(self, rec, dt)
    local dirX, dirY, magnitude = M.CombineForce(rec.Participants, self.config.Movement.OppositionDeadzone)
    local cfg = self.config.Movement
    local targetSpeed = 0
    if magnitude > 0 then targetSpeed = math.min(cfg.MaxSpeed, cfg.BaseSpeed * magnitude) end
    local oldSpeed, oldX, oldY = rec.MotionSpeed or 0, rec.MotionDirX or 0, rec.MotionDirY or 1
    if targetSpeed == 0 then
        rec.MotionSpeed = math.max(0, oldSpeed - cfg.Deceleration * dt)
    else
        local dot = oldSpeed > 0 and (oldX * dirX + oldY * dirY) or 1
        if oldSpeed > 0 and dot < 0.999 then
            rec.MotionSpeed = math.max(0, oldSpeed - cfg.Deceleration * dt)
            if rec.MotionSpeed <= 0.0001 then
                rec.MotionSpeed = 0
                rec.MotionDirX, rec.MotionDirY = dirX, dirY
            end
        else
            rec.MotionDirX, rec.MotionDirY = dirX, dirY
            if oldSpeed < targetSpeed then
                rec.MotionSpeed = math.min(targetSpeed, oldSpeed + cfg.Acceleration * dt)
            else
                rec.MotionSpeed = math.max(targetSpeed, oldSpeed - cfg.Deceleration * dt)
            end
        end
    end
    if rec.MotionSpeed <= 0.0001 then rec.MotionSpeed = 0 end
    if math.abs(rec.MotionSpeed - oldSpeed) > 0.001 then rec._motionDirty = true end

end
function M:Tick(now, dt)
    local dirty = {}
    for actor, rec in pairs(self.crates) do
        rec._motionDirty = false
        local participants = {}
        for _, p in pairs(rec.Participants) do participants[#participants + 1] = p end
        for _, p in ipairs(participants) do updateParticipant(self, rec, p, now) end
        updateMotion(self, rec, dt)
        if rec._dirty then
            rec._dirty = false
            dirty[#dirty + 1] = actor
        end
    end
    return dirty
end

function M:MarkBlocked(actor)
    local rec = self.crates[actor]
    if not rec then return end
    rec.Blocked = true
    rec.MotionSpeed = 0
    markDirty(rec)
end

function M:ClearBlocked(actor)
    local rec = self.crates[actor]
    if rec and rec.Blocked then
        rec.Blocked = false
        markDirty(rec)
    end
end

function M:Snapshot(actor)
    local rec = self.crates[actor]
    if not rec then return nil end
    local participants = {}
    for key, p in pairs(rec.Participants) do
        participants[key] = {
            PlayerKey = p.PlayerKey,
            ParticipantId = p.ParticipantId,
            FaceIndex = p.FaceIndex,
            GripU = p.GripU,
            GripStandOff = p.GripStandOff,
            Phase = p.Phase,
            Intent = p.Intent,
            AnimState = p.AnimState,
            AnimRevision = p.AnimRevision,
        }
    end
    return {
        CrateId = rec.CrateId,
        SessionId = rec.SessionId,
        Revision = rec.Revision,
        Enabled = rec.Enabled,
        MotionSpeed = rec.MotionSpeed,
        MotionDirX = rec.MotionDirX,
        MotionDirY = rec.MotionDirY,
        Blocked = rec.Blocked,
        Participants = participants,
    }
end

return M
