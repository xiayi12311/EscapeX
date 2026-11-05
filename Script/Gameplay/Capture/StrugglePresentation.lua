-- Local presentation for the imprisoned player; the server owns progress and release.
local Interaction = UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.InteractionConfig')
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureConfig')
local M = {}
local active
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

local function remove()
    local c = active
    active = nil
    if not c then return end
    if c.setupTimer then UGCTimerUtility.RemoveLuaTimer(c.setupTimer) end
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    if valid(c.widget) then
        c.widget:RemoveFromParent()
        UGCWidgetUtility.DestroyWidget(c.widget)
    end
end

local function draw(c)
    if active ~= c or not valid(c.widget) or not valid(c.controller) then return end
    local s = c.state
    local now = UGCGameSystem.GetTimeSeconds(c.controller)
    local elapsed = math.max(0, now - c.receivedAt)
    local progress = math.max(0, math.min(1, s.Struggle / s.StruggleNeed
        - elapsed * s.StruggleDecayPerSecond))
    c.widget:SetProgress(progress)
end

function M.Update(post, state)
    local pc = UGCGameSystem.GetLocalPlayerController()
    if not valid(pc) then remove(); return end
    local key = UGCGameSystem.GetPlayerKeyByPlayerController(pc)
    if not state or state.State ~= 'Imprisoned' or state.PlayerKey ~= key
        or state.StruggleReady ~= true then
        if active and active.post == post then remove() end
        return
    end
    if type(state.Struggle) ~= 'number' or type(state.StruggleNeed) ~= 'number'
        or state.StruggleNeed <= 0 or type(state.StruggleDecayPerSecond) ~= 'number' then
        ugcprint('[HTCapture] invalid struggle progress data')
        if active and active.post == post then remove() end
        return
    end
    if not active or active.post ~= post or active.sessionId ~= state.SessionId then
        remove()
        local c = {post=post, sessionId=state.SessionId, controller=pc, state=state,
            receivedAt=UGCGameSystem.GetTimeSeconds(pc)}
        active = c
        UGCWidgetUtility.CreateWidgetAsync(Interaction.WidgetClassPath, function(widget)
            if active ~= c then if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end; return end
            if not valid(widget) then ugcprint('[HTCapture] struggle widget creation failed'); return end
            c.widget = widget
            -- Async load may invoke this callback while the game thread is blocked on
            -- rendering; AddToViewport constructs dynamic materials, so defer it.
            c.setupTimer = UGCTimerUtility.CreateLuaTimer(Config.Defaults.StruggleUISetupDelay, function()
                c.setupTimer = nil
                if active ~= c or not valid(widget) then return end
                widget:AddToViewport(20)
                widget.CP_CurrentActor:SetVisibility(ESlateVisibility.Collapsed)
                widget.WBP_Interact_Left:Configure(widget, '挣脱')
                widget.WBP_Interact_Left.PressedFeedback = true
                widget:SetRequestHandler(function()
                    if active == c and valid(c.post) and valid(c.controller) then
                        UnrealNetwork.CallUnrealRPC(c.controller,c.controller,'ServerRequestStruggle',c.post,c.sessionId)
                    end
                end, nil)
                widget:SetButtonVisible(true)
                c.timer = UGCTimerUtility.CreateLuaTimer(Config.Defaults.StruggleUIRefreshInterval, function() draw(c) end, true)
                draw(c)
            end, false)
        end)
    end
    active.state = state
    active.receivedAt = UGCGameSystem.GetTimeSeconds(pc)
    draw(active)
end

function M.End(post)
    if active and active.post == post then remove() end
end

return M
