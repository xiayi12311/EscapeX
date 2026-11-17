-- 仅由服务器控制器调用；价格、次数和发货均不信任客户端。
local HospitalShopService = {}
local RandomShop = UGCGameSystem.UGCRequire("Script.utils.HospitalShopRandom")
local Delivery = UGCGameSystem.UGCRequire("Script.utils.HospitalShopDelivery")
local Stock = UGCGameSystem.UGCRequire("Script.Gameplay.ZombieDefense.DefenseShopStock")
local Team = UGCGameSystem.UGCRequire("Script.Gameplay.ZombieDefense.DefenseTeamPolicy")
local Catalog = UGCGameSystem.UGCRequire("Script.Gameplay.ZombieDefense.DefenseCatalog")

local function Valid(Object)
    return Object ~= nil and KismetSystemLibrary.IsValid(Object)
end

local function IsInteger(Value, Minimum)
    return type(Value) == "number" and Value == Value and Value < math.huge
        and Value >= Minimum and Value == math.floor(Value)
end

local function EnsureRound(PC)
    if PC.bHospitalShopBuying then return end
    PC.HospitalShopPlayerRecord = nil
    PC.HospitalShopTransactionFault = nil
    PC.HospitalCommodityBoughtCount = {}
    local Point = PC.DefenseShopPoint
    local GM = UGCGameSystem.GetGameMode()
    if not Valid(GM) or not Valid(Point) or not Point.Enabled then return end
    local Config = Catalog.Shops[Point.ShopConfigId]
    local Key = UGCGameSystem.GetPlayerKeyByPlayerController(PC)
    if not Config or type(Key) ~= "number" or Key < 0 or not UGCPlayerStateSystem.IsAlive(Key) then return end
    local Pawn = UGCGameSystem.GetPlayerPawnByPlayerController(PC)
    if not Valid(Pawn) or not Valid(Point.InteractionPoint) then return end
    local A = Point.InteractionPoint:K2_GetComponentLocation()
    local B = Pawn:K2_GetActorLocation()
    if (A.X-B.X)^2 + (A.Y-B.Y)^2 + (A.Z-B.Z)^2 > Config.Range^2 then return end

    local Owner, RoundID, Wave
    if Config.StandaloneLevel then
        if UGCGameSystem.GetCurrentLevel(Point, true) ~= Config.StandaloneLevel
            or UGCGameSystem.GetCurrentLevel(Pawn, true) ~= Config.StandaloneLevel then return end
        Owner, RoundID, Wave = GM, Config.StandaloneLevel .. ":SpawnShop", 1
    else
        local Service = GM.ZombieDefenseService
        if not Service or Service.Closed then return end
        local Encounter = Point.EncounterId
        local Run = Service.Runs[Encounter]
        if not Run or not Service.Registry:ValidateForStart(Encounter) then return end
        local State = Run.Session.State
        if Run.Error or Run.Session.Error or
            (State ~= "Preparing" and State ~= "Fighting" and State ~= "Resting") then return end
        local Registered = false
        for _, Actor in ipairs(Service.Registry:GetPoints(Encounter, "Shop") or {}) do
            if Actor == Point then Registered = true; break end
        end
        if not Registered or not Team.CanShop(GM, Encounter, Key) then return end
        Owner, RoundID, Wave = Run, Run.Session.InstanceId, math.max(1, Run.Session.WaveIndex)
    end

    Owner.ShopPlayers = Owner.ShopPlayers or {}
    local Record = Owner.ShopPlayers[Key]
    if not Record then
        Record = { BoughtCounts = {}, Funds = Config.StartingFunds }
        Owner.ShopPlayers[Key] = Record
    end
    PC.HospitalShopPlayerRecord = Record
    PC.HospitalShopTransactionFault = Record.Fault
    PC.HospitalCommodityBoughtCount = Record.BoughtCounts
    PC.HospitalShopLastRequestID = math.max(PC.HospitalShopLastRequestID or 0, Record.LastRequestID or 0)
    return { HospitalShopRoundID = RoundID, Day = Wave, Pawn = Pawn }
end

