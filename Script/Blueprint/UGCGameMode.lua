---@class UGCGameMode_C:BP_UGCGameBase_C
--Edit Below--
local UGCGameMode = {}
local TestRevive = UGCGameSystem.UGCRequire("Script.Common.TestAutoRevive")
local DeskSearch = UGCGameSystem.UGCRequire("Script.Gameplay.Desk.DeskSearchService")
local PushPull = UGCGameSystem.UGCRequire("Script.Gameplay.PushPull.PushPullService")
local Capture = UGCGameSystem.UGCRequire("Script.Gameplay.Capture.CaptureService")
local FirstPerson = UGCGameSystem.UGCRequire("Script.Gameplay.FirstPerson")

local function defenseService(gameMode)
    if gameMode.ZombieDefenseService then return gameMode.ZombieDefenseService end
    local Service = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseService')
    local Catalog = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseCatalog')
    local service, reason = Service.New(gameMode, Catalog)
    gameMode.ZombieDefenseService = service
    return service, reason
end

local function startBoardInstalls(gameMode)
    local service, reason = defenseService(gameMode)
    local ok
    if service then ok, reason = service:PrepareBoards() end
    if not ok then
        local Board = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardInteraction')
        ugcprint('[ZombieDefense] Window setup failed: ' .. Board.ErrorText(reason))
        return
    end
    if not next(service.Barricades) then return true end
    gameMode.ZombieBoardTimer = UGCTimerUtility.CreateLuaTimer(service.Catalog.BoardInstallCheckSeconds, function()
        service:TickBoardInstalls()
    end, true)
    return true
end

function UGCGameMode:ReceiveBeginPlay()
    self.IsOpenShovelAbility = true
    UGCGameMode.SuperClass.ReceiveBeginPlay(self)
    if self:HasAuthority() and self.HTBuildNavigationOnStart then
        -- This map has no exported .navmesh yet. Build its configured bounds
        -- asynchronously; behavior tasks retain their destinations while waiting.
        UGCNavigationSystem.AsyncBuildNavmesh(self, "Mannequin")
        ugcprint("[HeadTeacher] Initial dynamic navigation build requested")
    end
    TestRevive.setup(self)
    DeskSearch.Setup(self)
    Capture.Setup(self)
    PushPull.Setup(self)
    if self:HasAuthority() then startBoardInstalls(self) end
end

function UGCGameMode:ReceiveEndPlay(Reason)
    self:ShutdownZombieDefense()
    PushPull.Shutdown(self)
    FirstPerson.Shutdown()
    Capture.Shutdown(self)
    DeskSearch.Shutdown(self)
    UGCGameMode.SuperClass.ReceiveEndPlay(self, Reason)
end

function UGCGameMode:UGC_PlayerLoginEvent(PlayerController)
    if self:HasAuthority() then
        FirstPerson.Schedule(PlayerController)
        local key = UGCGameSystem.GetPlayerKeyByPlayerController(PlayerController)
        if type(key) == 'number' and key >= 0 then
            UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver').OnLogin(self, key)
        end
    end
end

-- PlayerExitEvent fires before the controller and state are destroyed, so the key
-- is still readable. A disconnect neither auto-revives the player nor holds the
-- team open; the roster entry is kept for reconnect.
function UGCGameMode:UGC_PlayerExitEvent(PlayerController)
    if not self:HasAuthority() then return end
    local key = UGCGameSystem.GetPlayerKeyByPlayerController(PlayerController)
    if type(key) ~= 'number' or key < 0 then return end
    -- A player who leaves cannot finish a board; release it before the roster
    -- records the disconnect so the window does not stay busy forever.
    UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardInteraction')
        .ReleasePlayer(self, key)
    UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver').OnExit(self, key)
end

function UGCGameMode:GetOpenedCount()
    return DeskSearch.GetOpenedCount(self)
end

function UGCGameMode:ResetOpenedCount()
    return DeskSearch.ResetOpenedCount(self)
end

function UGCGameMode:ResetDesk(DeskActor)
    return DeskSearch.ResetDesk(self, DeskActor)
end

function UGCGameMode:ResetAllDesks()
    return DeskSearch.ResetAllDesks(self)
end

-- A confirmed grab resets desks for everyone and restores the last count checkpoint.
-- Reset desks first to invalidate active searches and delayed reveals.
function UGCGameMode:OnPlayerCaptured(PlayerKey, CaptureSessionId)
    assert(self:HasAuthority(), 'capture round reset is server-only')
    PushPull.CancelPlayer(self, PlayerKey, 'PLAYER_BUSY')
    local ok, reason = self:ResetAllDesks()
    assert(ok, 'capture desk reset failed: ' .. tostring(reason))
    assert(self:ResetOpenedCount(), 'capture desk count reset failed')
    ugcprint('[DeskSearch] Round reset on capture player=' .. tostring(PlayerKey)
        .. ' session=' .. tostring(CaptureSessionId))
