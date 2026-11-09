-- Client animation state machine. The server owns AnimState; this module only maps that
-- state to the eight CG009 single-node sequences and restores the pawn's original mode.
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig')
local A = {}

local LOG = '[PushPull]'
local plays = {}
local assets = {}

local function log(text) ugcprint(LOG .. ' anim ' .. tostring(text)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local function localKey()
    local ok, pc = pcall(function() return UGCGameSystem.GetLocalPlayerController() end)
    if not (ok and valid(pc)) then return -1 end
    local okKey, key = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerController(pc) end)
    if okKey and type(key) == 'number' then return key end
    return -1
end

local function pawnOf(key)
    local ok, pawn = pcall(function() return UGCGameSystem.GetPlayerPawnByPlayerKey(key) end)
    if ok and valid(pawn) then return pawn end
    return nil
end

local function assetOf(state)
    local path = Config.Animations[state]
    if not path then error('unknown PushPull animation state: ' .. tostring(state)) end
    if assets[state] ~= nil then return assets[state] end
    local asset = UGCObjectUtility.LoadObject(path)
    if not valid(asset) then error('animation unavailable: ' .. tostring(path)) end
    assets[state] = asset
    local okLength, actualLength = pcall(function() return asset:GetPlayLength() end)
    local expectedLength = Config.AnimationDurations and Config.AnimationDurations[state]
    if okLength and type(actualLength) == 'number' and type(expectedLength) == 'number'
        and math.abs(actualLength - expectedLength) > 0.02 then
        log('duration mismatch state=' .. tostring(state) .. ' actual=' .. tostring(actualLength)
            .. ' config=' .. tostring(expectedLength))
    end
    return asset
end

local function stop(pawn, entry)
    if not entry then return end
    if valid(entry.mesh) then
        local ok, err = pcall(function()
            entry.mesh:Stop()
            entry.mesh:SetAnimationMode(entry.mode)
        end)
        if not ok then log('restore failed pawn=' .. tostring(pawn) .. ' error=' .. tostring(err)) end
    end
    plays[pawn] = nil
end

local function play(pawn, actor, participant, state, isLocal)
    local entry = plays[pawn]
    if entry and entry.actor ~= actor then
        stop(pawn, entry)
        entry = nil
    end
    if not valid(pawn.Mesh) then
        log('cannot play, pawn mesh unavailable player=' .. tostring(participant.PlayerKey))
        return
    end
    local sequence = assetOf(state)
    local looping = state == 'Idle' or state == 'Push' or state == 'Pull'
    if not entry then
        entry = {mesh = pawn.Mesh, mode = pawn.Mesh:GetAnimationMode()}
        plays[pawn] = entry
    end
    entry.actor = actor
    entry.playerKey = participant.PlayerKey
    entry.state = state
    entry.animRevision = participant.AnimRevision
    entry.localAtPlay = isLocal
    local ok, err = pcall(function()
        entry.mesh:PlayAnimation(sequence, looping)
        entry.mesh:SetPlayRate(1.0)
    end)
    if not ok then
        log('play failed player=' .. tostring(participant.PlayerKey) .. ' state=' .. tostring(state)
            .. ' error=' .. tostring(err))
        return
    end
    log('play player=' .. tostring(participant.PlayerKey) .. ' state=' .. tostring(state)
        .. ' loop=' .. tostring(looping))
end

function A.Sync(actor, state)
    if not valid(actor) or not state or not state.Participants then return end
    local key = localKey()
    local seen = {}
    for playerKey, participant in pairs(state.Participants) do
        local pawn = pawnOf(playerKey)
        if pawn then
            seen[pawn] = true
            local entry = plays[pawn]
            local isLocal = playerKey == key
            local desired = participant.AnimState
            local currentRevision = entry and entry.animRevision or nil
            local initialRemote = not entry and not isLocal
            if initialRemote then
                if desired == 'OnPosition' or desired == 'PushStop' or desired == 'PullStop' then
                    desired = 'Idle'
                elseif desired == 'PushStart' then
                    desired = 'Push'
                elseif desired == 'PullStart' then
                    desired = 'Pull'
                end
            end
            local becameLocal = isLocal and entry and entry.localAtPlay ~= true
            if not entry or entry.actor ~= actor or entry.state ~= desired
                or currentRevision ~= participant.AnimRevision or becameLocal then
                play(pawn, actor, participant, desired, isLocal)
            end
        end
    end
    for pawn, entry in pairs(plays) do
        if entry.actor == actor and not seen[pawn] then stop(pawn, entry) end
    end
    A.UpdateRate(actor, state)
end

function A.UpdateRate(actor, state)
    if not state or not state.Participants then return end
    local rate = 1.0
    if state.MotionSpeed and state.MotionSpeed > 0 then
        rate = math.max(Config.Action.MinLoopRate, math.min(Config.Action.MaxLoopRate,
            state.MotionSpeed / Config.Movement.BaseSpeed))
    end
    for playerKey, participant in pairs(state.Participants) do
        local pawn = pawnOf(playerKey)
        local entry = pawn and plays[pawn]
        if entry and entry.actor == actor then
            if participant.AnimState == 'Push' or participant.AnimState == 'Pull' then
                pcall(function() entry.mesh:SetPlayRate(rate) end)
            else
                pcall(function() entry.mesh:SetPlayRate(1.0) end)
            end
        end
    end
end

function A.ClearActor(actor)
    for pawn, entry in pairs(plays) do
        if entry.actor == actor then stop(pawn, entry) end
    end
end

function A.RestorePawn(pawn)
    local entry = pawn and plays[pawn]
    if entry then stop(pawn, entry) end
end

return A
