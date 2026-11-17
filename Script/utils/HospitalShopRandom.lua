-- 无引擎依赖。权重为非负整数；已购记录不参与抽取。
local RandomShop = { PageSize = 3, RefreshCost = 100, RefreshLimit = 3 }
RandomShop.PackageType = 4

function RandomShop.CopyTags(Tags)
    local Result, Seen = {}, {}
    if type(Tags) ~= "table" and type(Tags) ~= "userdata" then return Result end
    for _, Tag in pairs(Tags) do
        if not Seen[Tag] then Result[#Result + 1] = Tag; Seen[Tag] = true end
    end
    return Result
end

function RandomShop.HasTag(Data, Wanted)
    for _, Tag in ipairs(RandomShop.CopyTags(Data and Data.Tag)) do if Tag == Wanted then return true end end
    return false
end

function RandomShop.ValidTags(Data)
    local Shop = false
    for _, Tag in ipairs(RandomShop.CopyTags(Data and Data.Tag)) do
        if Tag ~= 0 and Tag ~= 1 and Tag ~= 2 then return false end
        if Tag == 0 or Tag == 1 then Shop = true end
    end
    return Shop
end

function RandomShop.IsInteger(Value, Minimum)
    return type(Value) == "number" and Value == Value and Value < math.huge
        and Value >= Minimum and Value == math.floor(Value)
end

function RandomShop.IsPurchasable(Row)
    return RandomShop.IsInteger(Row.CommodityID, 1) and RandomShop.IsInteger(Row.Price, 0)
        and RandomShop.IsInteger(Row.MaxCommodityCount, 0)
        and RandomShop.IsInteger(Row.ItemID, 1) and RandomShop.IsInteger(Row.ItemNum, 1)
        and RandomShop.ValidTags(Row)
end

-- 开放条件仅来自独立池表；先过滤，后求有效权重，不读取商品表上的旧列。
function RandomShop.BuildPool(Rows, Day, PoolRows)
    local Counts, ByID, Pool = {}, {}, { Weights = {}, Report = {} }
    for _, Row in pairs(Rows or {}) do
        local ID = Row.CommodityID
        if RandomShop.IsInteger(ID, 1) then Counts[ID] = (Counts[ID] or 0) + 1; ByID[ID] = Row end
    end
    local PoolCounts = {}
    for _, Entry in pairs(PoolRows or {}) do
        local ID = Entry.CommodityID
        if RandomShop.IsInteger(ID, 1) then PoolCounts[ID] = (PoolCounts[ID] or 0) + 1 end
    end
    for _, Entry in pairs(PoolRows or {}) do
        local ID, Weight, Night = Entry.CommodityID, Entry.Weight, Entry.UnlockNight
        local Row, Reason = ByID[ID]
        if not RandomShop.IsInteger(ID, 1) then Reason = "商品ID无效"
        elseif PoolCounts[ID] ~= 1 then Reason = "池内商品ID重复"
        elseif not Row or Counts[ID] ~= 1 then Reason = "商品不存在或ID重复"
        elseif not RandomShop.IsPurchasable(Row) or not RandomShop.HasTag(Row, 1) then Reason = "不是有效随机商品"
        elseif not RandomShop.IsInteger(Weight, 0) then Reason = "权重无效"
        elseif Weight == 0 then Reason = "权重为0"
        elseif not RandomShop.IsInteger(Night, 1) then Reason = "开放夜数无效"
        elseif Night > (Day or 1) then Reason = "尚未开放" end
        Pool.Report[#Pool.Report + 1] = { CommodityID = ID, Name = Row and Row.Name or tostring(ID), Weight = Weight,
            UnlockNight = Night, Reason = Reason }
        if not Reason then
            Pool[#Pool + 1] = ID
            Pool.Weights[ID] = Weight
        end
    end
    table.sort(Pool)
    return Pool
end

function RandomShop.Contains(IDs, ID)
    for _, Value in ipairs(IDs or {}) do if Value == ID then return true end end
    return false
end

function RandomShop.SameSet(A, B)
    if #A ~= #B then return false end
    for _, ID in ipairs(A) do if not RandomShop.Contains(B, ID) then return false end end
    return true
end

function RandomShop.CanReplace(Pool, IDs, LockedID)
    for _, ID in ipairs(Pool) do
        if ID ~= LockedID and not RandomShop.Contains(IDs, ID) then return true end
    end
    return false
end

local function Pick(Candidates, Weights, RNG)
    local Total = 0
    for _, ID in ipairs(Candidates) do Total = Total + (Weights[ID] or 1) end
    local Value = (RNG or math.random)(Total)
    for Index, ID in ipairs(Candidates) do
        Value = Value - (Weights[ID] or 1)
        if Value <= 0 then
            table.remove(Candidates, Index)
            return ID
        end
    end
    error("weighted draw failed")
end

function RandomShop.Draw(Pool, Previous, RNG, LockedID, LockedSlot)
    local Candidates, IDs, Weights = {}, {}, Pool.Weights or {}
    for _, ID in ipairs(Pool) do if ID ~= LockedID then Candidates[#Candidates + 1] = ID end end
    local Size = math.min(RandomShop.PageSize, #Candidates + (LockedID and 1 or 0))
    if LockedID then Size = math.max(Size, LockedSlot) end
    for Index = 1, Size do
        if LockedID and Index == LockedSlot then IDs[Index] = LockedID
        else IDs[Index] = #Candidates > 0 and Pick(Candidates, Weights, RNG) or 0 end
    end
    -- 付费刷新必须至少更换一件未锁商品，重排不算换货。
    if Previous and RandomShop.SameSet(IDs, Previous) then
        local Alternatives = {}
        for _, ID in ipairs(Pool) do
            if ID ~= LockedID and not RandomShop.Contains(Previous, ID) then Alternatives[#Alternatives + 1] = ID end
        end
        local Slots = {}
        for Index = 1, #IDs do if Index ~= LockedSlot then Slots[#Slots + 1] = Index end end
        if #Alternatives > 0 and #Slots > 0 then
            IDs[Slots[(RNG or math.random)(#Slots)]] = Pick(Alternatives, Weights, RNG)
        end
    end
    return IDs
end

return RandomShop
