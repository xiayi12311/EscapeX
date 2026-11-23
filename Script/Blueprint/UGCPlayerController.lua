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
local ZombieStartFocus=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseStartFocus')
local ZombieStart=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseStartInteraction')
local ZombieBoard=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardInteraction')
local ZombieBoardFocus=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardFocus')
local ZombieWaveHUD=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWaveHUD')
local Shop = UGCGameSystem.UGCRequire('Script.utils.HospitalShopService')
local ShopPresentation = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseShopPresentation')
local BossBreakAim=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.BossBreakAim')
local PlayerController={}

-- The controller is the stable local-session owner: pawns are replaced on respawn, so the
-- focus layer is armed here and follows pawn identity changes (see DeskFocusPresentation
-- Monitor comment for the measured pawn-hook failure).
function PlayerController:ReceiveBeginPlay()
    PlayerController.SuperClass.ReceiveBeginPlay(self)
    Focus.Monitor()
    PushPullFocus.Monitor()
    ZombieStartFocus.Begin(self)
    ZombieBoardFocus.Begin(self)
    ZombieWaveHUD.Begin(self)
    PushPullPresentation.Monitor()
    FirstPerson.MonitorLocal(self)
    StartSequence.PlayLocal(self)
end

function PlayerController:ReceiveEndPlay(reason)
    PushPullPresentation.StopMonitor()
    PushPullFocus.StopMonitor()
    ZombieStartFocus.End(self)
    ShopPresentation.Close(self)
    ZombieBoardFocus.End(self)
    ZombieWaveHUD.End(self)
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
        'ClientPushPullRejected', 'ServerRequestZombieStart', 'ClientZombieStartResult',
        'ServerOpenDefenseShop', 'ClientOpenDefenseShop', 'ClientDefenseShopDenied', 'RPC_Server_RequestHospitalShopState',
        'RPC_Server_BuyCommodity', 'RPC_Server_RefreshHospitalShop', 'RPC_Server_LockHospitalShop',
        'RPC_Client_HospitalShopState',
        'ServerRequestZombieBoard', 'ServerCompleteZombieBoard', 'ServerCancelZombieBoard', 'ClientZombieBoardResult',
        'ServerRequestBossBreakShot'
end

function PlayerController:ServerRequestBossBreakShot(point, weapon, shotId, x, y, z, dx, dy, dz, cx, cy, cz)
    if not self:HasAuthority() then return end
    BossBreakAim.ResolveShot(self,point,weapon,shotId,{X=x,Y=y,Z=z},{X=dx,Y=dy,Z=dz},{X=cx,Y=cy,Z=cz})
end

function PlayerController:ServerOpenDefenseShop(point)
    if self:HasAuthority() then Shop.Open(self, point) end
end

function PlayerController:ClientOpenDefenseShop()
    if self == UGCGameSystem.GetLocalPlayerController() then ShopPresentation.Open(self) end
end

function PlayerController:ClientDefenseShopDenied(point)
    if self == UGCGameSystem.GetLocalPlayerController() then ZombieStartFocus.ShopDenied(point) end
end

function PlayerController:RPC_Server_RequestHospitalShopState()
    if self:HasAuthority() then Shop.SendState(self) end
end

function PlayerController:RPC_Server_BuyCommodity(id, request, round, wave, version)
    if self:HasAuthority() then Shop.Buy(self, id, request, round, wave, version) end
end

function PlayerController:RPC_Server_RefreshHospitalShop(request, round, wave, version)
    if self:HasAuthority() then Shop.Refresh(self, request, round, wave, version) end
end

function PlayerController:RPC_Server_LockHospitalShop(id, request, round, wave, version)
    if self:HasAuthority() then Shop.Lock(self, id, request, round, wave, version) end
end

function PlayerController:RPC_Client_HospitalShopState(state)
    if self == UGCGameSystem.GetLocalPlayerController() then
        ShopPresentation.Receive(self, state)
    end
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


