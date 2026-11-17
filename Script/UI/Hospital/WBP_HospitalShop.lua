---@class WBP_HospitalShop_C:UUserWidget
---@field Btn_Exit UButton
---@field Btn_Permanent UButton
---@field Btn_Random UButton
---@field Image_0 UImage
---@field Img_Backdrop UImage
---@field Img_Body UImage
---@field Img_Frame UImage
---@field Img_Header UImage
---@field Img_Logo UImage
---@field Img_TabUnderline UImage
---@field Img_Wallet UImage
---@field SZ_Device USafeZone
---@field Text_Funds UTextBlock
---@field CommodityItemClass UClass
--Edit Below--
---@class WBP_HospitalShop_C:UUserWidget
local Shop = {}
local Page = UGCGameSystem.UGCRequire("Script.UI.Hospital.HospitalShopPage")
local Active = { R = 1, G = 1, B = 1, A = 1 }
local Inactive = { R = 0.28, G = 0.35, B = 0.45, A = 1 }

function Shop:Construct()
    if not self.bButtonsBound then
        self.Btn_Exit.OnPressed:Add(self.OnBtnExitClicked, self)
        local ExitSlot = WidgetLayoutLibrary.SlotAsCanvasSlot(self.Btn_Exit)
        if ExitSlot then ExitSlot:SetZOrder(20) end
        self.Btn_Permanent.OnClicked:Add(self.OnPermanentClicked, self)
        self.Btn_Random.OnClicked:Add(self.OnRandomClicked, self)
        self.bButtonsBound = true
    end
    -- Cross-project merges can strip nested UserWidgets from the parent canvas.
    self.PermanentPage = self.PermanentPage or self:GetWidgetFromName("PermanentPage")
        or Page.AttachWidget(self, "CP_Shop", "WBP_HospitalShopPermanent", 28, 198, 1544, 690)
    self.RandomPage = self.RandomPage or self:GetWidgetFromName("RandomPage")
        or Page.AttachWidget(self, "CP_Shop", "WBP_HospitalShopRandom", 28, 198, 1544, 690)
    self.PermanentPage:InitPage(false)
    self.RandomPage:InitPage(true)
    self:SetShopTab(false)
end

function Shop:OnOpen()
    self:OnClose()
    self.bOpened = true
    self:OnFundsChanged(nil)
    self:SetShopTab(false)
end

function Shop:SetShopTab(bRandom)
    local PreviousPage = self.ActivePage
    local Page = bRandom and self.RandomPage or self.PermanentPage
    if PreviousPage == Page then return end
    self.ActivePage = Page
    self.PermanentPage:SetVisibility(bRandom and ESlateVisibility.Collapsed or ESlateVisibility.SelfHitTestInvisible)
    self.RandomPage:SetVisibility(bRandom and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
    self.Btn_Permanent:SetBackgroundColor(bRandom and Inactive or Active)
    self.Btn_Random:SetBackgroundColor(bRandom and Active or Inactive)
    if self.bOpened then
        if PreviousPage then PreviousPage:OnClose() end
        Page:OnOpen()
    end
end

function Shop:OnFundsChanged(Funds)
    self:GetWidgetFromName("Text_Funds"):SetText(Funds ~= nil and ("$" .. tostring(Funds)) or "$ --")
end

function Shop:OnPermanentClicked()
    ugcprint("[HospitalShop] click tab=permanent")
    self:SetShopTab(false)
end

function Shop:OnRandomClicked()
    ugcprint("[HospitalShop] click tab=random")
    self:SetShopTab(true)
end
function Shop:OnBtnExitClicked()
    UGCGameSystem.UGCRequire("Script.Gameplay.ZombieDefense.DefenseShopPresentation").Close()
end
function Shop:OnClose()
    local OpenPage = self.bOpened and self.ActivePage
    self.bOpened = false
    self.ActivePage = nil
    if OpenPage then OpenPage:OnClose() end
end
function Shop:Destruct() self:OnClose() end
return Shop
