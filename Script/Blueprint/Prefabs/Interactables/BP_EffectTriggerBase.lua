---@class BP_EffectTriggerBase_C:ActivityBaseActor
---@field EffectSequence UActorSequenceComponent
---@field EffectMesh UStaticMeshComponent
---@field TriggerArea UBoxComponent
---@field DefaultSceneRoot USceneComponent
---@field EffectAudience int32
---@field EffectTriggerMode int32
---@field EffectCooldown float
---@field EffectSoundPath FString
---@field EffectEnabled bool
--Edit Below--
---@class BP_EffectTriggerBase_C:ActivityBaseActor
---@field TriggerArea UBoxComponent
---@field EffectMesh UStaticMeshComponent
---@field EffectSequence UActorSequenceComponent
---@field EffectAudience int
---@field EffectTriggerMode int
---@field EffectCooldown float
---@field EffectSoundPath FString
---@field EffectEnabled bool
local function NewTriggerClass()
local Trigger = {}

local function valid(o)
    return o ~= nil and KismetSystemLibrary.IsValid(o)
end

function Trigger:ReceiveBeginPlay()
    Trigger.SuperClass.ReceiveBeginPlay(self)
    if self:HasAuthority() then
        self.EffectOccupants = {}
        self.EffectTriggeredPlayers = {}
        self.EffectHasTriggered = false
        self.EffectLastTriggerTime = nil
        self.TriggerArea.OnComponentBeginOverlap:Add(self.OnEffectEnter, self)
        self.TriggerArea.OnComponentEndOverlap:Add(self.OnEffectLeave, self)
        self.TriggerArea:SetCollisionProfileName('Trigger')
        if not self.TriggerArea.bGenerateOverlapEvents then
            ugcprint('[EffectTrigger] TriggerArea must enable Generate Overlap Events')
        end
    end
end

-- Server-only public entry point for future non-overlap triggers.
function Trigger:TryTriggerEffect(playerKey)
    if not self:HasAuthority() or not self.EffectEnabled then return false end
    if type(playerKey) ~= 'number' or playerKey < 0 then return false end
    local mode = self.EffectTriggerMode
    if mode ~= 0 and mode ~= 1 and mode ~= 2 then
        ugcprint('[EffectTrigger] invalid trigger mode: '..tostring(mode)); return false
    end
    if self.EffectAudience ~= 0 and self.EffectAudience ~= 1 then
        ugcprint('[EffectTrigger] invalid audience: '..tostring(self.EffectAudience)); return false
    end
    if mode == 1 and self.EffectHasTriggered then return false end
    if mode == 2 and self.EffectTriggeredPlayers[playerKey] then return false end
    local now = KismetSystemLibrary.GetGameTimeInSeconds(self)
    if type(now) ~= 'number' then ugcprint('[EffectTrigger] server clock unavailable'); return false end
    if self.EffectLastTriggerTime and now - self.EffectLastTriggerTime < self.EffectCooldown then return false end
    self.EffectHasTriggered = true
    self.EffectTriggeredPlayers[playerKey] = true
    self.EffectLastTriggerTime = now
    UnrealNetwork.CallUnrealRPC_Multicast(self, 'MulticastRPC_PlayEffect', self.EffectAudience, playerKey)
    return true
end

function Trigger:OnEffectEnter(_, otherActor, otherComp)
    if not self:HasAuthority() or not valid(otherActor) or not valid(otherComp) then return end
    local ok, key = pcall(UGCGameSystem.GetPlayerKeyByPlayerPawn, otherActor)
    if not ok or type(key) ~= 'number' or key < 0 then return end
    local components = self.EffectOccupants[otherActor]
    if not components then components = {}; self.EffectOccupants[otherActor] = components end
    if components[otherComp] then return end
    local alreadyInside = next(components) ~= nil
    components[otherComp] = true
    if not alreadyInside then self:TryTriggerEffect(key) end
end

function Trigger:OnEffectLeave(_, otherActor, otherComp)
    if not self:HasAuthority() then return end
    local components = self.EffectOccupants[otherActor]
    if not components then return end
    components[otherComp] = nil
    if not next(components) then self.EffectOccupants[otherActor] = nil end
end

-- Clears once-per-round/player and cooldown history. Does not synthesize an enter.
function Trigger:ResetEffectTrigger()
    if not self:HasAuthority() then return false end
    self.EffectHasTriggered = false
    self.EffectTriggeredPlayers = {}
    self.EffectLastTriggerTime = nil
    return true
end

function Trigger:MulticastRPC_PlayEffect(audience, playerKey)
    if self:HasAuthority() then return end
    if audience == 1 then
        local pc = UGCGameSystem.GetLocalPlayerController()
        if not valid(pc) or UGCGameSystem.GetPlayerKeyByPlayerController(pc) ~= playerKey then return end
    end
    if not valid(self.EffectSequence) then
        ugcprint('[EffectTrigger] EffectSequence is missing'); return
    end
    self.EffectSequence:StopPlay()
    self.EffectSequence:StartPlay(0, true)
    if self.EffectSoundPath ~= '' then
        local sound = UE.LoadObject(self.EffectSoundPath)
        if not valid(sound) then
            ugcprint('[EffectTrigger] audio asset not found: '..tostring(self.EffectSoundPath))
        else
            UGCSoundManagerSystem.PlaySoundAttachActor(sound, self, true)
        end
    end
end

function Trigger:ReceiveEndPlay(reason)
    if self:HasAuthority() and valid(self.TriggerArea) then
        self.TriggerArea.OnComponentBeginOverlap:Remove(self.OnEffectEnter, self)
        self.TriggerArea.OnComponentEndOverlap:Remove(self.OnEffectLeave, self)
    end
    Trigger.SuperClass.ReceiveEndPlay(self, reason)
end

Trigger.NewClass = NewTriggerClass
return Trigger
end

return NewTriggerClass()




