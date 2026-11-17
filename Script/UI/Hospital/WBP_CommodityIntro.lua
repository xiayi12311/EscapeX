---@class WBP_CommodityIntro_C:UUserWidget
---@field Btn_Buy UButton
---@field Img_Body UImage
---@field Img_Divider UImage
---@field Img_Frame UImage
---@field Img_Preview UImage
---@field Img_PreviewBackground UImage
---@field Img_PriceStrike UImage
---@field Text_OriginalPrice UTextBlock
--Edit Below--
local WBP_CommodityIntro = {}

-- State 为当前玩家的展示状态，不写入商品配置表。
function WBP_CommodityIntro:InitUI(Data, State, OwnerShop)
    if not self.bBuyBound then
        self.Btn_Buy.OnClicked:Add(self.OnBuyClicked, self)
        self.bBuyBound = true
    end
    self.OwnerShop = OwnerShop
    self.CommodityData = Data
    Data = Data or {}
    State = State or {}
    self:GetWidgetFromName("Text_Name"):SetText(tostring(Data.Name or "暂无商品"))
    self:GetWidgetFromName("Text_Category"):SetText(tostring(Data.CategoryName or ""))
    local Description = Data.Description
    if Description == nil or tostring(Description) == "" then
        Description = self.CommodityData and "暂无商品介绍" or "当前页面暂无可展示的商品"
    end
    self:GetWidgetFromName("Text_Desc"):SetText(tostring(Description))
    self:GetWidgetFromName("Scroll_Description"):ScrollToStart()

    -- 缺少独立大图时复用小图；ScaleBox 根据原图比例缩放。
    local PreviewImage = Data.PreviewImage or Data.Icon
    if PreviewImage then
        self.Img_Preview:SetBrushFromTexture(PreviewImage, true)
    end
    self.Img_Preview:SetVisibility(PreviewImage and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
    self:GetWidgetFromName("Text_PreviewPlaceholder"):SetVisibility(PreviewImage and ESlateVisibility.Hidden or ESlateVisibility.HitTestInvisible)
    self:GetWidgetFromName("Text_PreviewPlaceholder"):SetText("暂无图片")
    self:GetWidgetFromName("Img_PreviewBackground"):SetColorAndOpacity(State.PreviewColor or { R = 0.16, G = 0.12, B = 0.24, A = 1 })

    local Price = tonumber(Data.Price)
    self:GetWidgetFromName("Text_Price"):SetText(Price and ("$" .. tostring(Price)) or "$ --")
    local Special = Data.IsSpecialOffer and tonumber(Data.OriginalPrice) and Data.OriginalPrice > (Price or 0)
    self:GetWidgetFromName("Text_OriginalPrice"):SetText("原价 $" .. tostring(Data.OriginalPrice or 0))
    self:GetWidgetFromName("Text_OriginalPrice"):SetVisibility(Special and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
    self:GetWidgetFromName("Img_PriceStrike"):SetVisibility(Special and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
    self:RefreshPurchaseState(State)
end

-- 资金或回包刷新不重置介绍滚动，不改变当前选中商品。
function WBP_CommodityIntro:RefreshPurchaseState(State)
    State = State or {}
    local Data = self.CommodityData or {}
    local Price = tonumber(Data.Price)
    local Funds = tonumber(State.Funds)
    self:GetWidgetFromName("Text_Balance"):SetText(Funds and Price and Funds >= Price and ("$" .. tostring(Funds - Price)) or "$ --")
    local Remaining = tonumber(State.RemainingPurchases)
    local Limit = tonumber(Data.PurchaseLimit)
    local LimitText = Limit and Limit > 0 and ("整局限购 " .. tostring(Limit) .. " 次") or "不限购"
    if not self.CommodityData then LimitText = "" end
    self:GetWidgetFromName("Text_Remaining"):SetText(Remaining and ("整局余 " .. tostring(math.max(0, Remaining)) .. " 次") or LimitText)
    local SoldOut = State.bSoldOut == true or (Remaining ~= nil and Remaining <= 0)
    local Label, Enabled = "暂无商品", false
    if self.CommodityData then
        if State.bPending then Label = "购买处理中…"
        elseif SoldOut then Label = "已售罄"
        elseif not State.bReady then Label = State.UnavailableText or "同步中…"
        elseif not State.bConfigValid then Label = "商品配置无效"
        elseif Funds == nil then Label = "资金同步中…"
        elseif Price == nil or Funds < Price then Label = "资金不足"
        else Label, Enabled = "购买 · $" .. tostring(Price), true end
    end
    self:GetWidgetFromName("Text_BuyLabel"):SetText(Label)
    self.Btn_Buy:SetIsEnabled(Enabled)
end

function WBP_CommodityIntro:OnBuyClicked()
    if self.OwnerShop and self.CommodityData then self.OwnerShop:OnBuyClicked() end
end

return WBP_CommodityIntro
