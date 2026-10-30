---@class ZombieBossProj_C:PESkillProjectileBase
---@field ParticleSystem UParticleSystemComponent
---@field Sphere USphereComponent
--Edit Below--
local ZombieBossProj = {}
 
--[[
function ZombieBossProj:ReceiveBeginPlay()
    ZombieBossProj.SuperClass.ReceiveBeginPlay(self)
end
--]]

--[[
function ZombieBossProj:ReceiveTick(DeltaTime)
    ZombieBossProj.SuperClass.ReceiveTick(self, DeltaTime)
end
--]]

--[[
function ZombieBossProj:ReceiveEndPlay()
    ZombieBossProj.SuperClass.ReceiveEndPlay(self) 
end
--]]

--[[
function ZombieBossProj:GetReplicatedProperties()
    return
end
--]]

--[[
function ZombieBossProj:GetAvailableServerRPCs()
    return
end
--]]

return ZombieBossProj