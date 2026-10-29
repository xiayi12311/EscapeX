---@class BP_EffectTriggerSkeletal_Rebuilt_C:BP_EffectTriggerBase_C
---@field EffectSequence UActorSequenceComponent
---@field EffectMesh USkeletalMeshComponent
--Edit Below--
-- Copy the method table so each bound blueprint has its own class metadata.
local Base = require('Script.Blueprint.Prefabs.Interactables.BP_EffectTriggerBase')
local EffectTriggerSkeletal = Base.NewClass()
return EffectTriggerSkeletal

