-- Passive screen HUD for defense status and Boss health.
local Widget = {}
function Widget:SetStatus(text)
    self.WaveStatus:SetText(text)
end
function Widget:SetBossHealth(percent)
    local visibility = percent ~= nil and ESlateVisibility.HitTestInvisible or ESlateVisibility.Collapsed
    if percent ~= nil then self.BossHealthBar:SetPercent(percent) end
    self.BossName:SetVisibility(visibility)
    self.BossHealthBar:SetVisibility(visibility)
    self.BossHealthFrame:SetVisibility(visibility)
    self.BossHealthEmblem:SetVisibility(visibility)
end
return Widget
