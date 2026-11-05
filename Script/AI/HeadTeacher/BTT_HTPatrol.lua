local H = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCommon")
local T = {}
local function clearDetectionSkill(self, p)
    local skill = self.DetectionSkill
    self.DetectionSkill = nil
    self.DetectionStarted = nil
    self.DetectionPending = nil
    if H.valid(skill) and H.valid(p) then
        UGCPersistEffectSystem.RemoveSkillInstance(p, skill)
    end
end

local function startDetectionSkill(self, p)
    local path = H.config(p, 'HTDetectSkillClass')
    local cls = UGCObjectUtility.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(path))
    if not cls then H.log(p, 'detect-skill', 'Discovery skill class unavailable: '..tostring(path)); return false end
    local skill = UGCPersistEffectSystem.AddSkillByClass(p, cls)
    if not H.valid(skill) then H.log(p, 'detect-skill', 'Could not add discovery skill'); return false end
    self.DetectionSkill = skill
    if not skill:CanActivateSkill() then H.log(p, 'detect-skill', 'Discovery skill cannot activate'); return false end
    skill:ActivateSkill()
    if not skill:IsActivating() then H.log(p, 'detect-skill', 'Discovery skill did not activate'); return false end
    self.DetectionStarted = true
    return true
end
function T:ReceiveExecuteAI(_,p)
    if not H.begin(self,p,"Patrol") then return end
    self.ScanElapsed = 100
    self.VisibleSince = {}
    self.WaitTime, self.WaitElapsed = nil, nil
    H.traceEvent(string.format("patrol_enter lock=%s %s", tostring(H.valid(H.target(p))), H.snapshot(p,H.target(p))))
    -- A tree restart must not replace a lock left by an interrupted chase.
    if H.valid(H.target(p)) then
        p.HTDetectionEnabled=false
        self:FinishExecute(true)
        return
    end
    H.setBattle(p,false)
    p.HTDetectionEnabled = true
    H.bb(p):SetValueAsBool("CatchReady",false)
    self:ReceiveTickAI(nil,p,0)
end
function T:ReceiveTickAI(_,p,dt)
    H.progress(p,dt)
    if self.DetectionPending then
        H.stop(p)
        if not H.alive(H.target(p)) then
            clearDetectionSkill(self,p)
            H.bb(p):ClearValue('LockedTarget')
            H.publishVision(p,{})
            p.HTDetectionEnabled=true
            self.VisibleSince={}
        elseif self.DetectionStarted and not self.DetectionSkill:IsActivating()
            and self.DetectionSkill.HTCompletionReason == 0 then
            clearDetectionSkill(self,p)
            self:FinishExecute(true)
        elseif self.DetectionStarted and not self.DetectionSkill:IsActivating() then
            H.log(p,'detect-skill','Discovery skill stopped without completing; chase is blocked')
        end
        return
    end
    local route, d = H.routes(p), H.data(p)
    if #route == 0 then
        self.VisibleSince={}
        H.publishVision(p,{})
        H.stop(p)
        return
    end
    d.index = math.max(1, math.min(d.index,#route))
    if not H.valid(route[d.index]) then
        H.log(p,"route-deleted","Current route waypoint was deleted; waiting for route repair")
        self.VisibleSince={}
        self.WaitTime, self.WaitElapsed = nil, nil
        H.publishVision(p,{})
        H.stop(p); return
    end
    self.ScanElapsed = self.ScanElapsed+dt
    if self.ScanElapsed >= H.config(p,"HTDetectionInterval") then
        self.ScanElapsed=0
        local _,visible=H.scan(p)
        local previous=self.VisibleSince
        local current={}
        local target=nil
        local delay=H.config(p,'HTDetectionDelay')
        if type(delay)~='number' or delay<0 then
            H.log(p,'detection-delay','Invalid HTDetectionDelay; acquisition disabled')
            self.VisibleSince={}
            H.publishVision(p,{})
            return
        end
        for _,entry in ipairs(visible) do
            local actor=entry.actor
            local since=previous[actor] or d.clock
            current[actor]=since
            entry.progress = delay == 0 and 1 or math.min(1, math.max(0, (d.clock-since)/delay))
            if not target and d.clock-since+0.000001>=delay then target=actor end
        end
        self.VisibleSince=current
        local lockedKey = target and UGCGameSystem.GetPlayerKeyByPlayerPawn(target) or -1
        -- Scanning stops at lock; clear all pending viewers in the same update.
        H.publishVision(p,target and {} or visible,lockedKey)
        if target then
            local bb=H.bb(p)
            local oldSeq=bb:GetValueAsInt("ChaseSequenceId")
            bb:SetValueAsObject("LockedTarget",target)
            bb:SetValueAsInt("ChaseSequenceId",oldSeq+1)
            H.traceEvent(string.format("patrol_lock oldSeq=%d newSeq=%d %s", oldSeq, oldSeq+1, H.snapshot(p,target)))
            p.HTDetectionEnabled=false
            H.stop(p)
            self.DetectionPending=true
            if not startDetectionSkill(self,p) then
                H.log(p,'detect-skill','Discovery skill failed; chase is blocked')
            end
            return
        end
    end
    if self.WaitTime then
        -- Stay at this point, facing its arrow, until the configured time passes.
        self.WaitElapsed = (self.WaitElapsed or 0) + dt
        if self.WaitElapsed < self.WaitTime then
            H.stop(p)
            H.face(p,route[d.index])
            return
        end
        self.WaitTime, self.WaitElapsed = nil, nil
        d.index = H.next(route,d.index)
    elseif H.arrived(p,route[d.index]) then
        local wait = H.waitTime(route[d.index])
        if wait > 0 then
            self.WaitTime, self.WaitElapsed = wait, 0
            H.stop(p)
            H.face(p,route[d.index])
            return
        end
        d.index=H.next(route,d.index)
    end
    H.moveTick(self,p,route[d.index]:K2_GetActorLocation(),H.config(p,"HTPatrolSpeed"),dt)
end
function T:ReceiveAbortAI(_,p)
    clearDetectionSkill(self,p)
    H.traceEvent(string.format("patrol_abort %s", H.snapshot(p,H.target(p))))
    p.HTDetectionEnabled=false
    self.VisibleSince={}
    self.WaitTime, self.WaitElapsed = nil, nil
    H.publishVision(p,{})
    H.abort(self,p)
end
return T
