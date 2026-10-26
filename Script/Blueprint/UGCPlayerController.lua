local Capture=UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureService')
local PlayerController={}

function PlayerController:UGC_PlayerLostConnectionEvent()
    PlayerController.SuperClass.UGC_PlayerLostConnectionEvent(self)
    if self:HasAuthority() then
        Capture.CancelPlayer(UGCGameSystem.GetGameMode(),self,'PLAYER_UNAVAILABLE')
    end
end

return PlayerController
