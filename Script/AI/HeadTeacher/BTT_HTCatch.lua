local H = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCommon")
local C = UGCGameSystem.UGCRequire("Script.AI.HeadTeacher.HTCapture")
local T = {}
function T:ReceiveExecuteAI(controller,p)
    if not H.begin(self,p,"Catch") then return end
    -- A reused task node must not inherit a finished capture's flag.
    self.Capturing=false
    p.HTDetectionEnabled=false
    local bb,target=H.bb(p),H.target(p)
    local sequence=bb:GetValueAsInt("ChaseSequenceId")
    H.stop(p)
    local d=H.data(p)
    local decided=(d.catchSeq==sequence) and d.catchGap or nil
    local ready=bb:GetValueAsBool("CatchReady")
    local why,key,health=H.aliveWhy(target)
    local processed=bb:GetValueAsInt("ProcessedSequenceId")
    local gap=-1
    if H.valid(target) and H.valid(target.CapsuleComponent) and H.valid(p.CapsuleComponent) then
        gap=H.capsuleGap(p,target)
    end
    local limit=H.config(p,"HTCatchDistance")
    local sanity=H.config(p,"HTCatchSanity")
    -- The chase decided one tick ago; reuse that distance and only bound how far
    -- the target may have moved since (teleport guard).
    local effective=decided or gap
    local within=effective<=limit and gap<=effective+sanity
    local visible=nil
    if ready and not why and processed~=sequence and within then
        visible=H.visible(p,target)
    end
    local skip=nil
    if not ready then skip="READY"
    elseif why then skip="ALIVE_"..tostring(why)
    elseif processed==sequence then skip="PROCESSED"
    elseif effective>limit then skip="GAP"
    elseif not within then skip="TELEPORT"
    elseif not visible then skip="VISIBLE" end
    H.traceEvent(string.format("catch_%s%s seq=%d decided=%s gapNow=%.1f limit=%.1f sanity=%.1f ready=%s alive=%s why=%s key=%s health=%s processed=%d visible=%s %s %s",
        skip and "skip" or "hit", skip and (" reason="..skip) or "", sequence,
        decided and string.format("%.1f",decided) or "nil", gap, limit, sanity,
        tostring(ready), tostring(why==nil), tostring(why), tostring(key), tostring(health),
        processed, tostring(visible), H.snapshot(p,target), H.gapDetail(p,target)))
    local started=false
    if not skip then
        bb:SetValueAsInt("ProcessedSequenceId",sequence)
        -- Mark before invoking the replaceable handling. Never retry.
        local ok,res,reason=pcall(function()
            return p:HandleCaughtPlayer(target,sequence,controller)
        end)
        if not ok then H.log(p,"capture","Catch handler failed: "..tostring(res))
        else started = (res==true) end
    end
    d.catchGap,d.catchSeq=nil,nil
    if started then
        -- Stay Running: the escort and the bind advance through ReceiveTickAI.
        -- LockedTarget is kept so a tree restart cannot pick a second victim.
        self.Capturing=true
        H.traceEvent(string.format("catch_into_capture seq=%d reason=%s",sequence,tostring(reason)))
        return
    end
    -- A handler that created a session and then failed would otherwise leave the pawn
    -- owning a session nothing drives: the monster would refuse every later catch.
    if C.active(p) then C.cancel(p,'BEGIN_INCOMPLETE') end
    bb:ClearValue("LockedTarget")
    bb:SetValueAsBool("CatchReady",false)
    self:FinishExecute(true)
end
function T:ReceiveTickAI(_,p,dt)
    if not self.Capturing then return end
    H.progress(p,dt)
    local finished,reason=C.update(self,p,dt)
    if not finished then return end
    self.Capturing=false
    local bb=H.bb(p)
    bb:ClearValue("LockedTarget")
    bb:SetValueAsBool("CatchReady",false)
    H.traceEvent(string.format("catch_finished seq=%d reason=%s",
        bb:GetValueAsInt("ChaseSequenceId"), tostring(reason)))
    self:FinishExecute(true)
end
function T:ReceiveAbortAI(_,p)
    -- Release the capture first: the diagnostic reads the blackboard, and a failure
    -- there must not skip the cleanup that unfreezes the player.
    if self.Capturing then
        self.Capturing=false
        C.cancel(p,'BT_ABORTED')
    end
    H.traceEvent(string.format("catch_abort %s", H.snapshot(p,H.target(p))))
    H.abort(self,p)
end
return T
