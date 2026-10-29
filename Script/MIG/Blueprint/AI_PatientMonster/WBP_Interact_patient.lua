-- Shared interaction visuals; this widget never completes gameplay locally.
local Widget = {}

function Widget:Construct()
    self.CircleMaterial = self.Image_CircleProgress and self.Image_CircleProgress:GetDynamicMaterial()
    if self.WBP_Interact_Left then self.WBP_Interact_Left:Configure(self, '搜索') end
    if self.WBP_Interact_Right then self.WBP_Interact_Right:SetVisibility(ESlateVisibility.Collapsed) end
    self:SetProgress(nil)
end

function Widget:SetRequestHandler(pressed, released)
    self.RequestHandler = pressed
    self.ReleaseHandler = released
end

function Widget:OnSearchPressed()
    if self.RequestHandler then self.RequestHandler() end
end

function Widget:OnSearchReleased()
    if self.ReleaseHandler then self.ReleaseHandler() end
end

function Widget:SetButtonVisible(visible)
    if self.WBP_Interact_Left then
        self.WBP_Interact_Left:SetVisibility(visible and ESlateVisibility.Visible or ESlateVisibility.Collapsed)
    end
end

-- nil hides the circle. A number is presentation of server-owned time only.
function Widget:SetProgress(value)
    if self.Image_CircleProgress then
        self.Image_CircleProgress:SetVisibility(value ~= nil and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
    end
    if self.CircleMaterial then
        self.CircleMaterial:SetScalarParameterValue('Mask_Percent', math.max(0, math.min(1, value or 0)))
    end
    if self.WBP_Interact_Left then self.WBP_Interact_Left:SetProgress(value or 0) end
end

-- Project from world into the current viewport, accounting for DPI, canvas anchor,
-- alignment and panel size in the same way as the source project.
function Widget:SetWorldAnchor(controller, point)
    local ok, projected = WidgetLayoutLibrary.ProjectWorldLocationToWidgetPosition(controller, point)
    if not ok then return false end
    local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(self.CP_CurrentActor)
    if not slot then return false end
    local scale = WidgetLayoutLibrary.GetViewportScale(controller)
    if not scale or scale <= 0 then return false end
    local size = WidgetLayoutLibrary.GetViewportSize(controller)
    local anchors, alignment, own = slot:GetAnchors(), slot:GetAlignment(), slot:GetSize()
    local x = projected.X - anchors.Minimum.X * size.X / scale - (0.5 - alignment.X) * own.X
    local y = projected.Y - anchors.Minimum.Y * size.Y / scale - (0.5 - alignment.Y) * own.Y
    if self.LastAnchorX and math.abs(x-self.LastAnchorX)<4 and math.abs(y-self.LastAnchorY)<4 then return true end
    slot:SetPosition(Vector2D.New(x, y))
    self.LastAnchorX,self.LastAnchorY=x,y
    return true
end

function Widget:ResetWorldAnchor()
    self.LastAnchorX,self.LastAnchorY=nil,nil
end

function Widget:Destruct()
    self.RequestHandler = nil
    self.ReleaseHandler = nil
end

return Widget
