local UGCPlayerPawn = {}

function UGCPlayerPawn:ReceiveBeginPlay()
    self.bVaultIsOpen = true
    UGCPlayerPawn.SuperClass.ReceiveBeginPlay(self)
    local Loadout = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestLoadout')
    Loadout.Schedule(self)
end

function UGCPlayerPawn:ReceiveEndPlay(Reason)
    local Loadout = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestLoadout')
    Loadout.Cancel(self)
    UGCPlayerPawn.SuperClass.ReceiveEndPlay(self, Reason)
end

--[[
function UGCPlayerPawn:ReceiveTick(DeltaTime)
    UGCPlayerPawn.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function UGCPlayerPawn:ReceiveEndPlay()
    UGCPlayerPawn.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function UGCPlayerPawn:GetAvailableServerRPCs()
    return
end
--]]

function UGCPlayerPawn:GetReplicatedProperties()
    return {"__SubObjectRepList", "Lazy"}
end


return UGCPlayerPawn
