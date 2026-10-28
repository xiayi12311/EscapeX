---@class BP_EffectTriggerSkeletal_C:BP_EffectTriggerBase_C
---@field EffectSequence UActorSequenceComponent
---@field EffectMesh USkeletalMeshComponent
--Edit Below--
-- Copy the method table so each bound blueprint has its own class metadata.
local Base = require('Script.Blueprint.Prefabs.Interactables.BP_EffectTriggerBase')
local EffectTriggerSkeletal = {}
for key, value in pairs(Base) do
    EffectTriggerSkeletal[key] = value
end
return EffectTriggerSkeletal

