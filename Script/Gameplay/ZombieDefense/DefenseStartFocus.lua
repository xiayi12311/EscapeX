-- Reuses the crate's shared widget shell; no changes to crate grip or hold logic.
local UI = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig').Interaction
local Start = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseStartInteraction')
local World = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local M = {}
local current
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end
local function clear(c)
    if valid(c.target) then UGCGameSystem.DrawOutline(c.target, false, UI.OutlineThickness, UI.OutlineColor) end
    c.target = nil
end
local function target(c, pawn)
    local pc = c.pc
    if not valid(pc.PlayerCameraManager) then return nil end
    local camera = pc.PlayerCameraManager:GetCameraLocation()
    local size = WidgetLayoutLibrary.GetViewportSize(pc)
    if not size then return nil end
    local ok, _, dir = GameplayStatics.DeprojectScreenToWorld(pc, {X=size.X/2, Y=size.Y/2})
    if not ok or not dir then return nil end
    local finish = {X=camera.X+dir.X*Start.Config.Range, Y=camera.Y+dir.Y*Start.Config.Range,
        Z=camera.Z+dir.Z*Start.Config.Range}
    local hits = {}
    KismetSystemLibrary.LineTraceMultiForObjects(pc, camera, finish, {0,1}, false,
        {pawn}, 0, hits, true, {R=1,G=0,B=0,A=1}, {R=0,G=1,B=0,A=1}, 0.1)
    for _, hit in ipairs(hits) do
        local actor = hit.Actor and hit.Actor:Get()
        if valid(actor) then
            if UE.IsA(actor, c.class) and actor.Enabled == true and Start.InRange(actor,pawn) then return actor end
            return nil
        end
    end
end
function M.Update()
    local c = current
    if not c or not valid(c.widget) then return end
    local pawn = UGCGameSystem.GetLocalPlayerPawn()
    local point = valid(pawn) and target(c,pawn) or nil
    if point ~= c.target then
        c.error = nil
        clear(c); c.target = point
        if valid(point) then UGCGameSystem.DrawOutline(point,true,UI.OutlineThickness,UI.OutlineColor) end
        c.widget:ResetWorldAnchor()
    end
    local show = valid(point)
    c.widget:SetButtonVisible(show)
    local projected = false
    if show then
        local label = point.DefenseStarted and Start.Config.StartedLabel
            or (c.pending and Start.Config.PendingLabel or (c.error and ('启动失败: '..c.error) or Start.Config.Label))
        c.widget.WBP_Interact_Left:Configure(c.widget,label)
        projected = c.widget:SetWorldAnchor(c.pc,point.InteractionPoint:K2_GetComponentLocation())
    end
    c.widget:SetVisibility(projected and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
end
function M.Result(sequence, ok, reason)
    local c = current
    if not c or c.pending ~= sequence then return end
    c.pending = nil
    c.error = not ok and tostring(reason) or nil
    if not ok then ugcprint('[ZombieStart] request rejected: '..tostring(reason)) end
end
function M.Begin(pc)
    if pc ~= UGCGameSystem.GetLocalPlayerController() then return false end
    if current then M.End() end
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Start))
    if not class then ugcprint('[ZombieStart] start class unavailable');return false end
    local c = {pc=pc,class=class,sequence=0}
    current = c
    UGCWidgetUtility.CreateWidgetAsync(UI.WidgetClassPath,function(widget)
        if current ~= c then
            if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end
            return
        end
        if not valid(widget) then ugcprint('[ZombieStart] widget unavailable');return end
        c.widget = widget
        widget:HideProgressVisuals()
        widget:SetVisibility(ESlateVisibility.Collapsed)
        widget:AddToViewport(20)
        widget:SetRequestHandler(function()
            local point = c.target
            if current ~= c or c.pending or not valid(point) or point.DefenseStarted then return end
            pc.ZombieStartClientSequence = (pc.ZombieStartClientSequence or 0)+1
            c.pending=pc.ZombieStartClientSequence
            UnrealNetwork.CallUnrealRPC(pc,pc,'ServerRequestZombieStart',point,c.pending)
        end,function()end)
        c.timer = UGCTimerUtility.CreateLuaTimer(UI.DetectInterval,M.Update,true)
    end)
    return true
end
function M.End(pc)
    local c = current
    if not c or (pc and pc ~= c.pc) then return end
    current = nil
    clear(c)
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    if valid(c.widget) then UGCWidgetUtility.DestroyWidget(c.widget) end
end
return M
