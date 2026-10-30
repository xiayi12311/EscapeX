local M = {
    WHITE = 1,
    YELLOW = 2,
    RED = 3,
}

local function finite(value)
    return type(value) == "number"
        and value == value
        and math.abs(value) < math.huge
end

function M.tierFor(distanceCm, detected)
    if detected then
        return M.RED, "red"
    end

    distanceCm = tonumber(distanceCm)
    if not finite(distanceCm) then
        return nil, "invalid"
    end
    if distanceCm <= 1000 then
        return M.YELLOW, "yellow"
    end
    if distanceCm <= 2000 then
        return M.WHITE, "white"
    end
    return nil, "out"
end

function M.insideVision(source, target, forward, maxDistance, fullAngleDegrees)
    maxDistance = tonumber(maxDistance)
    fullAngleDegrees = tonumber(fullAngleDegrees)
    if not (finite(maxDistance) and maxDistance > 0)
        or not (finite(fullAngleDegrees) and fullAngleDegrees > 0 and fullAngleDegrees <= 180)
        or not source
        or not target
        or not forward then
        return false
    end

    local dx = target.X - source.X
    local dy = target.Y - source.Y
    local dz = target.Z - source.Z
    local distanceSquared = dx * dx + dy * dy + dz * dz
    if distanceSquared > maxDistance * maxDistance then
        return false
    end
    if distanceSquared <= 0.000001 then
        return true
    end

    local distance = math.sqrt(distanceSquared)
    local dot = (dx * forward.X + dy * forward.Y + dz * forward.Z) / distance
    dot = math.max(-1, math.min(1, dot))
    local angle = math.deg(math.acos(dot))
    return angle <= fullAngleDegrees * 0.5
end

return M