function HospitalShopService.Open(PC, Point)
    if PC.bHospitalShopBuying or not Valid(Point) then return end
    local World = UGCGameSystem.UGCRequire("Script.Gameplay.ZombieDefense.DefenseWorldPoints")
    local Class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(World.Classes.Shop))
    if not Class or not UE.IsA(Point, Class) then return end
    local Previous = PC.DefenseShopPoint
    PC.DefenseShopPoint = Point
    if EnsureRound(PC) then
        UnrealNetwork.CallUnrealRPC(PC, PC, "ClientOpenDefenseShop")
    else
        PC.DefenseShopPoint = Previous
        UnrealNetwork.CallUnrealRPC(PC, PC, "ClientDefenseShopDenied", Point)
    end
end

local function SetTransactionFault(PC, Fault)
    PC.HospitalShopTransactionFault = Fault
    PC.HospitalShopPlayerRecord.Fault = Fault
end

local function CopyCounts(Source)
    local Result = {}
    for ID, Count in pairs(Source or {}) do Result[tostring(ID)] = Count end
    return Result
end

local SnapshotFields = { "CommodityID", "ItemID", "ItemNum", "ItemType", "Tag", "Name", "Price",
    "MaxCommodityCount", "Description", "OriginalPrice" }

local function CaptureOffer(ID, Context)
    if Context.Offers[ID] ~= nil then return Context.Offers[ID] end
    local Row = Context.ByID[ID]
    if not Row or not RandomShop.IsPurchasable(Row) then return nil end
    local Data = {}
    for _, Field in ipairs(SnapshotFields) do Data[Field] = Row[Field] end
    Data.Tag = RandomShop.CopyTags(Row.Tag)
    local OK, Plan = pcall(Delivery.BuildPlan, Data, Context.Packages)
    if not OK then
        Context.Offers[ID] = false
        ugcprint("[HospitalShop] invalid delivery id=" .. tostring(ID) .. " error=" .. tostring(Plan))
        return nil
    end
    Data.DeliveryPlan = Plan
    Context.Offers[ID] = Data
    return Data
end

local function BuildOffers(Record, Pool, Previous, Context)
    local Lock = Record.RandomLock
    local IDs = RandomShop.Draw(Pool, Previous, nil, Lock and Lock.Data.CommodityID, Lock and Lock.Slot)
    local Offers = {}
    for Index, ID in ipairs(IDs) do
        local Data = Lock and Index == Lock.Slot and Delivery.Copy(Lock.Data) or (ID > 0 and CaptureOffer(ID, Context))
        Offers[Index] = Data or false
        if not Data then IDs[Index] = 0 end
    end
    return IDs, Offers
end

local function ReadEffectivePool(Day)
    local Context = Stock.Context()
    local Pool = RandomShop.BuildPool(Context.Rows, Day, Context.PoolRows)
    -- 不让无效发货配置进入可收费刷新的候选池。
    for Index = #Pool, 1, -1 do
        if not CaptureOffer(Pool[Index], Context) then
            for _, Report in ipairs(Pool.Report) do if Report.CommodityID == Pool[Index] then Report.Reason = "物品或礼包配置无效" end end
            table.remove(Pool, Index)
        end
    end
    return Pool, Context
end

local function EnsureDaily(PC, Manager)
    local Record = PC.HospitalShopPlayerRecord
    -- 准备期并入第一波，开波时无需重复刷新。
    local Day = math.max(1, math.floor(Manager.Day or 0))
    local Pool, Context = ReadEffectivePool(Day)
    local Daily = Record.RandomDaily
    if Daily and Daily.BoughtCounts then
        for ID, Count in pairs(Daily.BoughtCounts) do
            Record.BoughtCounts[ID] = math.max(Record.BoughtCounts[ID] or 0, Count)
        end
        Daily.BoughtCounts = nil
    end
    if not Daily or Daily.Day ~= Day then
        Record.RandomOfferSerial = (Record.RandomOfferSerial or 0) + 1
        local IDs, Offers = BuildOffers(Record, Pool, nil, Context)
        Daily = { Day = Day, IDs = IDs, Offers = Offers, RefreshUsed = 0,
            OfferVersion = Record.RandomOfferSerial }
        Record.RandomDaily = Daily
    else
        -- 兼容旧记录；次数统一存入整局字典，换夜绝不清空。
        if not Daily.Offers then
            Daily.IDs, Daily.Offers = BuildOffers(Record, Pool, Daily.IDs, Context)
            Record.RandomOfferSerial = (Record.RandomOfferSerial or 0) + 1
            Daily.OfferVersion = Record.RandomOfferSerial
        end
    end
    return Daily, Pool, Context
