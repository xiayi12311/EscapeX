-- Local crosshair focus, outline and the desk-style WBP interaction button. The server
-- remains authoritative; this layer predicts the same continuous grip as the manager.
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullConfig')
local Manager = UGCGameSystem.UGCRequire('Script.Gameplay.PushPull.PushPullManager')
local F = {}

local LOG = '[PushPull]'
local current = nil
local monitorTimer = nil
local watchedPawn = nil

local function log(text) ugcprint(LOG .. ' focus ' .. tostring(text)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local function localPawn()
    local ok, pawn = pcall(function() return UGCGameSystem.GetLocalPlayerPawn() end)
    if ok and valid(pawn) then return pawn end
    return nil
end

local function localController()
    local ok, pc = pcall(function() return UGCGameSystem.GetLocalPlayerController() end)
    if ok and valid(pc) then return pc end
    return nil
end

local function localKey(pc)
    if not valid(pc) then return -1 end
    local ok, key = pcall(function() return UGCGameSystem.GetPlayerKeyByPlayerController(pc) end)
    if ok and type(key) == 'number' then return key end
    return -1
end

local function nextSequence(controller)
    controller.PushPullClientSequence = (controller.PushPullClientSequence or 0) + 1
    return controller.PushPullClientSequence
end

local function outline(actor, on)
    if valid(actor) then
        UGCGameSystem.DrawOutline(actor, on, Config.Interaction.OutlineThickness,
            Config.Interaction.OutlineColor)
    end
end

local function cameraRay(c)
    local pc = c.controller
    if not valid(pc) or not valid(pc.PlayerCameraManager) then return nil end
    local cam = pc.PlayerCameraManager:GetCameraLocation()
    local size = WidgetLayoutLibrary.GetViewportSize(pc)
    if not size then return nil end
    local ok, _, direction = GameplayStatics.DeprojectScreenToWorld(pc, {X = size.X / 2, Y = size.Y / 2})
    if not (ok and direction) then return nil end
    return cam, {
        X = cam.X + direction.X * Config.Interaction.TraceDistance,
        Y = cam.Y + direction.Y * Config.Interaction.TraceDistance,
        Z = cam.Z + direction.Z * Config.Interaction.TraceDistance,
    }
end

local function crateRecord(actor)
    local location = actor:K2_GetActorLocation()
    local rotation = actor:K2_GetActorRotation()
    local extent = actor.CrateCollision:GetScaledBoxExtent()
    return {
        X = location.X, Y = location.Y, Z = location.Z,
        Yaw = rotation.Yaw or 0,
        HalfExtentX = extent.X, HalfExtentY = extent.Y, HalfExtentZ = extent.Z,
        EdgeMargin = Config.Interaction.EdgeMargin,
        MinGripSpacing = Config.Interaction.MinGripSpacing,
    }
end

local function participantOf(state, key)
    return state and state.Participants and state.Participants[key] or nil
end

local function predictedGrip(c, actor, state)
    if not (valid(c.pawn) and valid(actor.CrateCollision)) then return nil end
    local rec = crateRecord(actor)
    local location = c.pawn:K2_GetActorLocation()
    local forward = c.pawn:GetActorForwardVector()
    local grip, reason = Manager.ResolveGrip(rec, location, state.Participants or {}, Config.Interaction)
    if not grip then return nil, reason end
    if not Manager.FacingMatches(rec, forward, grip.FaceIndex, Config.Interaction.MaxFacingAngle) then
        return nil, 'WRONG_FACE'
    end
    return grip, nil, rec
end

local function canInteract(c, actor, state)
    if not (valid(actor) and state and state.Enabled and state.Participants) then return false end
    if participantOf(state, c.key) then return false end
    local grip = predictedGrip(c, actor, state)
    return grip ~= nil
end

local function aimCrate(c)
    local cam, endpos = cameraRay(c)
    if not cam then return nil end
    local hits = {}
    local ok = KismetSystemLibrary.LineTraceMultiForObjects(c.controller, cam, endpos, {0, 1}, false,
        {c.pawn}, 0, hits, true, {R = 1, G = 0, B = 0, A = 1}, {R = 0, G = 1, B = 0, A = 1}, 0.1)
    if not ok then return nil end
    for _, entry in ipairs(hits) do
        local actor = entry.Actor and entry.Actor:Get()
        if valid(actor) then
            if not UE.IsA(actor, c.crateClass) then return nil end
            if canInteract(c, actor, actor.CrateState) then return actor end
            return nil
        end
    end
    return nil
end
local function setLabel(widget, label)
    if valid(widget) and valid(widget.WBP_Interact_Left) then
        widget.WBP_Interact_Left:Configure(widget, label)
    end
end

local function prepareWidget(c)
    local ok, err = pcall(function()
        UGCWidgetUtility.CreateWidgetAsync(Config.Interaction.WidgetClassPath, function(widget)
            if current ~= c then
                if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end
                return
            end
            if not valid(widget) then
                log('async widget creation failed; interaction UI disabled')
                return
            end
            c.widget = widget
            widget:SetVisibility(ESlateVisibility.Collapsed)
            widget:AddToViewport(20)
            widget:SetRequestHandler(function()
                local c2 = current
                if not c2 or not valid(c2.pawn) or not valid(c2.controller) then return end
                if c2.pending then return end
                local actor = c2.activeCrate or c2.display
                if not valid(actor) then return end
                local seq = nextSequence(c2.controller)
                if c2.activeCrate == actor then
                    local state = actor.CrateState
                    if not state or not state.SessionId then return end
                    UnrealNetwork.CallUnrealRPC(c2.controller, c2.controller, 'ServerReleasePushPull',
                        actor, state.SessionId, seq)
                else
                    c2.pending = {actor = actor, sequence = seq}
                    UnrealNetwork.CallUnrealRPC(c2.controller, c2.controller, 'ServerRequestPushPull',
                        actor, seq)
                end
            end, function() end)
            log('interaction widget prepared')
        end)
    end)
    if not ok then log('widget preparation failed: ' .. tostring(err)) end
end

local function updateAnchor()
    local c = current
    if not c or not valid(c.widget) or not valid(c.controller) then return end
    if not c.anchorWorld then
        c.widget:SetVisibility(ESlateVisibility.Collapsed)
        return
    end
    local projected = c.widget:SetWorldAnchor(c.controller, c.anchorWorld)
    c.widget:SetVisibility(projected and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
end

local function findLocal(actor, state, key)
    return participantOf(state, key) ~= nil
end

function F.UpdateAnchor()
    updateAnchor()
end

function F.Update()
    local c = current
    if not c or not valid(c.pawn) or not valid(c.controller) then return end
    c.notReady = (c.notReady or 0) + 1
    if not valid(c.controller.PlayerCameraManager) then
        if c.notReady < Config.Interaction.ReadyRetryTicks then return end
        log('camera unavailable; stopping focus')
        F.End()
        return
    end
    c.notReady = 0
    if c.activeCrate and valid(c.activeCrate) then
        local state = c.activeCrate.CrateState
        if not findLocal(c.activeCrate, state, c.key) then c.activeCrate = nil end
    end
    if c.pending and valid(c.pending.actor) then
        local state = c.pending.actor.CrateState
        if findLocal(c.pending.actor, state, c.key) then
            c.activeCrate = c.pending.actor
            c.pending = nil
        elseif not state then
            c.pending = nil
        end
    end
    local display, label, anchor = nil, Config.Interaction.Label, nil
    if valid(c.activeCrate) then
        local state = c.activeCrate.CrateState
        local p = participantOf(state, c.key)
        if p then
            display = c.activeCrate
            label = Config.Interaction.ReleaseLabel
            local rec = crateRecord(display)
            anchor = Manager.GripWorld(rec, p)
        end
    elseif c.pending and valid(c.pending.actor) then
        display = c.pending.actor
        local grip = predictedGrip(c, display, display.CrateState)
        anchor = grip and Manager.GripWorld(crateRecord(display), grip) or nil
        if not anchor then c.pending = nil; display = nil end
    else
        local candidate = aimCrate(c)
        if valid(candidate) then
            display = candidate
            local grip, _, rec = predictedGrip(c, candidate, candidate.CrateState)
            if grip then anchor = Manager.GripWorld(rec, grip) end
            if not anchor then display = nil end
        end
    end
    if c.display ~= display then
        outline(c.display, false)
        c.display = display
        if valid(display) then outline(display, true) end
        log('display changed actor=' .. tostring(display and KismetSystemLibrary.GetObjectName(display)) .. ' label=' .. tostring(label))
        if valid(c.widget) then c.widget:ResetWorldAnchor() end
    end
    c.anchorWorld = anchor
    if valid(c.widget) then
        c.widget:SetButtonVisible(display ~= nil)
        c.widget:SetProgress(nil)
        if c.label ~= label then
            c.label = label
            setLabel(c.widget, label)
        end
        updateAnchor()
    end
    if c.widget then c.widget:SetProgress(nil) end
end

function F.Begin(pawn)
    local pc = localController()
    if not valid(pc) or localPawn() ~= pawn then return false end
    if current then F.End() end
    local key = localKey(pc)
    local cls = UE.LoadClass(Config.Interaction.CrateClassPath)
    if not cls then
        log('crate class unavailable: ' .. tostring(Config.Interaction.CrateClassPath))
        return false
    end
    local c = {pawn = pawn, controller = pc, key = key, crateClass = cls,
        pending = nil, activeCrate = nil, display = nil, anchorWorld = nil}
    current = c
    prepareWidget(c)
    for _, actor in pairs(UGCActorComponentUtility.GetAllActorsOfClass(pawn, cls)) do
        if valid(actor) then F.CrateChanged(actor, actor.CrateState) end
    end
    c.timer = UGCTimerUtility.CreateLuaTimer(Config.Interaction.DetectInterval, F.Update, true,
        'EscapeX.PushPull.Focus')
    c.anchorTimer = UGCTimerUtility.CreateLuaTimer(Config.Interaction.PositionInterval, F.UpdateAnchor, true,
        'EscapeX.PushPull.FocusAnchor')
    log('focus started key=' .. tostring(key))
    return true
end

function F.CrateChanged(actor, state)
    local c = current
    if not c then return end
    if findLocal(actor, state, c.key) then
        c.activeCrate = actor
        c.pending = nil
    elseif c.activeCrate == actor then
        c.activeCrate = nil
    end
end

function F.RequestRejected(sequence, reason)
    local c = current
    if c and c.pending and c.pending.sequence == sequence then
        c.pending = nil
        log('request rejected: ' .. tostring(reason))
    end
end

function F.CrateRemoved(actor)
    local c = current
    if not c then return end
    if c.activeCrate == actor then c.activeCrate = nil end
    if c.pending and c.pending.actor == actor then c.pending = nil end
    if c.display == actor then
        outline(actor, false)
        c.display = nil
        c.anchorWorld = nil
        if valid(c.widget) then c.widget:SetVisibility(ESlateVisibility.Collapsed) end
    end
end

function F.DebugState()
    local c = current
    if not c then return nil end
    return {key=c.key, active=valid(c.activeCrate), display=valid(c.display), pending=c.pending ~= nil, label=c.label, anchor=c.anchorWorld ~= nil}
end

function F.End()
    local c = current
    if not c then return end
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    if c.anchorTimer then UGCTimerUtility.RemoveLuaTimer(c.anchorTimer) end
    outline(c.display, false)
    if valid(c.widget) then c.widget:RemoveFromParent() end
    current = nil
end

function F.Monitor()
    if monitorTimer then return false end
    monitorTimer = UGCTimerUtility.CreateLuaTimer(Config.Interaction.MonitorInterval, function()
        local pawn = localPawn()
        if pawn == watchedPawn then return end
        if watchedPawn then F.End() end
        watchedPawn = pawn
        if valid(pawn) then F.Begin(pawn) end
    end, true, 'EscapeX.PushPull.FocusMonitor')
    return true
end

function F.StopMonitor()
    if monitorTimer then
        UGCTimerUtility.RemoveLuaTimer(monitorTimer)
        monitorTimer = nil
    end
    F.End()
    watchedPawn = nil
end

return F


