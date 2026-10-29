-- Pure data for the capture/imprisonment state machine. No engine access.
local C = {}

-- Monster-side values are mirrored as HT* keys in HTCommon.M.Defaults so that a
-- blueprint variable of the same name can override them per monster instance.
C.Defaults = {
    PickupDuration = 0.6,
    PutDownDuration = 0.6,
    EscortSpeed = 300,
    ArriveRadius = 120,
    EscortTimeout = 20,
    ImprisonDuration = 15,
    StrugglePresses = 8,
    StruggleInterval = 0.15,
    RescueDuration = 3,
    RescueRadius = 220,
    -- Height compensation for the bind point, whose own RelativeLocation cannot be
    -- authored through the editor scripting layer.
    BindHeightOffset = 90,
}

C.States = {
    Grabbing = true, Carrying = true, PuttingDown = true,
    Imprisoned = true, Released = true,
}

-- Release reasons are part of the acceptance log vocabulary; keep them stable.
C.Reasons = {
    BROKE_FREE = 'imprisoned player struggled free',
    RESCUED = 'rescued by another player',
    ESCORT_TIMEOUT = 'no reachable free post in time',
    NO_POST = 'no prison post registered',
    PLAYER_UNAVAILABLE = 'captured player left the round',
    PLAYER_DEAD = 'captured player was eliminated',
    POST_REMOVED = 'prison post was removed while occupied',
    MONSTER_DESTROYED = 'carrier actor destroyed',
    SERVER_SHUTDOWN = 'server teardown',
    CANCELLED = 'cancelled by script',
}

-- Bounds are checked once at registration; an out-of-range value must not silently
-- stretch a timer, it rejects the session instead.
function C.Check(options)
    local o = options or {}
    local function num(key, min, max)
        local v = o[key]
        if v == nil then v = C.Defaults[key] end
        if type(v) ~= 'number' or v ~= v or v < min then return false, key end
        if max and v > max then return false, key end
        return true, v
    end
    local ok, value = num('PickupDuration', 0, 5)
    if not ok then return false, value end
    for _, key in ipairs({'PutDownDuration', 'EscortTimeout', 'ImprisonDuration'}) do
        ok, value = num(key, 0, 300)
        if not ok then return false, value end
    end
    ok, value = num('ArriveRadius', 10)
    if not ok then return false, value end
    ok, value = num('EscortSpeed', 1)
    if not ok then return false, value end
    ok, value = num('StruggleInterval', 0.01, 2)
    if not ok then return false, value end
    ok, value = num('RescueDuration', 0.1, 60)
    if not ok then return false, value end
    ok, value = num('RescueRadius', 50, 2000)
    if not ok then return false, value end
    local presses = o.StrugglePresses or C.Defaults.StrugglePresses
    if type(presses) ~= 'number' or presses < 1 or presses ~= math.floor(presses) then
        return false, 'StrugglePresses'
    end
    return true
end

return C