end

---玩家被淘汰事件，基类实现为空，生效范围：服务器
function UGCGameMode:UGC_PlayerKilledEvent(Killer, VictimPlayer, VictimPawn, DamageType)
    -- The base event is server-only; the guard keeps a stray client-side dispatch from
    -- tripping the roster's server assert. Marking the roster must happen before the
    -- test revive schedules anything, or the death would slip past the encounter policy.
    if self:HasAuthority() then
        local Driver = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver')
        local victimKey = TestRevive.playerKey(VictimPlayer,VictimPawn)
        Driver.OnKilled(self,victimKey)
        -- A dead installer must not finish a board on the next tick from wherever
        -- the corpse ends up; releasing here is the authoritative interruption.
        UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardInteraction')
            .ReleasePlayer(self, victimKey)
    end
    -- Record the death position before the capture cleanup can move the pawn.
    TestRevive.onKilled(self, Killer, VictimPlayer, VictimPawn, DamageType)
    -- An eliminated player must not keep holding a prison post or block their carrier.
    Capture.CancelVictim(self, VictimPlayer, VictimPawn, 'PLAYER_DEAD')
    PushPull.CancelVictim(self, VictimPlayer, VictimPawn, 'PLAYER_DEAD')
end

---玩家复活事件，基类实现为空，生效范围：服务器
function UGCGameMode:UGC_PlayerRespawnEvent(RespawnedController)
    local key = TestRevive.playerKey(RespawnedController,nil)
    if self:HasAuthority() then
        local Team=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTeamPolicy')
        Team.OnRespawn(self,key)
    end
    TestRevive.onRespawn(self, RespawnedController)
    if self:HasAuthority() then
        FirstPerson.Schedule(RespawnedController)
        -- A player who died before joining (and was already respawned by another
        -- path) would otherwise stay outside the roster forever: the join check at
        -- login requires IsAlive. Re-run the idempotent join on respawn so such a
        -- player either returns to their existing entry or joins an active one.
        -- knownAlive=true: this event itself proves the player is alive, and the pawn
        -- may not be rebuilt yet at this point.
        if type(key) == 'number' and key >= 0 then
            UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver').OnLogin(self, key, true)
        end
    end
end

-- Explicit server entry only. Never started by BeginPlay; caller owns team rules.
function UGCGameMode:StartZombieDefense(EncounterId, InstanceId, PlayerCount)
    assert(self:HasAuthority(), 'DEFENSE_SERVER_ONLY')
    local service, reason = defenseService(self)
    if not service then return false, reason end
    return service:Start(EncounterId, InstanceId, PlayerCount,
        KismetSystemLibrary.GetGameTimeInSeconds(self))
end

function UGCGameMode:StepZombieDefense(EncounterId, TeamFailed, DeferVictory)
    assert(self:HasAuthority(), 'DEFENSE_SERVER_ONLY')
    if not self.ZombieDefenseService then return nil, 'DEFENSE_NOT_INITIALIZED' end
    return self.ZombieDefenseService:Step(EncounterId,
        KismetSystemLibrary.GetGameTimeInSeconds(self), TeamFailed, DeferVictory)
end

function UGCGameMode:RequestZombieDefenseRevive(EncounterId,PlayerKey)
    local Team=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTeamPolicy')
    return Team.RequestRevive(self,EncounterId,PlayerKey)
end

function UGCGameMode:ResetZombieDefenseForGM()
    assert(self:HasAuthority(), 'DEFENSE_SERVER_ONLY')
    self:ShutdownZombieDefense(true)
    if not startBoardInstalls(self) then return false, 'BOARD_PREPARATION_FAILED' end
    return true
end

function UGCGameMode:ShutdownZombieDefense(resetForGM)
    if self.ZombieBoardTimer then
        UGCTimerUtility.RemoveLuaTimer(self.ZombieBoardTimer)
        self.ZombieBoardTimer = nil
    end
    local Driver = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestDriver')
    Driver.Stop(self)
    local Team=UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTeamPolicy')
    Team.Shutdown(self)
    if self.ZombieDefenseService then
        self.ZombieDefenseService:Shutdown(resetForGM)
        self.ZombieDefenseService = nil
    end
end

return UGCGameMode
