-- Passive screen text only; wave timing and outcome remain server owned.
local Widget = {}
function Widget:SetStatus(text)
    self.WaveStatus:SetText(text)
end
return Widget
