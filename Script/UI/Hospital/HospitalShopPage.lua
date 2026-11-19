-- 常驻/随机独立子页面的共用交互；资金与页签由外层WBP_HospitalShop管理。
local HospitalShopData = UGCGameSystem.UGCRequire("Script.UI.Hospital.HospitalShopData")

local Stock = UGCGameSystem.UGCRequire("Script.Gameplay.ZombieDefense.DefenseShopStock")
local CategoryKeys = { All = true, Weapon = true, Supply = true }
local ActiveColor = { R = 1, G = 1, B = 1, A = 1 }
local InactiveColor = { R = 0.28, G = 0.35, B = 0.45, A = 1 }
local WBP_HospitalShop = { bInitDoOnce = false }

-- 独立子页面共用行为；控件和页面状态各自独立。
function WBP_HospitalShop.AttachWidget(Owner, PanelName, AssetName, X, Y, Width, Height)
    local Panel = assert(Owner:GetWidgetFromName(PanelName), "missing shop canvas " .. PanelName)
    local Path = "Asset/UI/Hospital/" .. AssetName .. "." .. AssetName .. "_C"
    local Class = assert(UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(Path)), "missing shop class " .. AssetName)
    local Widget = assert(UserWidget.NewWidgetObjectBP(UGCGameSystem.GetLocalPlayerController(), Class),
        "could not create " .. AssetName)
    local Slot = assert(Panel:AddChildToCanvas(Widget), "could not attach " .. AssetName)
    Slot:SetPosition({X = X, Y = Y})
    Slot:SetSize({X = Width, Y = Height})
    return Widget
end

function WBP_HospitalShop:Construct()
    if not self.bInitDoOnce then
        self.Btn_Previous.OnClicked:Add(self.OnPreviousClicked, self)
        self.Btn_Next.OnClicked:Add(self.OnNextClicked, self)
        self:GetWidgetFromName("Btn_RandomRefresh").OnClicked:Add(self.OnRefreshClicked, self)
        self.bInitDoOnce = true
    end
end

function WBP_HospitalShop:InitPage(bRandom)
    self.bRandomShop = bRandom
    self:CacheCards()
    self:ReloadCatalog()
    self:SetShopTab(bRandom)
end

function WBP_HospitalShop:CacheCards()
    if self.Cards then return end
    local Cards = {}
    for Index = 1, (self.bRandomShop and 3 or 6) do
        Cards[Index] = self:GetWidgetFromName("ShopItem_" .. tostring(Index))
            or WBP_HospitalShop.AttachWidget(self, "CP_ProductGrid", "WBP_HospitalShopItem", 0, 0, 340, 228)
    end
    self.ShopDetailView = self:GetWidgetFromName("ShopDetail")
        or WBP_HospitalShop.AttachWidget(self, "CP_Page", "WBP_CommodityIntro", 1064, 0, 480, 648)
    self.Cards = Cards
end

function WBP_HospitalShop:ReloadCatalog()
    local Succeeded, Rows = pcall(Stock.Rows)
    if not Succeeded then
        ugcprint("[HospitalShop] 商品表读取失败：" .. tostring(Rows))
        Rows = {}
    end
    local Errors
    self.Catalog, Errors = HospitalShopData.BuildCatalog(Rows or {})
    for _, Error in ipairs(Errors) do
        ugcprint("[HospitalShop] " .. Error)
    end
end

function WBP_HospitalShop:OnOpen()
    if not self.Cards then self:CacheCards() end
    self:OnClose()
    self.bShopStateReceived = false
    self.DisplayFunds = nil
    self.RandomOfferKey = nil
    self.ShopPlayerController = UGCGameSystem.GetLocalPlayerController()

    self:ReloadCatalog()
    self:SetShopTab(self.bRandomShop)
    self:RefreshPurchaseState()
    self:RequestShopState()
    -- 仅同步状态，不重发购买；购买回包延迟时也保持防连点。
    self.ShopStateTimer = UGCTimerUtility.CreateLuaTimer(5, function()

        self:RequestShopState()
    end, true)
end

function WBP_HospitalShop:RequestShopState()
    local PC = self.ShopPlayerController
    if PC then UnrealNetwork.CallUnrealRPC(PC, PC, "RPC_Server_RequestHospitalShopState") end
end

function WBP_HospitalShop:OnShopStateUpdate(State)
    self.bShopStateReceived = true
    self.DisplayFunds = State.Funds
    local Random = State.RandomState or {}
    local Key = table.concat({tostring(State.RoundID), tostring(Random.Day), tostring(Random.OfferVersion)}, ":")
    local Changed = self.RandomOfferKey ~= Key
    self.RandomOfferKey = Key
    if self.bRandomShop and Changed then
        self:ReloadCatalog()
        self:RenderPage(1)
    end
    self:RefreshPurchaseState()
