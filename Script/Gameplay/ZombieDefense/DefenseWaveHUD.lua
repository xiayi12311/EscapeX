-- Local-controller owned screen HUD; replicated point text is presentation data only.
local World = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local M = {}
M.Config = {WidgetClassPath='Asset/UI/ZombieSurvival/WBP_ZS_StatusHUD.WBP_ZS_StatusHUD_C',
    RefreshSeconds=0.2, ZOrder=15}
local current
local function valid(o) return o and KismetSystemLibrary.IsValid(o) end
function M.Update()
    local c = current
    if not c or not valid(c.widget) then return end
    local rows = {}
    for _, point in ipairs(UGCActorComponentUtility.GetAllActorsOfClass(c.pc,c.class)) do
        if valid(point) and point.Enabled == true and point.DefenseStarted == true
            and type(point.DefenseStatusText) == 'string' and point.DefenseStatusText ~= '' then
            rows[#rows+1] = {id=tostring(point.EncounterId),text=point.DefenseStatusText}
        end
    end
    table.sort(rows,function(a,b)return a.id < b.id end)
    local lines = {}
    for _, row in ipairs(rows) do lines[#lines+1] = row.text end
    local text = table.concat(lines,'\n')
    if text ~= c.text then c.widget:SetStatus(text);c.text = text end
    c.widget:SetVisibility(text ~= '' and ESlateVisibility.HitTestInvisible or ESlateVisibility.Collapsed)
end
function M.Begin(pc)
    if pc ~= UGCGameSystem.GetLocalPlayerController() then return false end
    if current then M.End() end
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Start))
    if not class then ugcprint('[ZombieHUD] start class unavailable');return false end
    local c = {pc=pc,class=class}
    current = c
    UGCWidgetUtility.CreateWidgetAsync(UGCGameSystem.GetUGCResourcesFullPath(M.Config.WidgetClassPath),function(widget)
        if current ~= c then
            if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end
            return
        end
        if not valid(widget) then ugcprint('[ZombieHUD] widget unavailable');return end
        c.widget = widget
        widget:SetVisibility(ESlateVisibility.Collapsed)
        widget:AddToViewport(M.Config.ZOrder)
        M.Update()
        c.timer = UGCTimerUtility.CreateLuaTimer(M.Config.RefreshSeconds,M.Update,true)
    end)
    return true
end
function M.End(pc)
    local c = current
    if not c or (pc and pc ~= c.pc) then return end
    current = nil
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    if valid(c.widget) then UGCWidgetUtility.DestroyWidget(c.widget) end
end
return M
