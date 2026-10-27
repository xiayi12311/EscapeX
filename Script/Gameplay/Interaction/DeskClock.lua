-- One time base for desk search timing on both ends.
-- Why this exists: the service used to stamp SearchStartTime/SearchEndTime with
-- UGCGameSystem.GetServerTimeSec(), which this build returns as whole epoch seconds
-- (measured 2026-10-26 on a PIE DS: two samples 0.1s apart differed by 0.000000), while
-- the ring reads a world-seconds clock. Two bases make the progress ratio meaningless,
-- and no mock caught it because each side stubs its own clock.
local M = {}

local warned = {}
local function warnOnce(key, text)
    if warned[key] then return end
    warned[key] = true
    ugcprint('[DeskClock] ' .. text)
end

local function gameState()
    local ok, gs = pcall(function() return UGCGameSystem.GetGameState() end)
    if ok and gs ~= nil and KismetSystemLibrary.IsValid(gs) then return gs end
    return nil
end

-- The authoritative server world time.
local function replicated(gs)
    if gs == nil then return nil end
    local ok, t = pcall(function() return gs:GetServerWorldTimeSeconds() end)
    if ok and type(t) == 'number' then return t end
    return nil
end

-- local world time plus the replicated offset onto the server clock: same base as
-- `replicated`, but continuous between replication ticks.
local function localPlusDelta(gs, contextObject)
    if gs == nil then return nil end
    local okLocal, localTime = pcall(function()
        return KismetSystemLibrary.GetGameTimeInSeconds(contextObject or gs)
    end)
    if not (okLocal and type(localTime) == 'number') then return nil end
    local okDelta, delta = pcall(function() return gs.ServerWorldTimeSecondsDelta end)
    if not (okDelta and type(delta) == 'number') then return nil end
    return localTime + delta
end

-- Server authoritative value. A missing clock is an error, not a different clock source.
function M.ServerNow(contextObject)
    local gs = gameState()
    local t = replicated(gs)
    if t == nil then warnOnce('server', 'GameState server time unavailable') end
    return t
end

-- Client-side reading of the same base, interpolated locally. No alternate clock.
function M.ApproxServerNow(contextObject)
    local gs = gameState()
    local smooth = localPlusDelta(gs, contextObject)
    if smooth == nil then warnOnce('client', 'server time delta or local world time unavailable') end
    return smooth
end

function M.Now(contextObject, isServer)
    if isServer then return M.ServerNow(contextObject) end
    return M.ApproxServerNow(contextObject)
end

return M
