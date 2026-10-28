-- Presentation only: a click requests the action once. Server state owns progress.
local Button = {}

function Button:Construct()
    if self.Button_Interact then
        self.Button_Interact.OnPressed:Add(self.OnPressed, self)
        self.Button_Interact.OnReleased:Add(self.OnReleased, self)
    end
    if self.Image_Progress then self.ProgressMaterial = self.Image_Progress:GetDynamicMaterial() end
    self:SetProgress(0)
end

function Button:Configure(owner, label)
    self.InteractionOwner = owner
    if self.TextBlock_Label then self.TextBlock_Label:SetText(label) end
end

function Button:SetProgress(value)
    if self.ProgressMaterial then
        self.ProgressMaterial:SetScalarParameterValue('Mask_Percent', math.max(0, math.min(1, value or 0)))
    end
end

function Button:OnPressed()
    if self.InteractionOwner then self.InteractionOwner:OnSearchPressed() end
end

function Button:OnReleased()
    if self.InteractionOwner then self.InteractionOwner:OnSearchReleased() end
end

function Button:Destruct()
    if self.Button_Interact then
        self.Button_Interact.OnPressed:Remove(self.OnPressed, self)
        self.Button_Interact.OnReleased:Remove(self.OnReleased, self)
    end
    self.InteractionOwner = nil
end

return Button
