-- Client-only visual state. One timer per relevant desk; never commits gameplay.
local P={}
local Config=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskOutcomeConfig')
local function valid(o) return o~=nil and KismetSystemLibrary.IsValid(o) end
local function now() return UGCGameSystem.GetGameState():GetServerWorldTimeSeconds() end
local function stopTimer(a)
    if a.DeskVisualTimer then UGCTimerUtility.RemoveLuaTimer(a.DeskVisualTimer) end
    a.DeskVisualTimer=nil
end
local function ensureTimer(a)
    if a.DeskVisualTimer then return end
    a.DeskVisualTimer=UGCTimerUtility.CreateLuaTimer(0.05,function()
        if not valid(a) then return end
        local ok,err=pcall(P.Update,a)
        if not ok and not a.DeskVisualError then
            a.DeskVisualError=true; ugcprint('[DeskSearch] Presentation error: '..tostring(err))
        end
    end,true)
end
local function closeUI(a)
    if valid(a.DeskProgressUI) then a.DeskProgressUI:RemoveFromParent() end
    a.DeskProgressUI=nil
end
local function stopSequence(a)
    if valid(a.DeskSequencePlayer) then a.DeskSequencePlayer:Stop() end
    if valid(a.DeskSequenceActor) then a.DeskSequenceActor:K2_DestroyActor() end
    a.DeskSequencePlayer=nil; a.DeskSequenceActor=nil
end
-- 新模型（Asset/Models/SchoolDesk）：抽屉沿本地 -Y 抽出 18cm，组件原点归零；
-- 内容物放在抽屉内腔，内底 57.6cm、内腔中心相对抽屉 -0.8cm。
local DRAWER_TRAVEL=-18
local DRAWER_Z=0
local CONTENT_Y=-0.8
local CONTENT_FLOOR_Z=57.6
local function contentZ(a)
    return CONTENT_FLOOR_Z+(a.DeskContentHeight or 0.005)*50
end
local function contentAt(a,offset)
    a.DeskContent:K2_SetRelativeLocation({X=0,Y=offset+CONTENT_Y,Z=contentZ(a)},false,{},true)
end
local function drawerAt(a,opened)
    local offset=opened and DRAWER_TRAVEL or 0
    if valid(a.Drawer) then
        a.Drawer:K2_SetRelativeLocation({X=0,Y=offset,Z=DRAWER_Z},false,{},true)
    end
    if valid(a.DeskContent) then
        contentAt(a,offset)
        a.DeskContent:SetVisibility(opened,false)
    end
end

function P.Apply(a,s)
    if not s then return end
    local version=s.ResetVersion or 0
    if a.DeskVisualVersion and version<a.DeskVisualVersion then return end
    if (s.Revision or 0)<(a.DeskVisualRevision or 0) then return end
    local signature=version..':'..tostring(s.InteractionId)..':'..tostring(s.State)
    if signature==a.DeskVisualSignature then return end
    a.DeskVisualSignature=signature; a.DeskVisualVersion=version; a.DeskVisualRevision=s.Revision or 0
    local outcome=Config.Outcomes[s.FinalOutcomeId]
    if outcome and outcome.ContentScale and valid(a.DeskContent) then
        a.DeskContent:SetRelativeScale3D(outcome.ContentScale)
        a.DeskContentHeight=outcome.ContentScale.Z
    end
    closeUI(a)
    if s.State=='Searching' or s.State=='Opening' then ensureTimer(a) else stopTimer(a) end
    if s.State=='Closed' or s.State=='Searching' then
        stopSequence(a); drawerAt(a,false)
    elseif s.State=='Opening' then
        stopSequence(a)
        local elapsed=math.max(0,now()-(s.OpenStartTime or now()))
        if elapsed<(s.OpenDuration or 1) then
            local ok,err=pcall(function()
                local sequence=UE.LoadObject('/EscapeX/Asset/Sequences/LS_DeskOpen.LS_DeskOpen')
                local library=UGCObjectUtility.GetClassDefaultObject(
                    UE.LoadClass('/Script/LevelSequence.LevelSequencePlayer'))
                local player,actor=library.CreateLevelSequencePlayer(a,sequence,
                    {LoopCount=0,PlayRate=1/(s.OpenDuration or 1),StartTime=0,bRestoreState=false},nil)
                assert(valid(player) and valid(actor),'sequence player unavailable')
                a.DeskSequencePlayer=player; a.DeskSequenceActor=actor
                actor:UGCAddBinding(a,'DeskSequenceAuthoring')
                player:SetPlaybackPosition(elapsed/(s.OpenDuration or 1))
                player:Play()
            end)
            if not ok then ugcprint('[DeskSearch] Sequence error: '..tostring(err)) end
        else drawerAt(a,true) end
    elseif s.State=='Opened' then
        stopSequence(a); drawerAt(a,true)
    end
end

function P.Update(a)
    local s=a.DeskState
    if not s then return end
    if (s.Revision or 0)<(a.DeskVisualRevision or 0) then return end
    P.Apply(a,s)
    if s.State=='Searching' then
        local pc=UGCGameSystem.GetLocalPlayerController()
        local key=valid(pc) and UGCGameSystem.GetPlayerKeyByPlayerController(pc)
        if key~=s.SearchingPlayerId then closeUI(a); return end
        if not valid(a.DeskProgressUI) then
            local cls=UE.LoadClass('/EscapeX/Asset/UI/WBP_DeskSearchProgress.WBP_DeskSearchProgress_C')
            a.DeskProgressUI=UGCWidgetUtility.CreateWidget(cls)
            if valid(a.DeskProgressUI) then a.DeskProgressUI:AddToViewport(20) end
        end
        local w=a.DeskProgressUI
        if valid(w) then
            local bar=w:GetWidgetFromName('SearchProgress')
            local label=w:GetWidgetFromName('SearchLabel')
            local duration=(s.SearchEndTime or 0)-(s.SearchStartTime or 0)
            local remaining=math.max(0,(s.SearchEndTime or 0)-now())
            if valid(bar) then bar:SetPercent(duration>0 and math.min(1,math.max(0,1-remaining/duration)) or 0) end
            if valid(label) then label:SetText(remaining>0 and string.format('搜索中… %.1f 秒',remaining) or '等待确认…') end
        end
    elseif s.State=='Opening' then
        local elapsed=now()-(s.OpenStartTime or now())
        if elapsed>=(s.OpenDuration or 1) then
            -- 序列播完会把绑定组件还原，这里在时长到达时立即落到打开姿态，
            -- 避免等服务端 Opened 快照期间抽屉自己滑回闭合位置。
            stopSequence(a)
            drawerAt(a,true)
        elseif elapsed>=(s.RevealOffset or 0.8) then
            if valid(a.DeskContent) then
                contentAt(a,DRAWER_TRAVEL)
                a.DeskContent:SetVisibility(true,false)
            end
        end
    end
end

function P.Begin(a)
    a.DeskVisualSignature=nil
    P.Apply(a,a.DeskState)
end

function P.End(a)
    stopTimer(a)
    closeUI(a); stopSequence(a)
end

return P
