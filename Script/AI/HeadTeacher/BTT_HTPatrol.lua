local H = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCommon")
local T = {}
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
    p.HTDetectionEnabled = true
    H.bb(p):SetValueAsBool("CatchReady",false)
    self:ReceiveTickAI(nil,p,0)
end
function T:ReceiveTickAI(_,p,dt)
    H.progress(p,dt)
    local route, d = H.routes(p), H.data(p)
    if #route == 0 then self.VisibleSince={}; H.stop(p); return end
    d.index = math.max(1, math.min(d.index,#route))
    if not H.valid(route[d.index]) then
        H.log(p,"route-deleted","Current route waypoint was deleted; waiting for route repair")
        self.VisibleSince={}
        self.WaitTime, self.WaitElapsed = nil, nil
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
            return
        end
        for _,entry in ipairs(visible) do
            local actor=entry.actor
            local since=previous[actor] or d.clock
            current[actor]=since
            if not target and d.clock-since+0.000001>=delay then target=actor end
        end
        self.VisibleSince=current
        if target then
            local bb=H.bb(p)
            local oldSeq=bb:GetValueAsInt("ChaseSequenceId")
            bb:SetValueAsObject("LockedTarget",target)
            bb:SetValueAsInt("ChaseSequenceId",oldSeq+1)
            H.traceEvent(string.format("patrol_lock oldSeq=%d newSeq=%d %s", oldSeq, oldSeq+1, H.snapshot(p,target)))
            p.HTDetectionEnabled=false
            H.stop(p)
            self:FinishExecute(true)
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
    H.traceEvent(string.format("patrol_abort %s", H.snapshot(p,H.target(p))))
    p.HTDetectionEnabled=false
    self.VisibleSince={}
    self.WaitTime, self.WaitElapsed = nil, nil
    H.abort(self,p)
end
return T
