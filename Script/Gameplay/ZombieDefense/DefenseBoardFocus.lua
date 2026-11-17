-- Reuses the same shared widget shell as the start point. The label is driven by
-- the replicated board status, so a teammate's install shows up without a second
-- RPC, and pressing again while installing cancels this player's own board.
-- The crosshair may find a window from further away than the install range, so
-- the prompt is filtered by the same InstallRange the server enforces; a prompt
-- that only ever produces a refusal is worse than no prompt.
local UI = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig').Interaction
local Board = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseBoardInteraction')
local World = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local M = {}
M.Config = {DetectInterval = UI.DetectInterval, TraceReach = 350}
local current
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end
local function clear(c)
    if valid(c.target) then UGCGameSystem.DrawOutline(c.target, false, UI.OutlineThickness, UI.OutlineColor) end
    c.target = nil
    c.status = nil
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
            -- Only the first blocking actor decides: a window behind a wall must
            -- not become interactable through it.
            if UE.IsA(actor, c.class) and actor.Enabled == true then return actor end
            return nil
        end
    end
    return nil
end
local function label(c)
    if c.error then return '安装失败: '..c.error end
    if c.pending then return Board.Config.BusyLabel end
    if c.status and c.status.Boards >= c.status.MaxBoards then return Board.Config.FullLabel end
    if c.installing then return Board.Config.CancelLabel end
    if c.status and c.status.Boards > 0 then return Board.Config.InstalledLabel end
    return Board.Config.Label
end
function M.Update()
    local c = current
    if not c or not valid(c.widget) then return end
    local gm = UGCGameSystem.GetGameMode()
    local pawn = UGCGameSystem.GetLocalPlayerPawn()
    local found = valid(pawn) and tracePoint(c, pawn) or nil
    local status = valid(found) and Board.Status(gm, found) or nil
    if found and status and distanceTo(pawn, found) > status.InstallRange then
        found, status = nil, nil
    end
    if found ~= c.target then
        c.error = nil
        clear(c)
        c.target, c.status = found, status
        -- A window that already belongs to another installer still shows state,
        -- but this player's own pending install flag must not survive a retarget.
        c.installing = found ~= nil and status ~= nil and status.Installer == c.key
        if valid(found) then UGCGameSystem.DrawOutline(found, true, UI.OutlineThickness, UI.OutlineColor) end
        c.widget:ResetWorldAnchor()
    else
        c.status = status
    end
    local show = valid(found)
    c.widget:SetButtonVisible(show)
    local projected = false
    if show then
        c.widget.WBP_Interact_Left:Configure(c.widget, label(c))
        projected = c.widget:SetWorldAnchor(c.pc, anchorOf(found))
    end
    c.widget:SetVisibility(projected and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
end
function M.Result(sequence, ok, reason)
    local c = current
    if not c or c.pending ~= sequence then return end
    c.pending = nil
    if ok then
        c.error = nil
        -- Confirm from the authoritative status on the next tick rather than
        -- flipping a local flag that a lost update would leave wrong forever.
        M.Update()
    else
        c.installing = false
        c.error = tostring(reason)
        ugcprint('[ZombieBoard] request rejected: '..tostring(reason))
    end
end
function M.Begin(pc)
    if pc ~= UGCGameSystem.GetLocalPlayerController() then return false end
    if current then M.End() end
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Window))
    if not class then ugcprint('[ZombieBoard] window class unavailable'); return false end
    local c = {pc=pc, class=class, key=UGCGameSystem.GetPlayerKeyByPlayerController(pc)}
    current = c
    UGCWidgetUtility.CreateWidgetAsync(
        UGCGameSystem.GetUGCResourcesFullPath(UI.WidgetClassPath), function(widget)
        if current ~= c then
            if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end
            return
        end
        if not valid(widget) then ugcprint('[ZombieBoard] widget unavailable'); return end
        c.widget = widget
        widget:HideProgressVisuals()
        widget:SetVisibility(ESlateVisibility.Collapsed)
        widget:AddToViewport(20)
        widget:SetRequestHandler(function()
            if current ~= c or c.pending or not valid(c.target) then return end
            local sequence = (c.pc.ZombieBoardClientSequence or 0) + 1
            c.pc.ZombieBoardClientSequence = sequence
            c.pending = sequence
            if c.installing then
                -- Cancel carries only the sequence: the server owns which window
                -- this player occupies, so no client-chosen point can retract
                -- somebody else's board.
                UnrealNetwork.CallUnrealRPC(pc, pc, 'ServerCancelZombieBoard', sequence)
            else
                UnrealNetwork.CallUnrealRPC(pc, pc, 'ServerRequestZombieBoard', c.target, sequence)
            end
        end, function() end)
        c.timer = UGCTimerUtility.CreateLuaTimer(M.Config.DetectInterval, M.Update, true)
        M.Update()
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
