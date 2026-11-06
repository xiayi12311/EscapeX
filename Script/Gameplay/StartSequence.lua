-- Local open-match LevelSequence + server control locks (TeacherShow/Capture pattern).
-- Play is client-local; freeze/restore is authority-only via PC ServerRPCs.
local M = {}

local DEFAULT_RELATIVE_PATH = 'Asset/Sequences/LS_Start.LS_Start'

-- Same tags as CaptureService / BP_TeacherShowTrigger. SetDynamicStateDisabled is
-- reference-counted per tag, so our GameMode-owned locks stack with theirs.
local controlTags = {
    'PawnState.Movement.Walking', 'PawnState.Action.Sprint',
    'PawnState.Action.Jump', 'PawnState.Action.Vault',
    'PawnState.Action.HoldWeapon', 'PawnState.Action.HoldGrenade',
    'PawnState.Action.MeleeAttack', 'PawnState.Action.Pick',
    'PawnState.Action.SwitchWeapon', 'PawnState.Action.UseConsumables',
    'PawnState.Gun.GunFire', 'PawnState.Gun.GunADS',
    'PawnState.Pose.Crouch', 'PawnState.Pose.Prone',
}

local function valid(o)
    return o ~= nil and KismetSystemLibrary.IsValid(o)
end

local function stopPawnMotion(pawn)
    if not valid(pawn) then return end
    local move = pawn.CharacterMovement
    if valid(move) then
        move:StopMovementImmediately()
    end
end

local function setPlayerFrozen(gm, pawn, frozen)
    if not valid(pawn) then return false end
    gm.StartSequenceFreezeLocks = gm.StartSequenceFreezeLocks or {}
    if frozen then
        if gm.StartSequenceFreezeLocks[pawn] then return true end
        local acquired = {}
        local ok, err = pcall(function()
            for _, tag in ipairs(controlTags) do
                assert(UGCGameplayTagSystem.IsValidTag(tag), 'invalid start-sequence control tag: ' .. tag)
                UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, true, true)
                acquired[#acquired + 1] = tag
            end
        end)
        gm.StartSequenceFreezeLocks[pawn] = acquired
        if not ok then
            for _, tag in ipairs(acquired) do
                UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, false, false)
            end
            gm.StartSequenceFreezeLocks[pawn] = nil
            ugcprint('[StartSequence] control lock failed: ' .. tostring(err))
            return false
        end
        stopPawnMotion(pawn)
        return true
    end
    local tags = gm.StartSequenceFreezeLocks[pawn]
    if not tags then return true end
    for _, tag in ipairs(tags) do
        UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, false, false)
    end
    gm.StartSequenceFreezeLocks[pawn] = nil
    return true
end

--- Authority: one ref per local client that started LS_Start; locks apply at 1, clear at 0.
function M.ServerFreezeAll(gm)
    if not (valid(gm) and gm:HasAuthority()) then return end
    gm.StartSequenceFreezeCount = (gm.StartSequenceFreezeCount or 0) + 1
    if gm.StartSequenceFreezeCount > 1 then return end
    gm.StartSequenceFreezeLocks = {}
    for _, pawn in pairs(UGCGameSystem.GetAllPlayerPawn() or {}) do
        setPlayerFrozen(gm, pawn, true)
    end
    ugcprint('[StartSequence] froze all players for opening sequence')
end

function M.ServerRestoreAll(gm)
    if not (valid(gm) and gm:HasAuthority()) then return end
    local count = gm.StartSequenceFreezeCount or 0
    if count <= 0 then return end
    gm.StartSequenceFreezeCount = count - 1
    if gm.StartSequenceFreezeCount > 0 then return end
    for pawn, _ in pairs(gm.StartSequenceFreezeLocks or {}) do
        setPlayerFrozen(gm, pawn, false)
    end
    gm.StartSequenceFreezeLocks = {}
    ugcprint('[StartSequence] restored all players after opening sequence')
end

local function requestServerFreeze(controller)
    if controller.StartSequenceFreezePlayers == false then return end
    UnrealNetwork.CallUnrealRPC(controller, controller, 'ServerRPC_StartSequenceFreeze')
end

local function requestServerRestore(controller)
    if controller.StartSequenceFreezePlayers == false then return end
    UnrealNetwork.CallUnrealRPC(controller, controller, 'ServerRPC_StartSequenceRestore')
end

local function release(controller)
    if not controller then return end
    if valid(controller.StartSequencePlayer) then
        pcall(function() controller.StartSequencePlayer:Stop() end)
    end
    if valid(controller.StartSequenceActor) then
        pcall(function() controller.StartSequenceActor:K2_DestroyActor() end)
    end
    controller.StartSequencePlayer = nil
    controller.StartSequenceActor = nil
end

function M.OnFinished(controller)
    if not valid(controller) then return end
    controller.StartSequencePlayer = nil
    if valid(controller.StartSequenceActor) then
        controller.StartSequenceActor:K2_DestroyActor()
    end
    controller.StartSequenceActor = nil
    if controller == UGCGameSystem.GetLocalPlayerController() and controller.StartSequenceFreezeRequested then
        controller.StartSequenceFreezeRequested = false
        requestServerRestore(controller)
    end
end

--- Play LS_Start (or BP override path) for the local player only.
---@param controller APlayerController
function M.PlayLocal(controller)
    if not valid(controller) then return end
    if controller ~= UGCGameSystem.GetLocalPlayerController() then return end
    if controller.StartSequenceEnabled == false then return end
    if controller.StartSequencePlayed then return end

    local relative = controller.StartSequencePath
    if type(relative) ~= 'string' or relative == '' then
        relative = DEFAULT_RELATIVE_PATH
    end
    local fullPath = UGCGameSystem.GetUGCResourcesFullPath(relative)
    local sequence = UE.LoadObject(fullPath)
    if not valid(sequence) then
        ugcprint('[StartSequence] sequence not found: ' .. tostring(fullPath))
        return
    end

    local playRate = tonumber(controller.StartSequencePlayRate) or 1
    if playRate <= 0 then playRate = 1 end

    local playerClass = UE.LoadClass('/Script/LevelSequence.LevelSequencePlayer')
    local factory = valid(playerClass) and UGCObjectUtility.GetClassDefaultObject(playerClass)
    if not valid(factory) then
        ugcprint('[StartSequence] failed to load LevelSequencePlayer factory')
        return
    end

    release(controller)
    local player, sequenceActor = factory.CreateLevelSequencePlayer(
        controller,
        sequence,
        {
            LoopCount = 0,
            PlayRate = playRate,
            StartTime = 0,
            bRestoreState = controller.StartSequenceRestoreState == true,
        },
        nil
    )
    if not (valid(player) and valid(sequenceActor)) then
        ugcprint('[StartSequence] failed to create LevelSequence player')
        return
    end

    controller.StartSequencePlayed = true
    controller.StartSequencePlayer = player
    controller.StartSequenceActor = sequenceActor
    requestServerFreeze(controller)
    if controller.StartSequenceFreezePlayers ~= false then
        controller.StartSequenceFreezeRequested = true
    end
    player.OnFinished:Add(M.OnFinished, controller)
    player:Play()
    ugcprint('[StartSequence] playing ' .. tostring(relative))
end

function M.StopLocal(controller)
    if not valid(controller) then return end
    if controller ~= UGCGameSystem.GetLocalPlayerController() then return end
    release(controller)
    if controller.StartSequenceFreezeRequested then
        controller.StartSequenceFreezeRequested = false
        requestServerRestore(controller)
    end
end

return M
