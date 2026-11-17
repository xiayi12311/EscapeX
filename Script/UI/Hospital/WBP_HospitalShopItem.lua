---@class WBP_HospitalShopItem_C:UUserWidget
--Edit Below--
local WBP_HospitalShopItem = { bInitDoOnce = false }

function WBP_HospitalShopItem:Construct()
    if not self.bInitDoOnce then
        self.Btn_Select.OnClicked:Add(self.OnSelectedClicked, self)
        self:GetWidgetFromName("Btn_Lock").OnClicked:Add(self.OnLockClicked, self)
        self.bInitDoOnce = true
    end
end

-- Data 为展示数据；商品表字段转换由主界面负责。
function WBP_HospitalShopItem:InitUI(Data, OwnerShop, State)
    self.CommodityData = Data
    self.OwnerShop = OwnerShop
    Data = Data or {}
    State = State or {}
    self.bDaily = OwnerShop and OwnerShop.bRandomShop == true
    self.PurchaseLimit = tonumber(Data.PurchaseLimit)

    self:GetWidgetFromName("Text_Name"):SetText(tostring(Data.Name or "暂无商品"))
    self:GetWidgetFromName("Text_Category"):SetText(tostring(Data.CategoryName or "未分类"))
    local Price = tonumber(Data.Price)
    self:GetWidgetFromName("Text_Price"):SetText(Price and ("$" .. tostring(Price)) or "$ --")
    local Special = Data.IsSpecialOffer and tonumber(Data.OriginalPrice) and Data.OriginalPrice > (Price or 0)
    self:GetWidgetFromName("Text_OriginalPrice"):SetText("原价 $" .. tostring(Data.OriginalPrice or 0))
    self:GetWidgetFromName("Text_OriginalPrice"):SetVisibility(Special and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
    self:GetWidgetFromName("Img_PriceStrike"):SetVisibility(Special and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)

    local HasIcon = Data.Icon ~= nil
    if HasIcon then
        self.Img_Commodity:SetBrushFromTexture(Data.Icon, true)
    end
    self.Img_Commodity:SetVisibility(HasIcon and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
    self:GetWidgetFromName("Text_IconPlaceholder"):SetVisibility(HasIcon and ESlateVisibility.Hidden or ESlateVisibility.HitTestInvisible)
    self:GetWidgetFromName("Text_IconPlaceholder"):SetText("暂无图片")
    self.Img_IconBackground:SetColorAndOpacity(State.PreviewColor or { R = 0.075, G = 0.17, B = 0.22, A = 1 })

    self:SetSoldOut(State.bSoldOut, State.RemainingPurchases)
    self:SetSelected(State.bSelected == true)
    self.Btn_Select:SetIsEnabled(self.CommodityData ~= nil)
    self:SetLockState(State)
end

function WBP_HospitalShopItem:SetSelected(bSelected)
    self.bSelected = bSelected == true
    self.Img_Selected:SetVisibility(self.bSelected and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
end

function WBP_HospitalShopItem:SetSoldOut(bSoldOut, RemainingPurchases)
    self.RemainingPurchases = tonumber(RemainingPurchases)
    self.bSoldOut = bSoldOut == true or (self.RemainingPurchases ~= nil and self.RemainingPurchases <= 0)
    self:GetWidgetFromName("CP_SoldOut"):SetVisibility(self.bSoldOut and ESlateVisibility.HitTestInvisible or ESlateVisibility.Hidden)
    local LimitText = self.PurchaseLimit and self.PurchaseLimit > 0 and ("整局限购 " .. tostring(self.PurchaseLimit) .. " 次") or "不限购"
    if not self.CommodityData then LimitText = "" end
    -- 尚未同步玩家已购次数时显示配置上限，避免把上限当成真实剩余。
    self:GetWidgetFromName("Text_Remaining"):SetText(self.RemainingPurchases and ("整局余 " .. tostring(math.max(0, self.RemainingPurchases)) .. " 次") or LimitText)
end

function WBP_HospitalShopItem:SetLockState(State)
    State = State or {}
    local Button = self:GetWidgetFromName("Btn_Lock")
    Button:SetVisibility(self.CommodityData and self.bDaily and ESlateVisibility.Visible or ESlateVisibility.Collapsed)
    Button:SetIsEnabled(State.bCanLock == true)
    self:GetWidgetFromName("Text_Lock"):SetText(State.bLocked and "已锁" or "锁定")
    Button:SetBackgroundColor(State.bLocked and { R = 0.2, G = 0.7, B = 0.9, A = 1 }
        or { R = 0.2, G = 0.3, B = 0.4, A = 1 })
end

function WBP_HospitalShopItem:OnLockClicked()
    if self.OwnerShop then self.OwnerShop:OnLockClicked(self.CommodityData) end
end

-- 同一商品widget复用为常驻矮卡与随机长卡，文字保持原字号、图片保持比例。
function WBP_HospitalShopItem:SetCardHeight(Height)
    local function Box(Name, X, Y, W, H)
        local Slot = self:GetWidgetFromName(Name).Slot
        Slot:SetPosition({ X = X, Y = Y })
        Slot:SetSize({ X = W, Y = H })
    end
    Box("Img_Selected", 0, 0, 340, Height)
    Box("Img_Frame", 3, 3, 334, Height - 6)
    Box("Img_Body", 5, 5, 330, Height - 10)
    local Special = self.CommodityData and self.CommodityData.IsSpecialOffer
        and (self.CommodityData.OriginalPrice or 0) > (self.CommodityData.Price or 0)
    local ArtHeight = Height - (Special and 174 or 155)
    Box("Text_Name", 18, 12, Height > 228 and 224 or 304, 36)
    Box("Text_Category", 18, 49, Height > 228 and 224 or 304, 30)
    Box("Img_IconBackground", 18, 85, 304, ArtHeight)
    Box("Scale_Icon", 18, 85, 304, ArtHeight)
    Box("Text_IconPlaceholder", 18, 85 + (ArtHeight - 32) / 2, 304, 32)
    Box("Text_Price", 18, Height - 50, 172, 40)
    Box("Text_Remaining", 194, Height - 42, 130, 32)
    Box("Text_OriginalPrice", 18, Height - 81, 172, 30)
    Box("Img_PriceStrike", 18, Height - 65, 145, 2)
    Box("Img_SoldOutShade", 5, 5, 330, Height - 10)
    Box("Img_SoldOutBand", 18, (Height - 54) / 2, 304, 54)
    Box("Text_SoldOut", 18, (Height - 40) / 2, 304, 40)
end

-- 售罄也允许选中查看详情；卡片不发起购买。
function WBP_HospitalShopItem:OnSelectedClicked()
    if self.CommodityData and self.OwnerShop and self.OwnerShop.OnCommoditySelected then
        self.OwnerShop:OnCommoditySelected(self.CommodityData, self)
    end
end

return WBP_HospitalShopItem