end

function HospitalShopService.SendState(PC)
    if PC.bHospitalShopBuying then return end
    local Manager = EnsureRound(PC)
    if PC.HospitalShopPlayerRecord and PC.HospitalShopPlayerRecord.bBusy then return end
    local RandomState = { Ready = false, CommodityIDs = {}, BoughtCounts = {},
        RefreshCost = RandomShop.RefreshCost, RefreshLimit = RandomShop.RefreshLimit, RefreshUsed = 0 }
    if Manager and Manager.HospitalShopRoundID and PC.HospitalShopPlayerRecord then
        local OK, Daily, Pool = pcall(EnsureDaily, PC, Manager)
        if OK then
            local IDs = {}
            for Index, ID in ipairs(Daily.IDs) do IDs[Index] = ID end
            local Offers = {}
            for Index, Data in ipairs(Daily.Offers) do
                local View = {}
                if Data then for _, Field in ipairs(SnapshotFields) do View[Field] = Data[Field] end end
                Offers[Index] = View
            end
            local Lock = PC.HospitalShopPlayerRecord.RandomLock
            RandomState = { Ready = true, Day = Daily.Day, CommodityIDs = IDs, Offers = Offers,
                BoughtCounts = CopyCounts(PC.HospitalCommodityBoughtCount), OfferVersion = Daily.OfferVersion,
                LockedCommodityID = Lock and Lock.Data.CommodityID or 0, LockedSlot = Lock and Lock.Slot or 0,
                RefreshCost = RandomShop.RefreshCost, RefreshLimit = RandomShop.RefreshLimit,
                RefreshUsed = Daily.RefreshUsed, CanReplace = RandomShop.CanReplace(Pool, Daily.IDs, Lock and Lock.Data.CommodityID) }
        else
            ugcprint("[HospitalShop] random state failed=" .. tostring(Daily))
        end
    end
    PC.HospitalShopRevision = (PC.HospitalShopRevision or 0) + 1
    local Snapshot = {
        RoundID = Manager and Manager.HospitalShopRoundID or "",
        GameDay = Manager and math.max(1, math.floor(Manager.Day or 0)) or 1,
        Revision = PC.HospitalShopRevision,
        Funds = PC.HospitalShopPlayerRecord and PC.HospitalShopPlayerRecord.Funds or 0,
        BoughtCounts = CopyCounts(PC.HospitalCommodityBoughtCount),
        RandomState = RandomState,
        LastProcessedID = PC.HospitalShopLastRequestID or 0,
        Ready = Manager ~= nil and Manager.HospitalShopRoundID ~= nil and PC.HospitalShopTransactionFault == nil,
        Fault = PC.HospitalShopTransactionFault ~= nil,
        Message = PC.DefenseShopMessage,
    }
    UnrealNetwork.CallUnrealRPC(PC, PC, "RPC_Client_HospitalShopState", Snapshot)
    PC.DefenseShopMessage = nil
end

