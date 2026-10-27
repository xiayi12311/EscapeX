-- Local focus and interaction display. The desk service remains authoritative: this file
-- only decides what the local player is aiming at, and draws server-owned state.
local FocusState=UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.FocusState')
local Config=UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.InteractionConfig')
local DeskClock=UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.DeskClock')
local M={}
local current=nil
-- Ownership: the player controller lives for the whole local session while pawns come and
-- go, so a controller-side watch loop decides when the layer runs. Hooking the pawn's
-- ReceiveBeginPlay alone was measured to fail (PIE 2026-10-27: the first pawn started a
-- session, the replacement pawn never did, and the old pawn's EndPlay tore the layer down
-- silently, killing the ring 39s into the session).
local watched=nil
local monitorTimer=nil
local LOG='[DeskFocus]'
local function valid(o) return o~=nil and KismetSystemLibrary.IsValid(o) end
local function log(text) ugcprint(LOG..' '..tostring(text)) end
local function outline(actor,on)
    if valid(actor) then
        UGCGameSystem.DrawOutline(actor,on,Config.OutlineThickness,Config.OutlineColor)
    end
end

-- A camera that is not ready is normal for the first frames after a pawn spawns; it is
-- not an error and must not be treated as "no target".
local function cameraRay(c)
    local pc=c.controller
    if not valid(pc) or not valid(pc.PlayerCameraManager) then return nil end
    local cam=pc.PlayerCameraManager:GetCameraLocation()
    local size=WidgetLayoutLibrary.GetViewportSize(pc)
    if not size then return nil end
    local ok,_,dir=GameplayStatics.DeprojectScreenToWorld(pc,{X=size.X/2,Y=size.Y/2})
    if not (ok and dir) then return nil end
    return cam,{X=cam.X+dir.X*Config.TraceDistance,Y=cam.Y+dir.Y*Config.TraceDistance,Z=cam.Z+dir.Z*Config.TraceDistance}
end

local function selectDesk(c)
    local cam,endpos=cameraRay(c)
    if not cam then return nil end
    local pc=c.controller
    local hits={}
    local hit=KismetSystemLibrary.LineTraceMultiForObjects(pc,cam,endpos,{0,1},false,{c.pawn},0,
        hits,true,{R=1,G=0,B=0,A=1},{R=0,G=1,B=0,A=1},0.1)
    if not hit then return nil end
    for _,entry in ipairs(hits) do
        local actor=entry.Actor and entry.Actor:Get()
        if valid(actor) then
            -- the first blocking hit decides it: a wall or a prop in front also counts
            if not UE.IsA(actor,c.deskClass) then return nil end
            local s=actor.DeskState
            if s and s.State=='Closed' and valid(actor.SearchArea) then
                local a=actor.SearchArea:K2_GetComponentLocation()
                local b=c.pawn:K2_GetActorLocation()
                local dx,dy,dz=a.X-b.X,a.Y-b.Y,a.Z-b.Z
                local radius=actor.DeskInteractRadius or 180
                if dx*dx+dy*dy+dz*dz<=radius*radius then return actor end
            end
            return nil
        end
    end
    return nil
end

local function prepareWidget(c)
    local ok,err=pcall(function()
        UGCWidgetUtility.CreateWidgetAsync(Config.WidgetClassPath,function(widget)
            if current~=c then
                if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end
                return
            end
            if not valid(widget) then
                log('async widget creation failed, interaction UI disabled')
                return
            end
            c.widget=widget
            widget:SetVisibility(ESlateVisibility.Collapsed)
            widget:AddToViewport(20)
            widget:SetRequestHandler(function()
                local actor=c.state.focus
                if c.state:CanRequest() and valid(actor) then
                    log('requesting search through controller RPC')
                    UnrealNetwork.CallUnrealRPC(c.controller,c.controller,'ServerRequestDeskSearch',actor)
                end
            end)
            log('interaction widget prepared asynchronously')
        end)
    end)
    if not ok then log('async widget preparation failed: '..tostring(err)) end
end

