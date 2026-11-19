local Flight = UGCGameSystem.UGCRequire('Script.Gameplay.Debug.GMFlight')
local UGCPlayerPawn = {EscapeXGMFlight = false}

function UGCPlayerPawn:ReceiveBeginPlay()
    self.bVaultIsOpen = true
    self.IsOpenShovelAbility = true
    UGCPlayerPawn.SuperClass.ReceiveBeginPlay(self)
    local Loadout = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseTestLoadout')
    Loadout.Schedule(self)
end

function UGCPlayerPawn:ReceiveEndPlay(Reason)
    Flight.StopInput(self)
    if self.EscapeXGMAmmoTimer then
        UGCGameSystem.UGCRequire('Script.Gameplay.Debug.GMInventory').StopAmmo(self)
    end
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
    return {"__SubObjectRepList", "Lazy"}, 'EscapeXGMFlight'
end

function UGCPlayerPawn:OnRep_EscapeXGMFlight()
    Flight.Apply(self, self.EscapeXGMFlight)
end


return UGCPlayerPawn
