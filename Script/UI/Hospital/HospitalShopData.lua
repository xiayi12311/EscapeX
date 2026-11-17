-- 将商品表转换为UI展示数据，不修改原表，也不处理购买。
local HospitalShopData = {}
local Rules = UGCGameSystem.UGCRequire("Script.utils.HospitalShopRandom")
HospitalShopData.HasTag = Rules.HasTag

-- 对应现有 Enum_YXHospitalBaseType，追加Package=4；折扣独立由Tag数组判断。
local CategoryNames = { [0] = "设备", [1] = "补给", [2] = "武器", [3] = "角色", [4] = "礼包" }
local CategoryKeys = { [0] = "Other", [1] = "Supply", [2] = "Weapon", [3] = "Other", [4] = "Other" }

local function TextOrDefault(Value, Default)
    if Value == nil then return Default end
    local Text = tostring(Value)
    return Text:find("%S") and Text or Default
end

function HospitalShopData.BuildCatalog(Rows)
    local Candidates, IDCounts, Goods, Errors = {}, {}, {}, {}
    for RowName, Row in pairs(Rows or {}) do
        -- UGC表格的容器和行在游戏中是可遍历、可取字段的userdata。
        if type(Row) == "table" or type(Row) == "userdata" then
            local ID = tonumber(Row.CommodityID)
            local Tag = Rules.CopyTags(Row.Tag)
            if ID and ID > 0 and ID == math.floor(ID) then IDCounts[ID] = (IDCounts[ID] or 0) + 1 end
            if ID and ID > 0 and ID == math.floor(ID) and Rules.ValidTags(Row) then
                local ItemType = tonumber(Row.ItemType)
                local Price = tonumber(Row.Price)
                if not Rules.IsInteger(Price, 0) then Price = nil end
                local Limit = tonumber(Row.MaxCommodityCount) or 0
                local View = {
                    CommodityID = ID,
                    ItemID = Row.ItemID,
                    ItemNum = Row.ItemNum,
                    ItemType = ItemType,
                    Tag = Tag,
                    Name = TextOrDefault(Row.Name, "商品 " .. tostring(ID)),
                    CategoryName = CategoryNames[ItemType] or "其他",
                    CategoryKey = CategoryKeys[ItemType] or "Other",
                    Price = Price,
                    Icon = Row.Icon,
                    PreviewImage = Row.PreviewImage or Row.Icon,
                    Description = TextOrDefault(Row.Description, "暂无商品介绍"),
                    OriginalPrice = tonumber(Row.OriginalPrice) or 0,
                    IsSpecialOffer = Rules.HasTag(Row, 2),
                    PurchaseLimit = math.max(0, math.floor(Limit)),
                }
                Candidates[#Candidates + 1] = View
                if Price == nil then
                    Errors[#Errors + 1] = "商品 " .. tostring(ID) .. " 的价格无效"
                end
            else
                Errors[#Errors + 1] = "商品行 " .. tostring(RowName) .. " 的ID或Tag无效"
            end
        else
            Errors[#Errors + 1] = "商品行 " .. tostring(RowName) .. " 不是有效配置"
        end
    end
    for _, View in ipairs(Candidates) do
        if IDCounts[View.CommodityID] == 1 then
            Goods[#Goods + 1] = View
        end
    end
    for ID, Count in pairs(IDCounts) do
        if Count > 1 then Errors[#Errors + 1] = "商品ID " .. tostring(ID) .. " 重复，已跳过" end
    end
    table.sort(Goods, function(A, B)
        return A.CommodityID < B.CommodityID
    end)
    return Goods, Errors
end

-- 商品身份由本地目录提供贴图，交易字段以服务器本次特供快照为准。
function HospitalShopData.MergeOffer(Base, Offer)
    local Result = {}
    for K, V in pairs(Base or {}) do Result[K] = V end
    for K, V in pairs(Offer or {}) do Result[K] = V end
    Result.PurchaseLimit = Result.MaxCommodityCount or Result.PurchaseLimit or 0
    Result.CategoryName = CategoryNames[Result.ItemType] or "其他"
    Result.CategoryKey = CategoryKeys[Result.ItemType] or "Other"
    Result.Tag = Rules.CopyTags(Result.Tag)
    Result.IsSpecialOffer = Rules.HasTag(Result, 2)
    return Result
end

-- 先筛选，再分页；保留BuildCatalog确定的显示顺序。
function HospitalShopData.FilterCatalog(Catalog, Tag, CategoryKey)
    local Goods = {}
    for _, Data in ipairs(Catalog or {}) do
        if Rules.HasTag(Data, Tag) and (CategoryKey == nil or CategoryKey == "All" or Data.CategoryKey == CategoryKey) then
            Goods[#Goods + 1] = Data
        end
    end
    return Goods
end

function HospitalShopData.GetPage(Goods, RequestedPage, PageSize)
    Goods = Goods or {}
    PageSize = math.max(1, math.floor(tonumber(PageSize) or 6))
    local PageCount = math.ceil(#Goods / PageSize)
    if PageCount == 0 then return {}, 0, 0 end
    local Page = math.max(1, math.min(PageCount, math.floor(tonumber(RequestedPage) or 1)))
    local Items = {}
    local First = (Page - 1) * PageSize + 1
    for Index = First, math.min(First + PageSize - 1, #Goods) do
        Items[#Items + 1] = Goods[Index]
    end
    return Items, Page, PageCount
end

return HospitalShopData
