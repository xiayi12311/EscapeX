---@class BP_ZS_WindowPoint_C:AActor
---@field WindowInteractionQuery UBoxComponent
---@field VaultBlocker UBoxComponent
---@field InsideLanding USceneComponent
---@field InteractionPoint USceneComponent
---@field BoardRoot USceneComponent
---@field OutsideApproach UArrowComponent
---@field DefaultSceneRoot USceneComponent
---@field EncounterId FString
---@field PointId FString
---@field Enabled bool
---@field OutsideDistance float
---@field OutsideFloorOffset float
---@field InsideFloorOffset float
---@field BoardHeightOffset float
---@field InteractionDepthOffset float
---@field VaultSkillClass UClass
---@field QueueEnabled bool
---@field BoardsPerWindow int32
---@field BoardDurability float
---@field InstallSeconds float
---@field InstallRange float
---@field VaultDistance float
---@field StartRadius float
---@field LandingRadius float
---@field FootTolerance float
---@field NavProjectionHeight float
---@field FloorBelow float
---@field InteractIn float
---@field BoardWidth float
---@field SlotSpacing float
---@field GateHalfDepth float
---@field GateHalfHeight float
---@field GateUp float
---@field QueryIn float
---@field QueryHalfDepth float
---@field QueryHalfWidth float
---@field QueryHalfHeight float
---@field PreinstalledBoards int32
--Edit Below--
---@type BP_ZS_WindowPoint_C
local Point = {DefenseBoardSlots = '', DefenseBoardInteractionState = {Available = false}}
local Presentation = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardPresentation')

function Point:GetReplicatedProperties()
    return 'DefenseBoardSlots', 'DefenseBoardInteractionState'
end

function Point:ReceiveBeginPlay()
    Point.SuperClass.ReceiveBeginPlay(self)
    Presentation.Begin(self)
end

function Point:OnRep_DefenseBoardSlots()
    Presentation.Apply(self, true)
end

function Point:SetDefenseBoardSlots(slots)
    self.DefenseBoardSlots = slots
    Presentation.Apply(self, true)
end

function Point:ReceiveEndPlay(reason)
    Presentation.End(self)
    Point.SuperClass.ReceiveEndPlay(self, reason)
end

return Point