function PlayerController:ServerRequestZombieStart(point, sequence)
    if not self:HasAuthority() or not validSequence(sequence)
        or sequence <= (self.ZombieStartSequence or 0) then return end
    self.ZombieStartSequence = sequence
    local ok, reason = ZombieStart.Request(self, point)
    UnrealNetwork.CallUnrealRPC(self, self, 'ClientZombieStartResult', sequence, ok, ZombieStart.ErrorText(reason))
end

function PlayerController:ClientZombieStartResult(sequence, ok, reason)
    ZombieStartFocus.Result(sequence, ok, reason)
end

function PlayerController:ServerRequestZombieBoard(point, sequence)
    if not self:HasAuthority() or not validSequence(sequence)
        or sequence <= (self.ZombieBoardSequence or 0) then return end
    self.ZombieBoardSequence = sequence
    local ok = ZombieBoard.RequestInstall(self, point)
    UnrealNetwork.CallUnrealRPC(self, self, 'ClientZombieBoardResult', sequence, ok, false)
end

function PlayerController:ServerCompleteZombieBoard(point, sequence)
    if not self:HasAuthority() or not validSequence(sequence) or sequence ~= self.ZombieBoardSequence then return end
    local ok = ZombieBoard.CompleteInstall(self, point)
    UnrealNetwork.CallUnrealRPC(self, self, 'ClientZombieBoardResult', sequence, ok, true)
end

function PlayerController:ServerCancelZombieBoard(sequence)
    if not self:HasAuthority() or not validSequence(sequence)
        or sequence <= (self.ZombieBoardSequence or 0) then return end
    self.ZombieBoardSequence = sequence
    ZombieBoard.CancelInstall(self)
end

function PlayerController:ClientZombieBoardResult(sequence, ok, completed)
    ZombieBoardFocus.Result(sequence, ok, completed)
end

-- A silent disconnect keeps the controller alive and never raises the game mode's
-- PlayerExitEvent, so the encounter roster would keep counting that player as present
-- forever: a wiped online team would not fail, and the wave timer would never pause on
-- an empty map. This event is the authoritative disconnect signal for that case; the
-- key is still readable here because the controller is not destroyed.
function PlayerController:UGC_PlayerLostConnectionEvent()
    PlayerController.SuperClass.UGC_PlayerLostConnectionEvent(self)
    if self:HasAuthority() then
        local gm = UGCGameSystem.GetGameMode()
        DeskSearch.CancelPlayer(gm,self,'DISCONNECTED')
        Capture.CancelPlayer(gm,self,'PLAYER_UNAVAILABLE')
        PushPullService.CancelPlayer(gm,self,'PLAYER_UNAVAILABLE')
        local key = UGCGameSystem.GetPlayerKeyByPlayerController(self)
        if type(key) == 'number' and key >= 0 then
            -- Same release as the exit event: a disconnected player cannot finish a
            -- board, and the window must not stay busy until they come back.
            UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardInteraction')
                .ReleasePlayer(gm, key)
            UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver')
                .OnExit(gm, key)
        end
    end
end

-- Reconnect counterpart: the roster marks the player online again (or joins them to a
-- running encounter if they were never in it) and the pause lifts.
function PlayerController:UGC_PlayerReconnectedEvent(IsRecovered)
    if type(PlayerController.SuperClass.UGC_PlayerReconnectedEvent) == 'function' then
        PlayerController.SuperClass.UGC_PlayerReconnectedEvent(self, IsRecovered)
    end
    if self:HasAuthority() then
        local key = UGCGameSystem.GetPlayerKeyByPlayerController(self)
        if type(key) == 'number' and key >= 0 then
            -- No alive evidence here in either reconnect flavour: a silent reconnect
            -- keeps the pawn (the authoritative probe still works), and a kill-process
            -- reconnect has no rebuilt pawn yet, so the probe honestly excludes an
            -- unknown player until a respawn/login re-runs this. Claiming "alive" would
            -- add a still-dead player to the roster and stop the team from failing.
            UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver')
                .OnLogin(UGCGameSystem.GetGameMode(), key)
        end
    end
end

return PlayerController
