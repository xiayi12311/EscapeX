---@class BP_CutsceneTriggerBase_C:ActivityBaseActor
---@field TriggerArea UBoxComponent
---@field CutsceneSequencePath FString
---@field CutscenePlayRate float
---@field CutsceneStartTime float
---@field CutsceneRestoreState bool
---@field EffectAudience int
---@field EffectTriggerMode int
---@field EffectCooldown float
---@field EffectSoundPath FString
---@field EffectEnabled bool
--Edit Below--
local function NewCutsceneTriggerClass()
    local Trigger = {}

    local function valid(o)
        return o ~= nil and KismetSystemLibrary.IsValid(o)
    end

    local function releaseCutscene(self)
        self.CutscenePrepareGeneration = (self.CutscenePrepareGeneration or 0) + 1
        self.CutscenePreloadPending = false
        if valid(self.CutscenePlayer) then
            pcall(function() self.CutscenePlayer:Stop() end)
        end
        if valid(self.CutsceneActor) then
            pcall(function() self.CutsceneActor:K2_DestroyActor() end)
        end
        self.CutscenePlayer = nil
        self.CutsceneActor = nil
        self.CutscenePrepared = false
        self.CutscenePlaybackStarted = false
        self.CutsceneBindingsReady = false
    end

    local function stopCutscene(self)
        releaseCutscene(self)
    end

    local function prepareCutscenePlayer(self, sequence)
        if self.CutscenePrepared and valid(self.CutscenePlayer) and valid(self.CutsceneActor) then
            return true
        end
        if not valid(sequence) then return false end

        local playRate = tonumber(self.CutscenePlayRate) or 1
        if playRate <= 0 then
            ugcprint('[CutsceneTrigger] CutscenePlayRate must be greater than zero')
            return false
        end
        local startTime = tonumber(self.CutsceneStartTime) or 0
        local playerClass = self.CutscenePlayerClass
        if not valid(playerClass) then
            playerClass = UE.LoadClass('/Script/LevelSequence.LevelSequencePlayer')
            self.CutscenePlayerClass = playerClass
        end
        local factory = self.CutscenePlayerFactory
        if not valid(factory) then
            factory = valid(playerClass) and UGCObjectUtility.GetClassDefaultObject(playerClass)
            self.CutscenePlayerFactory = factory
        end
        if not valid(factory) then
            ugcprint('[CutsceneTrigger] failed to load LevelSequencePlayer factory')
            return false
        end

        local player, sequenceActor = factory.CreateLevelSequencePlayer(
            self,
            sequence,
            {
                LoopCount=0,
                PlayRate=playRate,
                StartTime=startTime,
                bRestoreState=self.CutsceneRestoreState == true,
            },
            nil
        )
        if not (valid(player) and valid(sequenceActor)) then
            ugcprint('[CutsceneTrigger] failed to create LevelSequence player')
            return false
        end

        self.CutscenePlayer = player
        self.CutsceneActor = sequenceActor
        self.CutscenePrepared = true
        self.CutscenePlaybackStarted = false
        self.CutsceneBindingsReady = self:ConfigureCutsceneBindings(sequenceActor, player) ~= false
        return true
    end

    local function finishPreparingCutscene(self, sequence, generation)
        if not valid(self)
            or generation ~= self.CutscenePrepareGeneration
            or self.CutscenePlaybackStarted then
            return
        end
        self.CutscenePreloadPending = false
        if not valid(sequence) then
            ugcprint('[CutsceneTrigger] async sequence preload failed')
            return
        end
        self.CutsceneSequence = sequence
        if prepareCutscenePlayer(self, sequence) then
            ugcprint('[CutsceneTrigger] preloaded and prepared sequence: '..tostring(self.CutsceneSequencePath))
        end
    end

    function Trigger:PrepareCutsceneAssets()
        if self:HasAuthority() or self.CutscenePlaybackStarted then return end
        if valid(self.CutsceneSequence) then
            prepareCutscenePlayer(self, self.CutsceneSequence)
            return
        end
        if self.CutscenePreloadPending then return end
        local sequencePath = self.CutsceneSequencePath
        if type(sequencePath) ~= 'string' or sequencePath == '' then
            ugcprint('[CutsceneTrigger] cutscene sequence path is not configured')
            return
        end

        self.CutscenePrepareGeneration = (self.CutscenePrepareGeneration or 0) + 1
        local generation = self.CutscenePrepareGeneration
        self.CutscenePreloadPending = true
        local trigger = self
        local started = UGCObjectUtility.AsyncLoadObject(sequencePath, function(sequence)
            finishPreparingCutscene(trigger, sequence, generation)
        end, nil)
        if not started then
            self.CutscenePreloadPending = false
            ugcprint('[CutsceneTrigger] failed to start sequence preload: '..tostring(sequencePath))
        end
    end

    function Trigger:OnCutsceneFinished()
        self.CutscenePlayer = nil
        if valid(self.CutsceneActor) then self.CutsceneActor:K2_DestroyActor() end
        self.CutsceneActor = nil
        self.CutscenePrepared = false
        self.CutscenePlaybackStarted = false
        self.CutsceneBindingsReady = false
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
                ugcprint('[CutsceneTrigger] TriggerArea must enable Generate Overlap Events')
            end
        else
            self:PrepareCutsceneAssets()
        end
    end

    -- Subclasses bind possessable tracks here. Spawnable tracks need no binding.
    function Trigger:ConfigureCutsceneBindings(sequenceActor, player)
        return true
    end

    -- Server-only public entry point for overlap or external gameplay triggers.
    function Trigger:TryTriggerEffect(playerKey)
        if not self:HasAuthority() or not self.EffectEnabled then return false end
        if type(playerKey) ~= 'number' or playerKey < 0 then return false end
        local mode = self.EffectTriggerMode
        if mode ~= 0 and mode ~= 1 and mode ~= 2 then
            ugcprint('[CutsceneTrigger] invalid trigger mode: '..tostring(mode))
            return false
        end
        if self.EffectAudience ~= 0 and self.EffectAudience ~= 1 then
            ugcprint('[CutsceneTrigger] invalid audience: '..tostring(self.EffectAudience))
            return false
        end
        if mode == 1 and self.EffectHasTriggered then return false end
        if mode == 2 and self.EffectTriggeredPlayers[playerKey] then return false end
        local now = KismetSystemLibrary.GetGameTimeInSeconds(self)
        if type(now) ~= 'number' then
            ugcprint('[CutsceneTrigger] server clock unavailable')
            return false
        end
        if self.EffectLastTriggerTime and now - self.EffectLastTriggerTime < self.EffectCooldown then
            return false
        end
        self.EffectHasTriggered = true
        self.EffectTriggeredPlayers[playerKey] = true
        self.EffectLastTriggerTime = now
        UnrealNetwork.CallUnrealRPC_Multicast(self, 'MulticastRPC_PlayCutscene', self.EffectAudience, playerKey)
        return true
    end

    function Trigger:OnEffectEnter(_, otherActor, otherComp)
        if not self:HasAuthority() or not valid(otherActor) or not valid(otherComp) then return end
        local ok, key = pcall(UGCGameSystem.GetPlayerKeyByPlayerPawn, otherActor)
        if not ok or type(key) ~= 'number' or key < 0 then return end
        local components = self.EffectOccupants[otherActor]
        if not components then
            components = {}
            self.EffectOccupants[otherActor] = components
        end
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

    function Trigger:ResetEffectTrigger()
        if not self:HasAuthority() then return false end
        self.EffectHasTriggered = false
        self.EffectTriggeredPlayers = {}
        self.EffectLastTriggerTime = nil
        return true
    end

    function Trigger:MulticastRPC_PlayCutscene(audience, playerKey)
        if self:HasAuthority() then return end
        if audience == 1 then
            local pc = UGCGameSystem.GetLocalPlayerController()
            if not valid(pc) or UGCGameSystem.GetPlayerKeyByPlayerController(pc) ~= playerKey then
                return
            end
        end

        if self.CutscenePlaybackStarted then releaseCutscene(self) end

        local sequencePath = self.CutsceneSequencePath
        if type(sequencePath) ~= 'string' or sequencePath == '' then
            ugcprint('[CutsceneTrigger] cutscene sequence path is not configured')
            return
        end
        local sequence = self.CutsceneSequence
        if not valid(sequence) then
            -- The trigger may be entered before its async preload completes.
            self.CutscenePrepareGeneration = (self.CutscenePrepareGeneration or 0) + 1
            self.CutscenePreloadPending = false
            sequence = UE.LoadObject(sequencePath)
            self.CutsceneSequence = sequence
        end
        if not valid(sequence) then
            ugcprint('[CutsceneTrigger] sequence not found: '..tostring(sequencePath))
            return
        end

        if not (self.CutscenePrepared and valid(self.CutscenePlayer) and valid(self.CutsceneActor)) then
            if not prepareCutscenePlayer(self, sequence) then return end
        elseif not self.CutsceneBindingsReady then
            self.CutsceneBindingsReady = self:ConfigureCutsceneBindings(self.CutsceneActor, self.CutscenePlayer) ~= false
            if not self.CutsceneBindingsReady then
                ugcprint('[CutsceneTrigger] failed to prepare possessable bindings')
                return
            end
        end

        self.CutscenePlayer.OnFinished:Add(self.OnCutsceneFinished, self)
        self.CutscenePlayer:Play()
        self.CutscenePlaybackStarted = true

        if type(self.EffectSoundPath) == 'string' and self.EffectSoundPath ~= '' then
            local sound = UE.LoadObject(self.EffectSoundPath)
            if not valid(sound) then
                ugcprint('[CutsceneTrigger] audio asset not found: '..tostring(self.EffectSoundPath))
            else
                UGCSoundManagerSystem.PlaySoundAttachActor(sound, self, true)
            end
        end
    end

    function Trigger:StopCutscene()
        stopCutscene(self)
    end

    function Trigger:ReceiveEndPlay(reason)
        if self:HasAuthority() and valid(self.TriggerArea) then
            self.TriggerArea.OnComponentBeginOverlap:Remove(self.OnEffectEnter, self)
            self.TriggerArea.OnComponentEndOverlap:Remove(self.OnEffectLeave, self)
        end
        stopCutscene(self)
        Trigger.SuperClass.ReceiveEndPlay(self, reason)
    end

    Trigger.NewClass = NewCutsceneTriggerClass
    return Trigger
end

return NewCutsceneTriggerClass()
