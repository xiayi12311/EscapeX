---@class UGCGameMode_C:BP_UGCGameBase_C
--Edit Below--
local UGCGameMode = {}
local TestRevive = UGCGameSystem.UGCRequire("Script.Common.TestAutoRevive")
local DeskSearch = UGCGameSystem.UGCRequire("Script.Gameplay.Desk.DeskSearchService")
local Capture = UGCGameSystem.UGCRequire("Script.Gameplay.Capture.CaptureService")

function UGCGameMode:ReceiveBeginPlay()
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
end

function UGCGameMode:ReceiveEndPlay(Reason)
    Capture.Shutdown(self)
    DeskSearch.Shutdown(self)
    UGCGameMode.SuperClass.ReceiveEndPlay(self, Reason)
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

-- A confirmed grab starts a fresh desk-search round for every player. Reset desks
-- first so all active searches and delayed reveals are invalidated before count 0.
function UGCGameMode:OnPlayerCaptured(PlayerKey, CaptureSessionId)
    assert(self:HasAuthority(), 'capture round reset is server-only')
    local ok, reason = self:ResetAllDesks()
    assert(ok, 'capture desk reset failed: ' .. tostring(reason))
    assert(self:ResetOpenedCount(), 'capture desk count reset failed')
    ugcprint('[DeskSearch] Round reset on capture player=' .. tostring(PlayerKey)
        .. ' session=' .. tostring(CaptureSessionId))
end

---玩家被淘汰事件，基类实现为空，生效范围：服务器
function UGCGameMode:UGC_PlayerKilledEvent(Killer, VictimPlayer, VictimPawn, DamageType)
    -- Record the death position before the capture cleanup can move the pawn.
    TestRevive.onKilled(self, Killer, VictimPlayer, VictimPawn, DamageType)
    -- An eliminated player must not keep holding a prison post or block their carrier.
    Capture.CancelVictim(self, VictimPlayer, VictimPawn, 'PLAYER_DEAD')
end

---玩家复活事件，基类实现为空，生效范围：服务器
function UGCGameMode:UGC_PlayerRespawnEvent(RespawnedController)
    TestRevive.onRespawn(self, RespawnedController)
end

return UGCGameMode
