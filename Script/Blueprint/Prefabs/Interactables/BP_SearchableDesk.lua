---@class BP_SearchableDesk_C:ActivityBaseActor
---@field InteractionAnchor USceneComponent
---@field SearchClick UClickActorComponentBase
---@field SearchArea USphereComponent
---@field DeskContent UStaticMeshComponent
---@field Drawer UStaticMeshComponent
---@field DeskBody UStaticMeshComponent
---@field DeskRoot USceneComponent
---@field DefaultSceneRoot USceneComponent
---@field DeskSearchDuration float
---@field DeskInteractRadius float
---@field DeskCancelRadius float
---@field DeskOpenDuration float
---@field DeskRevealOffset float
---@field DeskOutcomePool FString
---@field DeskRequireStanding bool
--Edit Below--
local Service=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskSearchService')
local Presentation=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskPresentation')
local Focus=UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.DeskFocusPresentation')
local Desk={DeskState={State='Closed',ResetVersion=0,InteractionId=0}}

function Desk:GetReplicatedProperties() return 'DeskState' end

function Desk:ReceiveBeginPlay()
    Desk.SuperClass.ReceiveBeginPlay(self)
    if self.SearchArea then self.SearchArea:SetSphereRadius(self.DeskInteractRadius or 180,true) end
    if self:HasAuthority() then
        self.DeskRegisterTimer=UGCTimerUtility.CreateLuaTimer(0.1,function()
            if not KismetSystemLibrary.IsValid(self) then return end
            local gm=UGCGameSystem.GetGameMode()
            if gm and gm.DeskSearchManager then
                local id=KismetSystemLibrary.GetObjectName(self)
                local ok,reason=Service.Register(gm,self,id,{SearchDuration=self.DeskSearchDuration,
                    InteractRadius=self.DeskInteractRadius,CancelRadius=self.DeskCancelRadius,
                    OpenDuration=self.DeskOpenDuration,RevealOffset=self.DeskRevealOffset,
                    OutcomePoolId=self.DeskOutcomePool})
                if not ok then ugcprint('[DeskSearch] register failed '..tostring(reason)) end
                UGCTimerUtility.RemoveLuaTimer(self.DeskRegisterTimer)
                self.DeskRegisterTimer=nil
            end
        end,true)
    else
        Presentation.Begin(self)
    end
end

-- The native click component remains in the blueprint, but its old button and
-- action are disabled: the unified local focus UI uses the controller RPC instead.
function Desk:CheckDeskSearchNative(Click_Param)
    return false
end

function Desk:OnClickDeskSearch(Click_Param)
end

function Desk:OnRep_DeskState()
    if not self:HasAuthority() then
        Presentation.Apply(self,self.DeskState)
        -- the focus layer keeps its own active/focus bookkeeping from this event; without
        -- it a cancelled or completed search stays latched as "the active desk"
        Focus.DeskChanged(self,self.DeskState)
    end
end

function Desk:ReceiveEndPlay(Reason)
    if self.DeskRegisterTimer then UGCTimerUtility.RemoveLuaTimer(self.DeskRegisterTimer) end
    if self:HasAuthority() then
        Service.Unregister(UGCGameSystem.GetGameMode(),self)
    else
        Presentation.End(self)
        Focus.DeskRemoved(self)
    end
    Desk.SuperClass.ReceiveEndPlay(self,Reason)
end

return Desk
