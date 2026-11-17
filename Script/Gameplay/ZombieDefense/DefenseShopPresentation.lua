local M = {}
local current
local ShopZOrder = 10000

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

function M.IsOpen()
    return current ~= nil
end

function M.Open(pc)
    if pc ~= UGCGameSystem.GetLocalPlayerController() or current then return end
    local view = {Controller = pc}
    current = view
    local classPath = UGCGameSystem.GetUGCResourcesFullPath(
        'Asset/UI/Hospital/WBP_HospitalShop.WBP_HospitalShop_C')
    UGCWidgetUtility.CreateWidgetAsync(classPath, function(widget)
        if current ~= view then
            if valid(widget) then UGCWidgetUtility.DestroyWidget(widget) end
            return
        end
        if not valid(widget) then
            current = nil
            ugcprint('[DefenseShop] WBP_HospitalShop is unavailable')
            return
        end
        view.Widget = widget
        widget:AddToViewport(ShopZOrder)
        UGCGameSystem.SetMouseCursorShowState(true)
        widget:OnOpen()
    end)
end

function M.Close(pc)
    local view = current
    if not view or (pc and view.Controller ~= pc) then return end
    current = nil
    if valid(view.Widget) then
        view.Widget:SetVisibility(ESlateVisibility.Collapsed)
        view.Widget:RemoveFromParent()
        UGCWidgetUtility.DestroyWidget(view.Widget)
        UGCGameSystem.SetMouseCursorShowState(false)
    end
end

function M.Receive(pc, state)
    if not state or state.Revision <= (pc.DefenseShopRevision or 0) then return end
    pc.DefenseShopRevision = state.Revision
    pc.HospitalShopState = state
    pc.HospitalShopNextRequestID = math.max(pc.HospitalShopNextRequestID or 0, state.LastProcessedID)
    local pending = pc.HospitalShopPendingPurchase
    if pending and (not state.Ready or pending.RoundID ~= state.RoundID
        or state.LastProcessedID >= pending.RequestID) then
        pc.HospitalShopPendingPurchase = nil
    end
    local view = current
    if not view or view.Controller ~= pc or not valid(view.Widget) then return end
    view.Widget:OnFundsChanged(state.Funds)
    local page = view.Widget.ActivePage
    if page then
        page:OnShopStateUpdate(state)
        if state.Message then page:GetWidgetFromName('Text_Footer'):SetText(state.Message) end
    end
end

return M