local function ExecutePurchase(PC, Manager, ID, RoundID, Day, OfferVersion)
    if not Manager or not Manager.HospitalShopRoundID then return "商店暂不可用" end
    if RoundID ~= Manager.HospitalShopRoundID then return "本局信息已更新，请重新购买" end
    if PC.HospitalShopTransactionFault then return "发货状态异常，请检查服务器日志" end
    local Daily, _, Context = EnsureDaily(PC, Manager)
    local Data
    for Index, OfferID in ipairs(Daily.IDs) do if OfferID == ID then Data = Daily.Offers[Index] end end
    Data = Data or CaptureOffer(ID, Context)
    if not Data then return Context.ByID[ID] and "商品或发货配置无效，请检查商品表与礼包表" or "商品不存在" end
    if not RandomShop.ValidTags(Data) then return "商品不存在" end
    if not RandomShop.IsPurchasable(Data) then
        return "商品配置无效"
    end
    local Counts = PC.HospitalCommodityBoughtCount
    if not RandomShop.HasTag(Data, 0) and RandomShop.HasTag(Data, 1) then
        if Day ~= Daily.Day or OfferVersion ~= Daily.OfferVersion then return "特供商品已更新，请重新选择" end
        if not RandomShop.Contains(Daily.IDs, ID) then return "该商品不在当前特供中" end
    end
    local Bought = Counts[ID] or 0
    if Data.MaxCommodityCount > 0 and Bought >= Data.MaxCommodityCount then return "该商品已售罄" end
    local Record = PC.HospitalShopPlayerRecord
    if Record.Funds < Data.Price then return "资金不足" end

    local Valid, Plan = pcall(function() return Data.DeliveryPlan or Delivery.BuildPlan(Data, Context.Packages) end)
    if not Valid then
        ugcprint("[HospitalShop] invalid commodity id=" .. tostring(ID) .. " error=" .. tostring(Plan))
        return "商品发货配置无效，请检查物品类型与发货表"
    end
    local Before = Delivery.Snapshot(Manager.Pawn, Plan)
    local Transaction = { CommodityID = ID, Price = Data.Price, RequestID = PC.HospitalShopLastRequestID,
        DeliveryPlan = Delivery.Copy(Plan), Before = Before }
    Record.Funds = Record.Funds - Data.Price
    SetTransactionFault(PC, Transaction)
    local AddedOK, Added = pcall(Delivery.Give, Manager.Pawn, Plan)
    if AddedOK then
        Counts[ID] = Bought + 1
        local Lock = PC.HospitalShopPlayerRecord.RandomLock
        if Lock and Lock.Data.CommodityID == ID then PC.HospitalShopPlayerRecord.RandomLock = nil end
        SetTransactionFault(PC, nil)
        ugcprint(string.format("[HospitalShop] bought id=%d request=%d round=%s cost=%d count=%d",
            ID, PC.HospitalShopLastRequestID, RoundID, Data.Price, Bought + 1))
        return "购买成功：" .. tostring(Data.Name), true
    end

    local Restored, Error = pcall(Delivery.Rollback, Manager.Pawn, Before)
    if Restored then
        Record.Funds = Record.Funds + Data.Price
        SetTransactionFault(PC, nil)
        ugcprint("[HospitalShop] delivery failed and refunded id=" .. tostring(ID) .. " result=" .. tostring(Added))
        return "物品未完整发放，已退款，请检查背包空间或商品配置"
    end
    -- 原生接口异常且无法完整回滚时禁止继续交易，保留扣款和审计信息供排查。
    ugcprint("[HospitalShop] TRANSACTION_FAULT id=" .. tostring(ID) .. " rollback=" .. tostring(Error))
    return "发货状态异常，请检查服务器日志"
end

local function RunAction(PC, RequestID, Callback)
    if PC.bHospitalShopBuying then return end
    local Context = EnsureRound(PC)
    local Record = PC.HospitalShopPlayerRecord
    if not Record then
        PC.DefenseShopMessage = "商店暂不可用，请靠近商店后重试"
        HospitalShopService.SendState(PC)
        return
    end
    if Record.bBusy then return end
    if not IsInteger(RequestID, 1) or RequestID > 2147483647 then
        HospitalShopService.SendState(PC)
        return
    end
    if RequestID <= (PC.HospitalShopLastRequestID or 0) then
        HospitalShopService.SendState(PC)
        return
    end
    -- 请求序号跨局递增，重放旧包也不能在新一局再次发货。
    PC.HospitalShopLastRequestID = RequestID
    Record.LastRequestID, Record.bBusy = RequestID, true
    PC.bHospitalShopBuying = true
    local OK, Message = pcall(Callback, Context)
    PC.bHospitalShopBuying = false
    Record.bBusy = false
    if not OK then
        ugcprint("[HospitalShop] purchase error=" .. tostring(Message))
        Message = PC.HospitalShopTransactionFault and "发货状态异常，请检查服务器日志" or "商店操作失败，请稍后重试"
    end
    ugcprint("[HospitalShop] result request=" .. tostring(RequestID) .. " message=" .. tostring(Message))
    PC.DefenseShopMessage = Message
    HospitalShopService.SendState(PC)
end