end

function WBP_HospitalShop:GetRandomGoods()
    local PC = self.ShopPlayerController
    local Snapshot = PC and PC.HospitalShopState
    local Random = self.bShopStateReceived and Snapshot and Snapshot.RandomState
    if not Random or not Random.Ready then return {} end
    local ByID, Goods = {}, {}
    for _, Data in ipairs(self.Catalog or {}) do
        if HospitalShopData.HasTag(Data, 1) then ByID[Data.CommodityID] = Data end
    end
    for _, ID in ipairs(Random.CommodityIDs or {}) do
        local Offer = (Random.Offers or {})[#Goods + 1]
        Goods[#Goods + 1] = ID > 0 and HospitalShopData.MergeOffer(ByID[ID], Offer) or false
    end
    return Goods
end

function WBP_HospitalShop:GetPurchaseState(Data)
    local PC = self.ShopPlayerController
    local Snapshot = PC and PC.HospitalShopState
    local Ready = self.bShopStateReceived == true and Snapshot ~= nil
    local Random = Ready and Snapshot.RandomState
    local Counts = Ready and Snapshot.BoughtCounts or {}
    if Data and self.bRandomShop then
        local Listed = false
        if Random and Random.Ready then
            for _, ID in ipairs(Random.CommodityIDs or {}) do
                if ID == Data.CommodityID then Listed = true end
            end
        end
        Ready = Ready and Listed
        Counts = Random and Random.BoughtCounts or {}
    end
    local Limit = Data and Data.PurchaseLimit or 0
    local Bought = Ready and Data and (Counts[tostring(Data.CommodityID)] or 0) or 0
    local Unlimited = Ready and Snapshot.InfiniteFunds == true
    local Remaining = Ready and not Unlimited and Limit > 0 and math.max(0, Limit - Bought) or nil
    local Price = Data and Data.Price
    local ItemID = Data and tonumber(Data.ItemID)
    local ItemNum = Data and tonumber(Data.ItemNum)
    local ConfigValid = Price ~= nil and Price >= 0 and Price == math.floor(Price)
        and ItemID ~= nil and ItemID > 0 and ItemID == math.floor(ItemID)
        and ItemNum ~= nil and ItemNum > 0 and ItemNum == math.floor(ItemNum)
    return {
        Funds = self.DisplayFunds,
        InfiniteFunds = Unlimited,
        RemainingPurchases = Remaining,
        bSoldOut = Remaining ~= nil and Remaining <= 0,
        bPending = PC ~= nil and PC.HospitalShopPendingPurchase ~= nil,
        bReady = Ready and Snapshot.Ready == true,
        bConfigValid = ConfigValid,
        bLocked = Data and Random and Random.LockedCommodityID == Data.CommodityID,
        bCanLock = Data ~= nil and Data ~= false and self.bRandomShop and Ready and Snapshot.Ready
            and not PC.HospitalShopPendingPurchase and (Remaining == nil or Remaining > 0)
            and (Random.LockedCommodityID == 0 or Random.LockedCommodityID == Data.CommodityID),
        UnavailableText = Ready and (Snapshot.Fault and "发货状态异常" or "商店暂不可用") or "同步中…",
    }
end

function WBP_HospitalShop:RefreshRandomControls()
    local PC = self.ShopPlayerController
    local Snapshot = PC and PC.HospitalShopState
    local Random = self.bShopStateReceived and Snapshot and Snapshot.RandomState
    local Button = self:GetWidgetFromName("Btn_RandomRefresh")
    local Label = "同步中…"
    local Enabled = false
    if Random and Random.Ready then
        local limited = not Snapshot.InfiniteFunds and Random.RefreshLimit > 0
        local Remaining = limited and math.max(0, Random.RefreshLimit - Random.RefreshUsed) or math.huge
        local Times = limited and string.format("刷新余 %d/%d", Remaining, Random.RefreshLimit) or "刷新不限次"
        self:GetWidgetFromName("Text_RandomSchedule"):SetText(string.format("第 %d 夜 · %s", Random.Day, Times))
        Label = Snapshot.InfiniteFunds and "刷新 · GM 免费" or "刷新 · $" .. tostring(Random.RefreshCost)
        if PC.HospitalShopPendingPurchase then Label = "处理中…"
        elseif not Snapshot.Ready then Label = Snapshot.Fault and "交易状态异常" or "商店暂不可用"
        elseif Remaining <= 0 then Label = "本波刷新已用完"
        elseif not Random.CanReplace then Label = "暂无可替换商品"
        elseif not Snapshot.InfiniteFunds and (self.DisplayFunds == nil or self.DisplayFunds < Random.RefreshCost) then Label = "刷新 $" .. tostring(Random.RefreshCost) .. " · 资金不足"
        else Enabled = true end
    else
        self:GetWidgetFromName("Text_RandomSchedule"):SetText("每波更新 · 整局限购")
    end
    Button:SetIsEnabled(self.bRandomShop and Enabled)
    self:GetWidgetFromName("Text_RandomRefreshLabel"):SetText(Label)
end

function WBP_HospitalShop:BeginShopRequest(Kind)
    local PC = self.ShopPlayerController
    if not PC or PC.HospitalShopPendingPurchase then return end
    PC.HospitalShopNextRequestID = (PC.HospitalShopNextRequestID or 0) + 1
    PC.HospitalShopPendingPurchase = { RequestID = PC.HospitalShopNextRequestID,
        RoundID = PC.HospitalShopState.RoundID, Kind = Kind }
    return PC.HospitalShopNextRequestID
end

function WBP_HospitalShop:OnRefreshClicked()
    local PC = self.ShopPlayerController
    if not self.bRandomShop or not self.bShopStateReceived or not PC or PC.HospitalShopPendingPurchase then return end
    local Snapshot = PC.HospitalShopState
    local Random = Snapshot and Snapshot.RandomState
    if not Snapshot or not Snapshot.Ready or not Random or not Random.Ready or not Random.CanReplace
        or (not Snapshot.InfiniteFunds and ((Random.RefreshLimit > 0 and Random.RefreshUsed >= Random.RefreshLimit)
            or self.DisplayFunds == nil or self.DisplayFunds < Random.RefreshCost)) then return end
    local RequestID = self:BeginShopRequest("Refresh")
    if RequestID then
        UnrealNetwork.CallUnrealRPC(PC, PC, "RPC_Server_RefreshHospitalShop", RequestID, Snapshot.RoundID, Random.Day, Random.OfferVersion)
        self:RefreshPurchaseState()
    end
end

function WBP_HospitalShop:RefreshPurchaseState()
    self:RefreshRandomControls()
    for _, Card in ipairs(self.Cards or {}) do
        local State = self:GetPurchaseState(Card.CommodityData)
        Card:SetSoldOut(State.bSoldOut, State.RemainingPurchases)
        Card:SetLockState(State)
    end
    self.ShopDetailView:RefreshPurchaseState(self:GetPurchaseState(self.SelectedCommodityData))
end

function WBP_HospitalShop:OnBuyClicked()
    local Data = self.SelectedCommodityData
    local PC = self.ShopPlayerController
    local State = self:GetPurchaseState(Data)
    if not Data or not PC or not State.bReady or not State.bConfigValid or State.bPending
        or State.bSoldOut or (not State.InfiniteFunds and (State.Funds == nil or State.Funds < Data.Price)) then return end
    local Snapshot = PC.HospitalShopState
    local Random = Snapshot.RandomState or {}
    local RequestID = self:BeginShopRequest("Buy")
    if RequestID then
        UnrealNetwork.CallUnrealRPC(PC, PC, "RPC_Server_BuyCommodity", Data.CommodityID, RequestID,
            Snapshot.RoundID, Random.Day, Random.OfferVersion)
        self:RefreshPurchaseState()
    end
end

function WBP_HospitalShop:OnClose()
    if self.ShopStateTimer then
        UGCTimerUtility.RemoveLuaTimer(self.ShopStateTimer)
        self.ShopStateTimer = nil
    end
end

function WBP_HospitalShop:Destruct()
    self:OnClose()
end

function WBP_HospitalShop:SetShopTab(bRandom)
    self.bRandomShop = bRandom == true
    self.CategoryKey = "All"
    if self.bRandomShop then
        -- 兼容尚未删除分类按钮的旧随机页资产。
        for Key in pairs(CategoryKeys) do
            local Button = self:GetWidgetFromName("Btn_" .. Key)
            if Button then Button:SetVisibility(ESlateVisibility.Collapsed) end
        end
    end
    self:GetWidgetFromName("CP_RandomHeader"):SetVisibility(self.bRandomShop and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Collapsed)
    self:GetWidgetFromName("Text_SectionHint"):SetVisibility(self.bRandomShop and ESlateVisibility.Collapsed or ESlateVisibility.HitTestInvisible)
    self:RenderPage(1)
end

function WBP_HospitalShop:OnAllClicked()
    self:SetCategory("All")
end

function WBP_HospitalShop:OnWeaponClicked()
    self:SetCategory("Weapon")
end

function WBP_HospitalShop:OnSupplyClicked()
    self:SetCategory("Supply")
end

function WBP_HospitalShop:SetCategory(CategoryKey)
    ugcprint("[HospitalShop] click category=" .. CategoryKey)
    if self.bRandomShop or not CategoryKeys[CategoryKey] then return end
    self.CategoryKey = CategoryKey
    self:RenderPage(1)
end

function WBP_HospitalShop:OnPreviousClicked()
    if self.bRandomShop or (self.CurrentPage or 0) <= 1 then return end
    self:RenderPage(self.CurrentPage - 1)
end

function WBP_HospitalShop:OnNextClicked()
    if self.bRandomShop or (self.CurrentPage or 0) >= (self.PageCount or 0) then return end
    self:RenderPage(self.CurrentPage + 1)
end

function WBP_HospitalShop:RenderPage(RequestedPage)
    local Goods = self.bRandomShop and self:GetRandomGoods() or HospitalShopData.FilterCatalog(self.Catalog, 0, self.CategoryKey)
    local PageGoods, Page, PageCount = HospitalShopData.GetPage(Goods, RequestedPage, self.bRandomShop and 3 or 6)
    self.CurrentGoods = Goods
    self.PageGoods = PageGoods
    self.CurrentPage = Page
    self.PageCount = PageCount
    self.SelectedCommodityData = nil
    for Index, Card in ipairs(self.Cards or {}) do
        local Data = PageGoods[Index] or nil
        local Tall = self.bRandomShop and Index <= 3
        Card.Slot:SetPosition({ X = ((Index - 1) % 3) * 350, Y = Index <= 3 and 0 or 236 })
        Card.Slot:SetSize({ X = 340, Y = Tall and 464 or 228 })
        Card:InitUI(Data, self, self:GetPurchaseState(Data))
        Card:SetCardHeight(Tall and 464 or 228)
        Card:SetVisibility(Data and ESlateVisibility.SelfHitTestInvisible or ESlateVisibility.Hidden)
    end
    if not self.bRandomShop then
        self.Btn_All:SetBackgroundColor(self.CategoryKey == "All" and ActiveColor or InactiveColor)
        self.Btn_Weapon:SetBackgroundColor(self.CategoryKey == "Weapon" and ActiveColor or InactiveColor)
        self.Btn_Supply:SetBackgroundColor(self.CategoryKey == "Supply" and ActiveColor or InactiveColor)
    end
    self.Btn_Previous:SetIsEnabled(Page > 1)
    self.Btn_Next:SetIsEnabled(Page > 0 and Page < PageCount)
    self:GetWidgetFromName("Text_Page"):SetText(tostring(Page) .. " / " .. tostring(PageCount))
    local Count = #Goods
    self:GetWidgetFromName("Text_SectionHint"):SetText("共 " .. tostring(Count) .. " 件 · 每页 6 件")
    local Footer = "常驻供应 · 随时补给"
    if self.bRandomShop then
        Footer = #Goods > 0 and "每波更新 · 整局限购 · 最多锁定1件，购买自动解锁" or (self.bShopStateReceived and "暂无特供商品" or "正在同步特供商品…")
    elseif Count == 0 then
        Footer = self.CategoryKey == "All" and "暂无商品" or "该分类暂无商品"
    end
    self:GetWidgetFromName("Text_Footer"):SetText(Footer)
    local First
    for Index, Data in ipairs(PageGoods) do if Data and not First then First = Index end end
    if First then self:OnCommoditySelected(PageGoods[First], self.Cards[First])
    else self.ShopDetailView:InitUI(nil, self:GetPurchaseState(nil), self) end
    self:RefreshRandomControls()
    ugcprint(string.format("[HospitalShop] shop=%s category=%s page=%d/%d total=%d visible=%d",
        self.bRandomShop and "Random" or "Permanent", self.CategoryKey, Page, PageCount, Count, #PageGoods))
end

function WBP_HospitalShop:OnCommoditySelected(Data, SelectedCard)
    self.SelectedCommodityData = Data
    for _, Card in ipairs(self.Cards or {}) do
        Card:SetSelected(Card == SelectedCard)
    end
    self.ShopDetailView:InitUI(Data, self:GetPurchaseState(Data), self)
    ugcprint("[HospitalShop] selected=" .. tostring(Data.CommodityID))
end

function WBP_HospitalShop:OnLockClicked(Data)
    if not Data then return end
    local State = self:GetPurchaseState(Data)
    if not State.bCanLock then return end
    local PC = self.ShopPlayerController
    local Snapshot = PC.HospitalShopState
    local Random = Snapshot.RandomState
    local RequestID = self:BeginShopRequest("Lock")
    if RequestID then
        UnrealNetwork.CallUnrealRPC(PC, PC, "RPC_Server_LockHospitalShop", Data.CommodityID, RequestID,
            Snapshot.RoundID, Random.Day, Random.OfferVersion)
        self:RefreshPurchaseState()
    end
end

return WBP_HospitalShop
