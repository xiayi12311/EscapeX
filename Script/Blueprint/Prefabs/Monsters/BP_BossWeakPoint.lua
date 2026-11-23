---@class BP_BossWeakPoint_C:BP_UGC_GenericMobPawn_Base_C
---@field WeakPointMesh UStaticMeshComponent
---@field BreakPointCue UTextRenderComponent
---@field HitBox UCapsuleComponent
--Edit Below--
---@class BP_BossWeakPoint_C:BP_UGC_GenericMobPawn_Base_C
local WeakPoint = {}

function WeakPoint:PreOverrideDamage(damage, instigator, causer)
    local boss = self.BossWeakPointOwner
    if damage > 0 and instigator and UGCGameSystem.GetPlayerPawnByPlayerController(instigator)
        and boss and KismetSystemLibrary.IsValid(boss) then
        boss:ApplyWeakPointHit(self, damage, instigator, causer)
    end
    -- The weak point forwards damage to the Boss and has no separate health or death.
    return 0
end

return WeakPoint
