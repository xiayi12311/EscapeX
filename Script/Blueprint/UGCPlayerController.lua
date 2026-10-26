local DeskSearch=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskSearchService')
local Capture=UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureService')
local PlayerController={}

function PlayerController:UGC_PlayerLostConnectionEvent()
    PlayerController.SuperClass.UGC_PlayerLostConnectionEvent(self)
    if self:HasAuthority() then
        DeskSearch.CancelPlayer(UGCGameSystem.GetGameMode(),self,'DISCONNECTED')
        Capture.CancelPlayer(UGCGameSystem.GetGameMode(),self,'PLAYER_UNAVAILABLE')
    end
end

return PlayerController
