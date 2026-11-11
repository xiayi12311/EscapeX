---@class BP_TeacherShowTrigger_C:BP_CutsceneTriggerBase_C
---@field TeacherActorTag FString
---@field CameraActorTag FString
---@field ShowCameraBlendTime float
---@field ShowCameraEntryLocation FVector
---@field ShowCameraEntryRotation FRotator
--Edit Below--
local Base = require('Script.Blueprint.Prefabs.Interactables.BP_CutsceneTriggerBase')
local TeacherShowTrigger = Base.NewClass()

local function valid(o)
    return o ~= nil and KismetSystemLibrary.IsValid(o)
end

-- Same action tags CaptureService uses for control locks (gp-docs SetDynamicStateDisabled;
-- reference-counted so leaving our locks does not clear Capture's). Interacting is left
-- alone here the same way Capture does; cutscene camera ownership is sequence-driven.
local controlTags = {
    'PawnState.Movement.Walking', 'PawnState.Action.Sprint',
    'PawnState.Action.Jump', 'PawnState.Action.Vault',
    'PawnState.Action.HoldWeapon', 'PawnState.Action.HoldGrenade',
    'PawnState.Action.MeleeAttack', 'PawnState.Action.Pick',
    'PawnState.Action.SwitchWeapon', 'PawnState.Action.UseConsumables',
    'PawnState.Gun.GunFire', 'PawnState.Gun.GunADS',
    'PawnState.Pose.Crouch', 'PawnState.Pose.Prone',
}

local function freezeEnabled(self)
    return self.FreezePlayersDuringShow ~= false
end

local function stopPawnMotion(pawn)
    if not valid(pawn) then return end
    local move = pawn.CharacterMovement
    if valid(move) then
        move:StopMovementImmediately()
    end
end

local function setPlayerFrozen(self, pawn, frozen)
    if not valid(pawn) then return false end
    self.ShowFreezeLocks = self.ShowFreezeLocks or {}
    if frozen then
        if self.ShowFreezeLocks[pawn] then return true end
        local acquired = {}
        local ok, err = pcall(function()
            for _, tag in ipairs(controlTags) do
                assert(UGCGameplayTagSystem.IsValidTag(tag), 'invalid show control tag: ' .. tag)
                UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, true, true)
                acquired[#acquired + 1] = tag
            end
        end)
        self.ShowFreezeLocks[pawn] = acquired
        if not ok then
            for _, tag in ipairs(acquired) do
                UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, false, false)
            end
            self.ShowFreezeLocks[pawn] = nil
            ugcprint('[TeacherShowTrigger] control lock failed: ' .. tostring(err))
            return false
        end
        stopPawnMotion(pawn)
        return true
    end

    local tags = self.ShowFreezeLocks[pawn]
    if not tags then return true end
    for _, tag in ipairs(tags) do
        UGCPersistEffectSystem.SetDynamicStateDisabled(pawn, tag, false, false)
    end
    self.ShowFreezeLocks[pawn] = nil
    return true
end

local function freezeAllPlayers(self)
    if not self:HasAuthority() or not freezeEnabled(self) then return end
    if self.ShowPlayersFrozen then return end
    self.ShowFreezeLocks = {}
    for _, pawn in pairs(UGCGameSystem.GetAllPlayerPawn() or {}) do
        setPlayerFrozen(self, pawn, true)
    end
    self.ShowPlayersFrozen = true
    ugcprint('[TeacherShowTrigger] froze all players for cutscene')
end

local function restoreAllPlayers(self)
    if not self:HasAuthority() then return end
    if not self.ShowPlayersFrozen and not self.ShowFreezeLocks then return end
    for pawn, _ in pairs(self.ShowFreezeLocks or {}) do
        setPlayerFrozen(self, pawn, false)
    end
    -- Also clear any pawn that may have been missed if the table key became invalid.
    self.ShowFreezeLocks = {}
    self.ShowPlayersFrozen = false
    ugcprint('[TeacherShowTrigger] restored all players after cutscene')
end

local function findActorByTag(context, tag)
    if type(tag) ~= 'string' or tag == '' then return nil end
    local actors = GameplayStatics.GetAllActorsWithTag(context, tag, {}) or {}
    return actors[1]
end

function TeacherShowTrigger:ConfigureCutsceneBindings(sequenceActor, player)
    local teacher = findActorByTag(self, self.TeacherActorTag)
    local camera = findActorByTag(self, self.CameraActorTag)
    if not valid(teacher) or not valid(camera) then
        ugcprint('[TeacherShowTrigger] possessable actors not found for tags: '
            ..tostring(self.TeacherActorTag)..', '..tostring(self.CameraActorTag))
        return false
    end

    sequenceActor:UGCAddBinding(teacher, 'SK_NewWorld_TianTan_NPC_F')
    sequenceActor:UGCAddBinding(camera, 'TeacherCamera')
    return true
end

