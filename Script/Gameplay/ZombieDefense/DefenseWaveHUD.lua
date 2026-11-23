-- Local-controller owned screen HUD for wave status and Boss health.
local World = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWorldPoints')
local Catalog = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseCatalog')
local M = {}
M.Config = {WidgetClassPath='Asset/UI/ZombieSurvival/WBP_ZS_StatusHUD.WBP_ZS_StatusHUD_C',
    RefreshSeconds=0.2, ZOrder=15}
local current
local function valid(o) return o and KismetSystemLibrary.IsValid(o) end
local function bossHealthPercent(c)
    local boss = c.boss
    if not valid(boss) or not UGCGenericCharacterSystem.IsAlive(boss) then
        c.boss = nil
        for _, actor in ipairs(UGCActorComponentUtility.GetAllActorsOfClass(c.pc, c.bossClass)) do
            if valid(actor) and UGCGenericCharacterSystem.IsAlive(actor) then
                c.boss = actor
                break
            end
        end
        boss = c.boss
    end
    if not boss then return nil end

    local health = UGCGenericCharacterSystem.GetHealth(boss)
    local maxHealth = UGCGenericCharacterSystem.GetHealthMax(boss)
    if health <= 0 or maxHealth <= 0 then return nil end
    return math.min(1, health / maxHealth)
end

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
    local bossPercent = bossHealthPercent(c)
    if bossPercent ~= c.bossPercent then
        c.widget:SetBossHealth(bossPercent)
        c.bossPercent = bossPercent
    end
    c.widget:SetVisibility((text ~= '' or bossPercent ~= nil)
        and ESlateVisibility.HitTestInvisible or ESlateVisibility.Collapsed)
end
function M.Begin(pc)
    if pc ~= UGCGameSystem.GetLocalPlayerController() then return false end
    if current then M.End() end
    local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Start))
    if not class then ugcprint('[ZombieHUD] start class unavailable');return false end
    local bossPath = Catalog.BossEncounters.DefenseMainTest.ClassPath
    local bossClass = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(bossPath))
    assert(bossClass, '[ZombieHUD] Boss class unavailable')
    local c = {pc=pc,class=class,bossClass=bossClass}
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
