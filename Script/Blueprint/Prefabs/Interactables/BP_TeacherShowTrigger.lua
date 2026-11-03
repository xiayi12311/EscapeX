---@class BP_TeacherShowTrigger_C:BP_CutsceneTriggerBase_C
---@field TeacherActorTag FString
---@field CameraActorTag FString
--Edit Below--
local Base = require('Script.Blueprint.Prefabs.Interactables.BP_CutsceneTriggerBase')
local TeacherShowTrigger = Base.NewClass()

local function valid(o)
    return o ~= nil and KismetSystemLibrary.IsValid(o)
end

local function findActorByTag(context, tag)
    if type(tag) ~= 'string' or tag == '' then return nil end
    local actors = GameplayStatics.GetAllActorsWithTag(context, tag, {}) or {}
    return actors[1]
end

function TeacherShowTrigger:ConfigureCutsceneBindings(sequenceActor, player)
    local teacher = findActorByTag(self, self.TeacherActorTag)
    local camera = findActorByTag(self, self.CameraActorTag)
    if not valid(teacher) or not valid(camera) then
        ugcprint('[TeacherShowTrigger] possessable actors not found for tags: '
            ..tostring(self.TeacherActorTag)..', '..tostring(self.CameraActorTag))
        return false
    end

    sequenceActor:UGCAddBinding(teacher, 'SK_NewWorld_TianTan_NPC_F')
    sequenceActor:UGCAddBinding(camera, 'TeacherCamera')
    return true
end

return TeacherShowTrigger
