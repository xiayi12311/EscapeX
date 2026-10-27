local DeskSearch=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskSearchService')
local Capture=UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureService')
local Focus=UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.DeskFocusPresentation')
local PlayerController={}

-- The controller is the stable local-session owner: pawns are replaced on respawn, so the
-- focus layer is armed here and follows pawn identity changes (see DeskFocusPresentation
-- Monitor comment for the measured pawn-hook failure).
function PlayerController:ReceiveBeginPlay()
    PlayerController.SuperClass.ReceiveBeginPlay(self)
    Focus.Monitor()
end

-- Client requests a start through its own controller; no player key or outcome is
-- accepted from the client. The existing service validates desk registration,
-- character state, range and exclusivity on the server.
function PlayerController:GetAvailableServerRPCs()
    return 'ServerRequestDeskSearch'
end

function PlayerController:ServerRequestDeskSearch(desk)
    if not self:HasAuthority() then return end
    local ok,reason=DeskSearch.StartSearch(UGCGameSystem.GetGameMode(),desk,self)
    if not ok then ugcprint('[DeskSearch] request rejected '..tostring(reason)) end
end

function PlayerController:UGC_PlayerLostConnectionEvent()
    PlayerController.SuperClass.UGC_PlayerLostConnectionEvent(self)
    if self:HasAuthority() then
        DeskSearch.CancelPlayer(UGCGameSystem.GetGameMode(),self,'DISCONNECTED')
        Capture.CancelPlayer(UGCGameSystem.GetGameMode(),self,'PLAYER_UNAVAILABLE')
    end
end

return PlayerController
