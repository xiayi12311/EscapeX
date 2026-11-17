---@class WBP_HospitalShopPermanent_C:UUserWidget
---@field Btn_All UButton
---@field Btn_Next UButton
---@field Btn_Previous UButton
---@field Btn_RandomRefresh UButton
---@field Btn_Supply UButton
---@field Btn_Weapon UButton
---@field ShopDetail WBP_CommodityIntro_C
---@field ShopItem_1 WBP_HospitalShopItem_C
---@field ShopItem_2 WBP_HospitalShopItem_C
---@field ShopItem_3 WBP_HospitalShopItem_C
---@field ShopItem_4 WBP_HospitalShopItem_C
---@field ShopItem_5 WBP_HospitalShopItem_C
---@field ShopItem_6 WBP_HospitalShopItem_C
---@field Text_Footer UTextBlock
---@field Text_Page UTextBlock
---@field Text_RandomRefreshLabel UTextBlock
---@field Text_RandomSchedule UTextBlock
---@field CommodityItemClass UClass
--Edit Below--
-- 页面拥有各自控件和实例状态，共用已验证的商品交互逻辑。
local SharedPage = UGCGameSystem.UGCRequire("Script.UI.Hospital.HospitalShopPage")
local Page = {}
for Key, Value in pairs(SharedPage) do Page[Key] = Value end

function Page:Construct()
    if not self.bInitDoOnce then
        self.Btn_All.OnClicked:Add(self.OnAllClicked, self)
        self.Btn_Weapon.OnClicked:Add(self.OnWeaponClicked, self)
        self.Btn_Supply.OnClicked:Add(self.OnSupplyClicked, self)
        for _, CategoryKey in ipairs({ "All", "Weapon", "Supply" }) do
            local Key = CategoryKey
            local Button = self["Btn_" .. Key]
            Button.OnPressed:Add(function()
                ugcprint("[HospitalShop] press category=" .. Key)
            end, self)
        end
    end
    SharedPage.Construct(self)
end

return Page