function M.Update()
    local c=current
    if not c or not valid(c.pawn) or not valid(c.controller) then return end
    c.notReady=(c.notReady or 0)+1
    if not valid(c.controller.PlayerCameraManager) then
        if c.notReady<Config.ReadyRetryTicks then return end
        -- never ready: stop instead of erroring forever, and say so
        log(string.format('local camera unavailable after %d ticks; stopping focus loop',c.notReady))
        M.End()
        return
    end
    c.notReady=0
    local target=selectDesk(c)
    if target~=c.state.focus then
        outline(c.state.focus,false)
        c.state:SetFocus(target)
        outline(target,true)
    end
    local display=c.state:DisplayTarget()
    if not valid(display) or not valid(display.SearchArea) then
        if display then M.DeskRemoved(display) end
        if valid(c.widget) then c.widget:SetVisibility(ESlateVisibility.Collapsed) end
        return
    end
    local widget=c.widget
    if not valid(widget) then return end
    local s=display.DeskState
    local active=c.state.active==display and s and s.State=='Searching' and s.SearchingPlayerId==c.key
    widget:SetButtonVisible(not active and c.state:CanRequest())
    if active then
        local duration=(s.SearchEndTime or 0)-(s.SearchStartTime or 0)
        local now=DeskClock.ApproxServerNow(c.pawn)
        if now==nil then
            if not c.clockWarned then
                c.clockWarned=true
                log('server time base unavailable; ring stays empty rather than guessing')
            end
            widget:SetProgress(nil)
        elseif duration>0 then
            local raw=math.max(0,math.min(1,(now-s.SearchStartTime)/duration))
            -- the client clock estimate steps back when the replicated delta refreshes
            -- (measured 2026-10-27: 0.649 -> 0.632), which reads as the ring jerking
            -- backwards, so one search only ever moves forward
            local sessionKey=tostring(s.InteractionId or '')..'/'..tostring(s.ResetVersion or '')
            if sessionKey~=c.progressSession then
                c.progressSession=sessionKey
                c.progressMax=raw
            elseif raw<c.progressMax then
                raw=c.progressMax
            else
                c.progressMax=raw
            end
            widget:SetProgress(raw)
        else
            widget:SetProgress(nil)
        end
    else widget:SetProgress(nil) end
    local projected=widget:SetWorldAnchor(c.controller,display.SearchArea:K2_GetComponentLocation())
    widget:SetVisibility(projected and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
end

function M.Begin(pawn)
    local pc=UGCGameSystem.GetLocalPlayerController()
    if not valid(pc) or UGCGameSystem.GetLocalPlayerPawn()~=pawn then return false end
    if current then M.End() end
    local key=UGCGameSystem.GetPlayerKeyByPlayerController(pc)
    local cls=UE.LoadClass(Config.DeskClassPath)
    if cls==nil then
        log('desk class unavailable, focus layer not started')
        return false
    end
    local c={pawn=pawn,controller=pc,key=key,deskClass=cls,state=FocusState.new(key),notReady=0}
    current=c
    prepareWidget(c)
    for _,desk in pairs(UGCActorComponentUtility.GetAllActorsOfClass(pawn,cls)) do
        if valid(desk) then c.state:ApplyDeskState(desk,desk.DeskState) end
    end
    c.timer=UGCTimerUtility.CreateLuaTimer(Config.DetectInterval,function() M.Update() end,true)
    -- lifecycle evidence: without this a healthy run is indistinguishable from a layer
    -- that was never started, because every other log here is a failure path
    log('focus session started key='..tostring(key))
    return true
end

function M.DeskChanged(actor,state)
    if not current then return end
    current.state:ApplyDeskState(actor,state)
    -- without this the OnRep -> focus-layer hop is invisible in a native run: every other
    -- log here is a failure path
    log('desk state reached focus layer: '..tostring(KismetSystemLibrary.GetObjectName(actor))
        ..' state='..tostring(state and state.State)..' rev='..tostring(state and state.Revision))
end

function M.DeskRemoved(actor)
    if current then
        if current.state.focus==actor then outline(actor,false) end
        current.state:Remove(actor)
    end
end

function M.End()
    local c=current
    if not c then return end
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    outline(c.state.focus,false)
    if valid(c.widget) then c.widget:RemoveFromParent() end
    if watched==c.pawn then watched=nil end
    current=nil
    log('focus session stopped')
end

-- Started from the local player controller. Every tick it re-reads which pawn is ours and
-- treats a change as the only lifecycle event that matters: respawn, re-possess and pawn
-- destruction all show up here, so no ordering between pawn BeginPlay/EndPlay is trusted.
function M.Monitor()
    local pc=UGCGameSystem.GetLocalPlayerController()
    if not valid(pc) then return false end
    if monitorTimer then return false end
    monitorTimer=UGCTimerUtility.CreateLuaTimer(Config.MonitorInterval,function()
        local localPawn=UGCGameSystem.GetLocalPlayerPawn()
        if localPawn==watched then return end
        if watched then M.End() end
        if valid(localPawn) then
            watched=localPawn
            M.Begin(localPawn)
        else
            log('local pawn unavailable; focus layer idle')
        end
    end,true,'EscapeX.DeskFocus.Monitor')
    log('focus monitor armed')
    return true
end

function M.StopMonitor()
    if monitorTimer then
        UGCTimerUtility.RemoveLuaTimer(monitorTimer)
        monitorTimer=nil
    end
    M.End()
end

return M
