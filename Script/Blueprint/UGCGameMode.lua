---@class UGCGameMode_C:BP_UGCGameBase_C
--Edit Below--
local UGCGameMode = {}
local TestRevive = UGCGameSystem.UGCRequire("Script.Common.TestAutoRevive")

function UGCGameMode:ReceiveBeginPlay()
    UGCGameMode.SuperClass.ReceiveBeginPlay(self)
    if self:HasAuthority() and self.HTBuildNavigationOnStart then
        -- This map has no exported .navmesh yet. Build its configured bounds
        -- asynchronously; behavior tasks retain their destinations while waiting.
        UGCNavigationSystem.AsyncBuildNavmesh(self, "Mannequin")
        ugcprint("[HeadTeacher] Initial dynamic navigation build requested")
    end
    TestRevive.setup(self)
end

---玩家被淘汰事件，基类实现为空，生效范围：服务器
function UGCGameMode:UGC_PlayerKilledEvent(Killer, VictimPlayer, VictimPawn, DamageType)
    TestRevive.onKilled(self, Killer, VictimPlayer, VictimPawn, DamageType)
end

---玩家复活事件，基类实现为空，生效范围：服务器
function UGCGameMode:UGC_PlayerRespawnEvent(RespawnedController)
    TestRevive.onRespawn(self, RespawnedController)
end

return UGCGameMode
