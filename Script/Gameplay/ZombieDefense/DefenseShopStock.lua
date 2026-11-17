-- 商品从数据表读取，仅接受引擎识别的物资。
local Delivery = UGCGameSystem.UGCRequire('Script.utils.HospitalShopDelivery')
local Rules = UGCGameSystem.UGCRequire('Script.utils.HospitalShopRandom')
local M = {}
local TableRoot = 'Data/Table/Customized/'

local function ReadTable(Name)
    local OK, Rows = pcall(UGCGameSystem.GetTableData, TableRoot .. Name)
    if OK and Rows then return Rows end
    ugcprint("[DefenseShop] Could not read " .. TableRoot .. Name .. ": " .. tostring(Rows))
    return {}
end

local function IsSellable(Row, Packages)
    if not Rules.IsPurchasable(Row) or (Row.ItemType ~= 1 and Row.ItemType ~= 2 and Row.ItemType ~= 4) then
        return false
    end
    local OK, Plan = pcall(Delivery.BuildPlan, Row, Packages)
    if not OK then return false end
    for _, Item in ipairs(Plan) do
        if not UGCItemSystem.GetItemData(Item.ItemID) then
            return false
        end
    end
    return true
end

function M.Context()
    local Packages = Delivery.IndexPackages(ReadTable('YX_ShopDeliveryTable'))
    local Rows, ByID, Seen = {}, {}, {}
    for _, Row in pairs(ReadTable('YX_CommodityTable')) do
        local ID = Row.CommodityID
        if Rules.IsInteger(ID, 1) then
            if Seen[ID] then
                ByID[ID] = nil
            elseif IsSellable(Row, Packages) then
                ByID[ID] = Row
            end
            Seen[ID] = true
        end
    end
    for _, Row in pairs(ByID) do Rows[#Rows + 1] = Row end
    return {Rows = Rows, ByID = ByID, Offers = {}, Packages = Packages,
        PoolRows = ReadTable('YX_ShopRandomPoolTable')}
end

function M.Rows()
    return M.Context().Rows
end

return M
