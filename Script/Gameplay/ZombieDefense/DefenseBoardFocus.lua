local UI = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig').Interaction
local World = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local Catalog = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseCatalog')
local M = {}
M.Config = {DetectInterval = UI.DetectInterval, TraceReach = 350}
local current
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end
local function clear(c)
    if valid(c.target) then UGCGameSystem.DrawOutline(c.target, false, UI.OutlineThickness, UI.OutlineColor) end
    c.target = nil
end

local function nextSequence(pc)
    local sequence = (pc.ZombieBoardClientSequence or 0) + 1
    pc.ZombieBoardClientSequence = sequence
    return sequence
end

local function release(c)
    local hold = c.hold
    if not hold then return end
    c.hold = nil
    if valid(c.pc) and not hold.finished and not hold.submitted then
        UnrealNetwork.CallUnrealRPC(c.pc, c.pc, 'ServerCancelZombieBoard', nextSequence(c.pc))
    end
end
local function anchorOf(point)
    if valid(point.InteractionPoint) then return point.InteractionPoint:K2_GetComponentLocation() end
    return point:K2_GetActorLocation()
end
local function distanceTo(pawn, point)
    if not valid(pawn) then return math.huge end
    local here = pawn:K2_GetActorLocation()
    local there = anchorOf(point)
    local dx, dy, dz = here.X - there.X, here.Y - there.Y, here.Z - there.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end
local function tracePoint(c, pawn)
    local pc = c.pc
    if not valid(pc.PlayerCameraManager) then return nil end
    local camera = pc.PlayerCameraManager:GetCameraLocation()
    local size = WidgetLayoutLibrary.GetViewportSize(pc)
    if not size then return nil end
    local ok, _, dir = GameplayStatics.DeprojectScreenToWorld(pc, {X=size.X/2, Y=size.Y/2})
    if not ok or not dir then return nil end
    local reach = M.Config.TraceReach
    local finish = {X=camera.X+dir.X*reach, Y=camera.Y+dir.Y*reach, Z=camera.Z+dir.Z*reach}
    local hits = {}
    KismetSystemLibrary.LineTraceMultiForObjects(pc, camera, finish, {0,1}, false,
        {pawn}, 0, hits, true, {R=1,G=0,B=0,A=1}, {R=0,G=1,B=0,A=1}, 0.1)
    for _, hit in ipairs(hits) do
        local actor = hit.Actor and hit.Actor:Get()
        if valid(actor) then
            -- Installed planks belong to the window that spawned them. Other
            -- blockers still terminate the trace before it can reach the window.
            local point = UE.IsA(actor, c.class) and actor or UGCActorComponentUtility.GetOwner(actor)
            if valid(point) and UE.IsA(point, c.class) and point.Enabled == true then return point end
            return nil
        end
    end
    return nil
end
function M.Update()
    local c = current
    if not c or not valid(c.widget) then return end
    local pawn = UGCGameSystem.GetLocalPlayerPawn()
    local found = valid(pawn) and UGCAttributeSystem.GetGameAttributeValue(pawn, 'Health') > 0
        and tracePoint(c, pawn) or nil
    if found and distanceTo(pawn, found) > found.InstallRange then
        found = nil
    end
    if c.hold and (c.hold.point ~= found or c.hold.pawn ~= pawn) then release(c) end
    local hold = c.hold
    local status = found and found.DefenseBoardInteractionState
    if hold and status then
        if status.Installer == c.key then
            hold.observed = true
        elseif not hold.submitted and (hold.observed or status.Installer ~= nil) then
            hold.finished = true
        end
    end
    if hold and hold.finished and hold.released then
        c.hold, hold = nil, nil
    end
    local holding = hold and not hold.finished
    local canInstall = status and status.Available
        and UGCBackPackSystem.GetItemCount(pawn, Catalog.BoardItemId) > 0
    local target = (holding or canInstall) and found or nil
    if target ~= c.target then
        clear(c)
        c.target = target
        if valid(target) then UGCGameSystem.DrawOutline(target, true, UI.OutlineThickness, UI.OutlineColor) end
        c.widget:ResetWorldAnchor()
    end
    local projected = valid(target) and c.widget:SetWorldAnchor(c.pc, anchorOf(target))
    if not projected then release(c) end
    c.canPress = projected and not hold and canInstall
    c.widget:SetButtonVisible(projected == true)
    local progress
    if projected and holding then
        local elapsed = KismetSystemLibrary.GetGameTimeInSeconds(c.pc) - hold.pressedAt
        progress = math.min(elapsed / hold.duration, 1)
    end
    local button = c.widget.WBP_Interact_Left
    button:SetProgress(progress or 0)
    button:SetProgressVisible(progress ~= nil)
    c.widget:SetVisibility(projected and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
    if progress == 1 and hold.accepted and not hold.submitted then
        hold.submitted = true
        UnrealNetwork.CallUnrealRPC(c.pc, c.pc, 'ServerCompleteZombieBoard', hold.point, hold.sequence)
    end
end
function M.Result(sequence, ok, completed)
    local c = current
    local hold = c and c.hold
    if not hold or hold.sequence ~= sequence or hold.finished then return end
    if completed or not ok then hold.finished = true else hold.accepted = true end
    M.Update()
end
function M.Begin(pc)
    if pc ~= UGCGameSystem.GetLocalPlayerController() then return false end
    if current then M.End() end
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Window))
    if not class then ugcprint('[ZombieBoard] window class unavailable'); return false end
    local c = {pc=pc, class=class, key=UGCGameSystem.GetPlayerKeyByPlayerController(pc)}
    current = c
    UGCWidgetUtility.CreateWidgetAsync(UI.WidgetClassPath, function(widget)
        if current ~= c then
            if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end
            return
        end
        if not valid(widget) then ugcprint('[ZombieBoard] widget unavailable'); return end
        c.widget = widget
        widget:SetVisibility(ESlateVisibility.Collapsed)
        widget:AddToViewport(20)
        widget:HideProgressVisuals()
        widget.WBP_Interact_Left:Configure(widget, '长按安装木板')
        widget:SetRequestHandler(function()
            if current ~= c or c.hold then return end
            M.Update()
            if not c.canPress then return end
            local point, sequence = c.target, nextSequence(pc)
            c.hold = {point = point, pawn = UGCGameSystem.GetLocalPlayerPawn(), sequence = sequence,
                duration = point.InstallSeconds,
                pressedAt = KismetSystemLibrary.GetGameTimeInSeconds(pc)}
            UnrealNetwork.CallUnrealRPC(pc, pc, 'ServerRequestZombieBoard', point, sequence)
            M.Update()
        end, function()
            if current ~= c then return end
            M.Update()
            local hold = c.hold
            if hold and not hold.finished
                and KismetSystemLibrary.GetGameTimeInSeconds(pc) - hold.pressedAt >= hold.duration then
                hold.released = true
            else
                release(c)
            end
            M.Update()
        end)
        c.timer = UGCTimerUtility.CreateLuaTimer(M.Config.DetectInterval, M.Update, true)
        M.Update()
    end)
    return true
end
function M.End(pc)
    local c = current
    if not c or (pc and pc ~= c.pc) then return end
    current = nil
    release(c)
    clear(c)
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    if valid(c.widget) then UGCWidgetUtility.DestroyWidget(c.widget) end
end
return M