function HospitalShopService.Buy(PC, ID, RequestID, RoundID, Day, OfferVersion)
    RunAction(PC, RequestID, function(Manager)
        if not IsInteger(ID, 1) then return "商品编号无效" end
        return ExecutePurchase(PC, Manager, ID, RoundID, Day, OfferVersion)
    end)
end

function HospitalShopService.Refresh(PC, RequestID, RoundID, Day, OfferVersion)
    RunAction(PC, RequestID, function(Manager)
        if not Manager or not Manager.HospitalShopRoundID then return "商店暂不可用" end
        if RoundID ~= Manager.HospitalShopRoundID then return "本局信息已更新" end
        if PC.HospitalShopTransactionFault then return "发货状态异常，请检查服务器日志" end
        local Daily, Pool, Context = EnsureDaily(PC, Manager)
        if Day ~= Daily.Day or OfferVersion ~= Daily.OfferVersion then return "特供商品已更新，请重试" end
        if RandomShop.RefreshLimit > 0 and Daily.RefreshUsed >= RandomShop.RefreshLimit then return "本波刷新次数已用完" end
        local Lock = PC.HospitalShopPlayerRecord.RandomLock
        if not RandomShop.CanReplace(Pool, Daily.IDs, Lock and Lock.Data.CommodityID) then return "暂无可替换的特供商品" end
        local Record = PC.HospitalShopPlayerRecord
        if Record.Funds < RandomShop.RefreshCost then return "资金不足" end
        local IDs, Offers = BuildOffers(PC.HospitalShopPlayerRecord, Pool, Daily.IDs, Context)
        if RandomShop.SameSet(IDs, Daily.IDs) then return "暂无可替换的特供商品" end
        Record.Funds = Record.Funds - RandomShop.RefreshCost
        SetTransactionFault(PC, { Action = "Refresh", Price = RandomShop.RefreshCost, RequestID = RequestID })
        Daily.IDs = IDs
        Daily.Offers = Offers
        Daily.RefreshUsed = Daily.RefreshUsed + 1
        PC.HospitalShopPlayerRecord.RandomOfferSerial = PC.HospitalShopPlayerRecord.RandomOfferSerial + 1
        Daily.OfferVersion = PC.HospitalShopPlayerRecord.RandomOfferSerial
        SetTransactionFault(PC, nil)
        ugcprint(string.format("[HospitalShop] refresh day=%d used=%d cost=%d", Daily.Day, Daily.RefreshUsed, RandomShop.RefreshCost))
        return "特供商品已刷新"
    end)
end

function HospitalShopService.Lock(PC, ID, RequestID, RoundID, Day, OfferVersion)
    RunAction(PC, RequestID, function(Manager)
        if not Manager or not Manager.HospitalShopRoundID then return "商店暂不可用" end
        if RoundID ~= Manager.HospitalShopRoundID then return "本局信息已更新" end
        if PC.HospitalShopTransactionFault then return "发货状态异常，请检查服务器日志" end
        if not IsInteger(ID, 1) then return "商品编号无效" end
        local Daily = EnsureDaily(PC, Manager)
        if Day ~= Daily.Day or OfferVersion ~= Daily.OfferVersion then return "特供商品已更新，请重试" end
        local Record, Slot = PC.HospitalShopPlayerRecord
        for Index, Value in ipairs(Daily.IDs) do if Value == ID then Slot = Index end end
        if not Slot then return "该商品不在当前特供中" end
        if Record.RandomLock and Record.RandomLock.Data.CommodityID == ID then
            Record.RandomLock = nil
        else
            if Record.RandomLock then return "最多锁定一件商品，请先解锁" end
            local Data = Daily.Offers[Slot]
            if Data.MaxCommodityCount > 0 and (Record.BoughtCounts[ID] or 0) >= Data.MaxCommodityCount then return "已售罄商品不能锁定" end
            Record.RandomLock = { Slot = Slot, Data = Delivery.Copy(Data) }
        end
        Record.RandomOfferSerial = Record.RandomOfferSerial + 1
        Daily.OfferVersion = Record.RandomOfferSerial
        return Record.RandomLock and "商品已锁定，跨波与刷新保留" or "商品已解锁"
    end)
end

return HospitalShopService