-- Runs only on the receiving client, before Camera Cuts can take ownership.
function TeacherShowTrigger:BeginCutscenePlayback(startPlayback)
    local pc = UGCGameSystem.GetLocalPlayerController()
    local camera = findActorByTag(self, self.CameraActorTag)
    local duration = tonumber(self.ShowCameraBlendTime)
    if not valid(pc) or not valid(camera) or not duration or duration < 0 then
        ugcprint('[TeacherShowTrigger] invalid camera transition configuration')
        self:StopCutscene()
        return
    end
    self.ShowCameraController = pc
    self.ShowOriginalViewTarget = pc:GetViewTarget()
    camera:K2_SetActorLocationAndRotation(
        self.ShowCameraEntryLocation, self.ShowCameraEntryRotation, false, {}, true)
    -- VTBlend_Cubic = 1; lock the outgoing POV while approaching the first frame.
    pc:SetViewTargetWithBlend(camera, duration, 1, 2.0, true)
    if duration == 0 then
        startPlayback()
        return
    end
    local generation = self.CutscenePrepareGeneration
    self.ShowCameraBlendTimer, self.ShowCameraBlendDelegate = UGCGameSystem.SetTimer(self, function()
        if not valid(self) or self.CutscenePrepareGeneration ~= generation then return end
        self.ShowCameraBlendTimer = nil
        self.ShowCameraBlendDelegate = nil
        ugcprint('[TeacherShowTrigger] entry blend complete; starting sequence')
        startPlayback()
    end, duration, false)
    ugcprint('[TeacherShowTrigger] blending player camera for '..tostring(duration)..' seconds')
end

function TeacherShowTrigger:OnCutsceneReleased()
    if self.ShowCameraBlendTimer then
        UGCGameSystem.ClearTimer(self, self.ShowCameraBlendTimer)
    end
    self.ShowCameraBlendTimer = nil
    self.ShowCameraBlendDelegate = nil
    local pc, original = self.ShowCameraController, self.ShowOriginalViewTarget
    self.ShowCameraController = nil
    self.ShowOriginalViewTarget = nil
    -- Sequence restores its pre-Play target (the cinematic camera); restore gameplay after it.
    if valid(pc) and valid(original) then
        pc:SetViewTargetWithBlend(original, 0, 1, 2.0, false)
    end
end

local baseTryTriggerEffect = TeacherShowTrigger.TryTriggerEffect
function TeacherShowTrigger:TryTriggerEffect(playerKey)
    local started = baseTryTriggerEffect(self, playerKey)
    if started then
        freezeAllPlayers(self)
    end
    return started
end

function TeacherShowTrigger:GetAvailableServerRPCs()
    return 'ServerRPC_TeacherShowFinished'
end

-- Client OnFinished reports to the server so authority can Leave the control locks
-- (SetDynamicStateDisabled is server-only per gp-docs).
function TeacherShowTrigger:ServerRPC_TeacherShowFinished()
    if not self:HasAuthority() then return end
    restoreAllPlayers(self)
end

local baseOnCutsceneFinished = TeacherShowTrigger.OnCutsceneFinished
function TeacherShowTrigger:OnCutsceneFinished()
    local pc = UGCGameSystem.GetLocalPlayerController()
    if valid(pc) then
        UnrealNetwork.CallUnrealRPC(pc, self, 'ServerRPC_TeacherShowFinished')
    end
    baseOnCutsceneFinished(self)
end

local baseReceiveEndPlay = TeacherShowTrigger.ReceiveEndPlay
function TeacherShowTrigger:ReceiveEndPlay(reason)
    if self:HasAuthority() then
        restoreAllPlayers(self)
    end
    baseReceiveEndPlay(self, reason)
end

local DEFAULT_CUTSCENE_SEQUENCE_PATH = '/EscapeX/Asset/Sequences/LS_TeacherShow.LS_TeacherShow'

local function ensureCutsceneSequencePath(self)
    -- Map/CDO historically pointed at missing /EscapeX/Asset/Cinematics/TeacherShow.
    self.CutsceneSequencePath = DEFAULT_CUTSCENE_SEQUENCE_PATH
end

local baseReceiveBeginPlay = TeacherShowTrigger.ReceiveBeginPlay
function TeacherShowTrigger:ReceiveBeginPlay()
    ensureCutsceneSequencePath(self)
    baseReceiveBeginPlay(self)
end

local basePrepareCutsceneAssets = TeacherShowTrigger.PrepareCutsceneAssets
function TeacherShowTrigger:PrepareCutsceneAssets()
    ensureCutsceneSequencePath(self)
    return basePrepareCutsceneAssets(self)
end

local baseMulticast = TeacherShowTrigger.MulticastRPC_PlayCutscene
function TeacherShowTrigger:MulticastRPC_PlayCutscene(audience, playerKey)
    ensureCutsceneSequencePath(self)
    return baseMulticast(self, audience, playerKey)
end

return TeacherShowTrigger