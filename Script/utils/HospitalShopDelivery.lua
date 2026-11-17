-- 先校验/快照全部发货内容，失败恢复全部，成功后才记一次购买。
local Delivery = {}
local Rules = UGCGameSystem.UGCRequire("Script.utils.HospitalShopRandom")

function Delivery.Copy(Value)
    if type(Value) ~= "table" then return Value end
    local Result = {}
    for Key, Entry in pairs(Value) do Result[Key] = Delivery.Copy(Entry) end
    return Result
end

-- 同一PackageID可有多行；只索引一次，内容引用真实物品，不反查商品表。
function Delivery.IndexPackages(Rows)
    local Index = {}
    for _, Row in pairs(Rows or {}) do
        if Rules.IsInteger(Row.PackageID, 1) then
            local Group = Index[Row.PackageID] or { Items = {} }
            Index[Row.PackageID] = Group
            if not Rules.IsInteger(Row.ItemID, 1) or not Rules.IsInteger(Row.ItemNum, 1) then
                Group.Error = "invalid package item or quantity"
            else Group.Items[#Group.Items + 1] = { ItemID = Row.ItemID, ItemNum = Row.ItemNum } end
        end
    end
    for _, Group in pairs(Index) do table.sort(Group.Items, function(A, B) return A.ItemID < B.ItemID end) end
    return Index
end

function Delivery.BuildPlan(Data, PackageIndex)
    local Items = {}
    assert(Rules.IsInteger(Data.ItemID, 1) and Rules.IsInteger(Data.ItemNum, 1), "invalid item ID or quantity")
    if Data.ItemType == Rules.PackageType then
        PackageIndex = PackageIndex or {}
        local Group = PackageIndex[Data.ItemID]
        assert(Group and not Group.Error and #Group.Items > 0, "package missing, empty or invalid")
        for _, Item in ipairs(Group.Items) do
            local Count = Item.ItemNum * Data.ItemNum
            assert(Rules.IsInteger(Count, 1) and Count <= 2147483647, "package quantity out of range")
            Items[#Items + 1] = { ItemID = Item.ItemID, ItemNum = Count }
        end
    else
        Items[1] = { ItemID = Data.ItemID, ItemNum = Data.ItemNum }
    end
    return Items
end

local function Inventory(Pawn, ItemID)
    local Result = {}
    local Items = assert(UGCBackPackSystem.GetAllItemData(Pawn), "native backpack unavailable")
    for _, Item in pairs(Items) do
        if Item.ItemID == ItemID then
            assert(Item.InstanceID and Item.InstanceID ~= 0 and Rules.IsInteger(Item.Count, 1),
                "invalid native item instance")
            Result[Item.InstanceID] = Item.Count
        end
    end
    return Result
end

function Delivery.Snapshot(Pawn, Plan)
    assert(UGCBackPackSystem.GetBackpackComponent(Pawn), "native backpack unavailable")
    local Before = {}
    for _, Item in ipairs(Plan) do
        if not Before[Item.ItemID] then Before[Item.ItemID] = Inventory(Pawn, Item.ItemID) end
    end
    return Before
end

function Delivery.Give(Pawn, Plan)
    for _, Item in ipairs(Plan) do
        local Count = UGCBackPackSystem.GetItemCount(Pawn, Item.ItemID)
        local Added = UGCBackPackSystem.AddItem(Pawn, Item.ItemID, Item.ItemNum)
        assert(Added and UGCBackPackSystem.GetItemCount(Pawn, Item.ItemID) == Count + Item.ItemNum,
            "native delivery incomplete: " .. tostring(Item.ItemID))
    end
end

function Delivery.Rollback(Pawn, Before)
    local Restored = true
    for ItemID, Original in pairs(Before) do
        for InstanceID, Count in pairs(Inventory(Pawn, ItemID)) do
            local Added = Count - (Original[InstanceID] or 0)
            if Added > 0 and not UGCBackPackSystem.DropItemByInstanceID(Pawn, InstanceID, Added, true) then
                Restored = false
            end
        end
        local Current = Inventory(Pawn, ItemID)
        for InstanceID, Count in pairs(Original) do
            if Current[InstanceID] ~= Count then Restored = false end
        end
        for InstanceID, Count in pairs(Current) do
            if Original[InstanceID] ~= Count then Restored = false end
        end
    end
    assert(Restored, "native inventory rollback incomplete")
end

return Delivery
