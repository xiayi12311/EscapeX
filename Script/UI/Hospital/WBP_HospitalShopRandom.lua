---@class WBP_HospitalShopRandom_C:UUserWidget
---@field Btn_Next UButton
---@field Btn_Previous UButton
---@field Btn_RandomRefresh UButton
---@field ShopDetail WBP_CommodityIntro_C
---@field ShopItem_1 WBP_HospitalShopItem_C
---@field ShopItem_2 WBP_HospitalShopItem_C
---@field ShopItem_3 WBP_HospitalShopItem_C
---@field Text_Footer UTextBlock
---@field Text_Page UTextBlock
---@field Text_RandomRefreshLabel UTextBlock
---@field Text_RandomSchedule UTextBlock
---@field CommodityItemClass UClass
--Edit Below--
-- 页面拥有各自控件和实例状态，共用已验证的商品交互逻辑。
local Page = {}
for Key, Value in pairs(UGCGameSystem.UGCRequire("Script.UI.Hospital.HospitalShopPage")) do Page[Key] = Value end
return Page