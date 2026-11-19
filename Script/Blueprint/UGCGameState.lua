---@class UGCGameState_C:BP_UGCGameState_C
--Edit Below--
UGCGameSystem.UGCRequire('Script.Common.ue_enum_custom')
local DeskOutcomeConfig = UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskOutcomeConfig')
local UGCGameState = {ClassAirWallsRemoved = false}

function UGCGameState:GetReplicatedProperties()
    return 'ClassAirWallsRemoved'
end

function UGCGameState:OnRep_ClassAirWallsRemoved()
    if not self.ClassAirWallsRemoved or self:HasAuthority() then return end
    local tag = DeskOutcomeConfig.TaggedActorRemovals.RemoveClassAirWalls.Tag
    local walls = UGCActorComponentUtility.GetAllActorsWithTag(self, tag) or {}
    local disabled = 0
    for _,wall in pairs(walls) do
        if KismetSystemLibrary.IsValid(wall) and wall.ApplyClassAirWallRemoval then
            wall:ApplyClassAirWallRemoval()
            disabled = disabled + 1
        end
    end
    ugcprint('[DeskSearch] Applied classroom wall removal on client count='..disabled)
end
function UGCGameState:ReceiveBeginPlay()
	self.IsOpenShovelAbility = true
	self.SuperClass.ReceiveBeginPlay(self)
end
-- function UGCGameState:ReceiveTick(DeltaTime)

-- end
-- function UGCGameState:ReceiveEndPlay()
 
-- end
return UGCGameState;
