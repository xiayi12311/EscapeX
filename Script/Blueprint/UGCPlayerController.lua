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
local PlayerController={}

-- The controller is the stable local-session owner: pawns are replaced on respawn, so the
-- focus layer is armed here and follows pawn identity changes (see DeskFocusPresentation
-- Monitor comment for the measured pawn-hook failure).
function PlayerController:ReceiveBeginPlay()
    PlayerController.SuperClass.ReceiveBeginPlay(self)
    Focus.Monitor()
    FirstPerson.MonitorLocal(self)
    StartSequence.PlayLocal(self)
end

function PlayerController:ReceiveEndPlay(reason)
    FirstPerson.StopLocal(self)
    StartSequence.StopLocal(self)
    PlayerController.SuperClass.ReceiveEndPlay(self,reason)
end

-- Client requests a start through its own controller; no player key or outcome is
-- accepted from the client. The existing service validates desk registration,
-- character state, range and exclusivity on the server.
function PlayerController:GetAvailableServerRPCs()
    return 'ServerRequestDeskSearch', 'ServerCancelDeskSearch', 'ServerRequestStruggle', 'ServerRPC_StartSequenceFreeze', 'ServerRPC_StartSequenceRestore'
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
function PlayerController:UGC_PlayerLostConnectionEvent()
    PlayerController.SuperClass.UGC_PlayerLostConnectionEvent(self)
    if self:HasAuthority() then
        DeskSearch.CancelPlayer(UGCGameSystem.GetGameMode(),self,'DISCONNECTED')
        Capture.CancelPlayer(UGCGameSystem.GetGameMode(),self,'PLAYER_UNAVAILABLE')
    end
end

return PlayerController
