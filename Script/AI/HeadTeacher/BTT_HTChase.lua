local H = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCommon")
local T = {}
function T:ReceiveExecuteAI(_,p)
    if not H.begin(self,p,"Chase") then return end
    p.HTDetectionEnabled=false
    self.Sequence=H.bb(p):GetValueAsInt("ChaseSequenceId")
    H.traceEvent(string.format("chase_enter taskSeq=%d %s", self.Sequence, H.snapshot(p,H.target(p))))
    self:ReceiveTickAI(nil,p,0)
end
function T:ReceiveTickAI(_,p,dt)
    H.progress(p,dt)
    local bb, target = H.bb(p),H.target(p)
    if self.Sequence ~= bb:GetValueAsInt("ChaseSequenceId") then
        H.traceEvent(string.format("chase_exit reason=SEQ_MISMATCH taskSeq=%d %s", self.Sequence, H.snapshot(p,target)))
        H.stop(p); self:FinishExecute(false); return
    end
    if not H.alive(target) then
        H.traceEvent(string.format("chase_exit reason=TARGET_LOST taskSeq=%d %s", self.Sequence, H.snapshot(p,target)))
        bb:SetValueAsBool("CatchReady",false)
        H.stop(p); self:FinishExecute(true); return
    end
    local gap=H.capsuleGap(p,target)
    if gap<=H.config(p,"HTCatchDistance") and H.visible(p,target) then
        -- Record the decision-frame distance: Catch runs on the next tick and the
        -- target may already be out of range by then.
        local d=H.data(p)
        d.catchGap,d.catchSeq=gap,self.Sequence
        H.traceEvent(string.format("chase_exit reason=CATCH_READY taskSeq=%d gap=%.1f %s %s", self.Sequence, gap, H.snapshot(p,target), H.gapDetail(p,target)))
        bb:SetValueAsBool("CatchReady",true)
        H.stop(p); self:FinishExecute(true); return
    end
    H.trace(p,"chase_tick",string.format("chase_tick taskSeq=%d %s", self.Sequence, H.snapshot(p,target)))
    -- No discovery, visibility loss, range leash, timeout or target switching.
    H.moveTick(self,p,target:K2_GetActorLocation(),H.config(p,"HTChaseSpeed"),dt)
end
function T:ReceiveAbortAI(_,p)
    H.traceEvent(string.format("chase_abort taskSeq=%s %s", tostring(self.Sequence), H.snapshot(p,H.target(p))))
    H.abort(self,p)
end
return T
