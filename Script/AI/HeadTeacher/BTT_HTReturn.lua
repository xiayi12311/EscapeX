local H = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCommon")
local T = {}
function T:ReceiveExecuteAI(_,p)
    if not H.begin(self,p,"ReturnToRoute") then return end
    p.HTDetectionEnabled=false
    H.releaseUnusedRigs(p,{})
    local bb=H.bb(p)
    H.traceEvent(string.format("return_enter seq=%s processed=%s lockBeforeClear=%s",
        tostring(bb:GetValueAsInt("ChaseSequenceId")), tostring(bb:GetValueAsInt("ProcessedSequenceId")),
        tostring(H.valid(H.target(p)))))
    local d=H.data(p)
    d.catchGap,d.catchSeq=nil,nil
    bb:ClearValue("LockedTarget")
    self.ReturnPoint=nil
    self.ReturnIndex=nil
    self:ReceiveTickAI(nil,p,0)
end
function T:ReceiveTickAI(_,p,dt)
    H.progress(p,dt)
    if not self.ReturnIndex then
        local route,nearest=H.routes(p),math.huge
        for i,point in ipairs(route) do
            local distance=H.distance(p:K2_GetActorLocation(),point:K2_GetActorLocation())
            if distance<nearest then
                nearest,self.ReturnPoint,self.ReturnIndex=distance,point,i
            end
        end
    end
    -- A deleted or unreachable chosen point never authorizes resuming detection.
    if not H.valid(self.ReturnPoint) then
        H.log(p,"return","Missing return waypoint; detection remains disabled")
        H.stop(p); return
    end
    if H.arrived(p,self.ReturnPoint) then
        local d=H.data(p)
        d.index=self.ReturnIndex
        H.stop(p)
        self:FinishExecute(true) -- BT alone re-enters Patrol and enables scanning.
        return
    end
    H.moveTick(self,p,self.ReturnPoint:K2_GetActorLocation(),H.config(p,"HTPatrolSpeed"),dt)
end
function T:ReceiveAbortAI(_,p) H.abort(self,p) end
return T
