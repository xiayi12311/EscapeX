-- Presentation only: a click requests the action once. Server state owns progress.
local Button = {}

function Button:Construct()
    if self.Button_Interact then
        self.Button_Interact.OnClicked:Add(self.OnClicked, self)
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

function Button:OnClicked()
    if self.InteractionOwner then self.InteractionOwner:OnSearchClicked() end
end

function Button:Destruct()
    if self.Button_Interact then self.Button_Interact.OnClicked:Remove(self.OnClicked, self) end
    self.InteractionOwner = nil
end

return Button
