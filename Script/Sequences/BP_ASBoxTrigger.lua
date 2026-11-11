---@class BP_ASBoxTrigger_C:UBoxComponent
---@field SequenceComponentName FString
---@field Enabled bool
local BP_ASBoxTrigger = {}

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

-- Each copied component owns its own round-local latch and AS selection.
function BP_ASBoxTrigger:ReceiveBeginPlay()
    BP_ASBoxTrigger.SuperClass.ReceiveBeginPlay(self)
    self.ASHasTriggered = false
    local owner = self:GetOwner()
    if not valid(owner) then return end
    local sequence = owner[self.SequenceComponentName]
    if not valid(sequence) or sequence.StartPlay == nil or sequence.StopPlay == nil then
        ugcprint('[ASBoxTrigger] Invalid Actor Sequence component: '..tostring(self.SequenceComponentName))
        return
    end
    self.ASTarget = sequence
    if owner:HasAuthority() then
        self.OnComponentBeginOverlap:Add(self.OnPlayerEnter, self)
    end
end

function BP_ASBoxTrigger:OnPlayerEnter(_, otherActor)
    local owner = self:GetOwner()
    if not valid(owner) or not owner:HasAuthority() then return end
    if not self.Enabled or self.ASHasTriggered or not valid(self.ASTarget) then return end
    if not valid(otherActor) then return end
    local ok, playerKey = pcall(UGCGameSystem.GetPlayerKeyByPlayerPawn, otherActor)
    if not ok or type(playerKey) ~= 'number' or playerKey < 0 then return end
    -- Latch before RPC: overlapping capsule/mesh events cannot replay the AS.
    self.ASHasTriggered = true
    UnrealNetwork.CallUnrealRPC_Multicast(self, 'MulticastRPC_PlaySequence')
end

-- Reliable multicast on the replicated component; no client-to-server RPC.
function BP_ASBoxTrigger:MulticastRPC_PlaySequence()
    if not valid(self.ASTarget) then
        ugcprint('[ASBoxTrigger] Actor Sequence unavailable: '..tostring(self.SequenceComponentName))
        return
    end
    self.ASTarget:StopPlay()
    self.ASTarget:StartPlay(0, true)
end

function BP_ASBoxTrigger:ReceiveEndPlay(reason)
    local owner = self:GetOwner()
    if valid(owner) and owner:HasAuthority() then
        self.OnComponentBeginOverlap:Remove(self.OnPlayerEnter, self)
    end
    self.ASTarget = nil
    BP_ASBoxTrigger.SuperClass.ReceiveEndPlay(self, reason)
end

return BP_ASBoxTrigger
