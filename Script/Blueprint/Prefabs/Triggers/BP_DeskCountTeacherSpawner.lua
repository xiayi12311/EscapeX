---@class BP_DeskCountTeacherSpawner_C:ActivityBaseActor
---@field SpawnPoint USceneComponent
--Edit Below--
local Service = UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskTeacherSpawner')
local Spawner = {}

function Spawner:ReceiveBeginPlay()
    Spawner.SuperClass.ReceiveBeginPlay(self)
    if self:HasAuthority() then
        local gm = UGCGameSystem.GetGameMode()
        if not Service.Register(gm, self) then
            ugcprint('[DeskTeacherSpawner] ERROR: marker registration failed')
        end
    end
end

function Spawner:ReceiveEndPlay(reason)
    if self:HasAuthority() then Service.Unregister(UGCGameSystem.GetGameMode(), self) end
    Spawner.SuperClass.ReceiveEndPlay(self, reason)
end

return Spawner
