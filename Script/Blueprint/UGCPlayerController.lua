---@class UGCPlayerController_C
---@field StartSequenceEnabled bool
---@field StartSequencePath FString
---@field StartSequencePlayRate float
---@field StartSequenceRestoreState bool
---@field StartSequenceFreezePlayers bool
--Edit Below--
local DeskSearch=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskSearchService')
local Capture=UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureService')
local Focus=UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.DeskFocusPresentation')
local FirstPerson=UGCGameSystem.UGCRequire('Script.Gameplay.FirstPerson')
local StartSequence=UGCGameSystem.UGCRequire('Script.Gameplay.StartSequence')
local PushPullConfig=UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig')
local PushPullService=UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullService')
local PushPullFocus=UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullFocusPresentation')
local PushPullPresentation=UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullPresentation')
local PlayerController={}

-- The controller is the stable local-session owner: pawns are replaced on respawn, so the
-- focus layer is armed here and follows pawn identity changes (see DeskFocusPresentation
-- Monitor comment for the measured pawn-hook failure).
function PlayerController:ReceiveBeginPlay()
    PlayerController.SuperClass.ReceiveBeginPlay(self)
    Focus.Monitor()
    PushPullFocus.Monitor()
    PushPullPresentation.Monitor()
    FirstPerson.MonitorLocal(self)
    StartSequence.PlayLocal(self)
end

function PlayerController:ReceiveEndPlay(reason)
    PushPullPresentation.StopMonitor()
    PushPullFocus.StopMonitor()
    FirstPerson.StopLocal(self)
    StartSequence.StopLocal(self)
    PlayerController.SuperClass.ReceiveEndPlay(self,reason)
end

-- Client requests a start through its own controller; no player key or outcome is
-- accepted from the client. The existing service validates desk registration,
-- character state, range and exclusivity on the server.
function PlayerController:GetAvailableServerRPCs()
    return 'ServerRequestDeskSearch', 'ServerCancelDeskSearch', 'ServerRequestStruggle',
        'ServerRPC_StartSequenceFreeze', 'ServerRPC_StartSequenceRestore',
        'ServerRequestPushPull', 'ServerSetPushPullIntent', 'ServerReleasePushPull',
        'ClientPushPullRejected'
end

function PlayerController:ServerRequestStruggle(post, sessionId)
    if not self:HasAuthority() or not post or not KismetSystemLibrary.IsValid(post) then return end
    local state = post.PrisonState
    if not state or state.SessionId ~= sessionId or state.State ~= 'Imprisoned' then return end
    local ok, reason = Capture.Struggle(UGCGameSystem.GetGameMode(), post, self)
    if not ok and reason ~= 'TOO_FAST' then ugcprint('[HTCapture] struggle refused '..tostring(reason)) end
end

function PlayerController:ServerRequestDeskSearch(desk, sequence)
    if not self:HasAuthority() then return end
    if type(sequence)~='number' or sequence~=math.floor(sequence) or sequence<=0
        or sequence<=(self.DeskHoldSequence or 0) or sequence<=(self.DeskCancelSequence or 0) then return end
    self.DeskHoldSequence=sequence
    self.DeskHoldActor=nil
    local ok,reason=DeskSearch.StartSearch(UGCGameSystem.GetGameMode(),desk,self)
    if ok then self.DeskHoldActor=desk end
    if not ok then
        ugcprint('[DeskSearch] request rejected '..tostring(reason))
        UnrealNetwork.CallUnrealRPC(self,self,'ClientDeskSearchRejected',sequence,tostring(reason))
    end
end

function PlayerController:ClientDeskSearchRejected(sequence,reason)
    Focus.RequestRejected(sequence,reason)
end

function PlayerController:ServerCancelDeskSearch(desk, sequence)
    if not self:HasAuthority() or type(sequence)~='number' or sequence~=math.floor(sequence) or sequence<=0 then return end
    if sequence>(self.DeskCancelSequence or 0) then self.DeskCancelSequence=sequence end
    if sequence~=self.DeskHoldSequence or desk~=self.DeskHoldActor then return end
    self.DeskHoldActor=nil
    DeskSearch.CancelPlayer(UGCGameSystem.GetGameMode(),self,'PLAYER_CANCELLED')
end

function PlayerController:ServerRPC_StartSequenceFreeze()
    if not self:HasAuthority() then return end
    if self.StartSequenceFreezePlayers == false then return end
    local gm = UGCGameSystem.GetGameMode()
    StartSequence.ServerFreezeAll(gm)
end

function PlayerController:ServerRPC_StartSequenceRestore()
    if not self:HasAuthority() then return end
    if self.StartSequenceFreezePlayers == false then return end
    local gm = UGCGameSystem.GetGameMode()
    StartSequence.ServerRestoreAll(gm)
end

local function validSequence(sequence)
    return type(sequence) == 'number' and sequence == math.floor(sequence) and sequence > 0
end

local function acceptSequence(self, sequence)
    if not validSequence(sequence) or sequence <= (self.PushPullRequestSequence or 0) then
        return false
    end
    self.PushPullRequestSequence = sequence
    return true
end

function PlayerController:ServerRequestPushPull(crate, sequence)
    if not self:HasAuthority() then return end
    if not acceptSequence(self, sequence) then
        if validSequence(sequence) then
            UnrealNetwork.CallUnrealRPC(self, self, 'ClientPushPullRejected', sequence, 'STALE_REQUEST')
        end
        return
    end
    local ok, reason = PushPullService.RequestEntry(UGCGameSystem.GetGameMode(), crate, self)
    if not ok then
        ugcprint('[PushPull] entry rejected player=' .. tostring(UGCGameSystem.GetPlayerKeyByPlayerController(self))
            .. ' reason=' .. tostring(reason))
        UnrealNetwork.CallUnrealRPC(self, self, 'ClientPushPullRejected', sequence, tostring(reason))
    end
end

function PlayerController:ServerSetPushPullIntent(crate, sessionId, intent, sequence)
    if not self:HasAuthority() then return end
    if not acceptSequence(self, sequence) then return end
    local now = UGCGameSystem.GetTimeSeconds(self)
    local minimum = 1 / PushPullConfig.Input.MaxRpcRate
    local last = self.PushPullLastIntentAt
    if type(now) ~= 'number' or (last and now - last < minimum) then
        return
    end
    self.PushPullLastIntentAt = now
    local ok, reason = PushPullService.SetIntent(UGCGameSystem.GetGameMode(), crate, self, sessionId, intent)
    if not ok and reason ~= 'PLAYER_UNAVAILABLE' then
        ugcprint('[PushPull] intent rejected reason=' .. tostring(reason))
    end
end

function PlayerController:ServerReleasePushPull(crate, sessionId, sequence)
    if not self:HasAuthority() then return end
    if not acceptSequence(self, sequence) then return end
    local ok, reason = PushPullService.Release(UGCGameSystem.GetGameMode(), crate, self, sessionId)
    if not ok then
        ugcprint('[PushPull] release rejected reason=' .. tostring(reason))
    end
end


function PlayerController:UGC_PlayerLostConnectionEvent()
    PlayerController.SuperClass.UGC_PlayerLostConnectionEvent(self)
    if self:HasAuthority() then
        DeskSearch.CancelPlayer(UGCGameSystem.GetGameMode(),self,'DISCONNECTED')
        Capture.CancelPlayer(UGCGameSystem.GetGameMode(),self,'PLAYER_UNAVAILABLE')
        PushPullService.CancelPlayer(UGCGameSystem.GetGameMode(),self,'PLAYER_UNAVAILABLE')
    end
end

return PlayerController
