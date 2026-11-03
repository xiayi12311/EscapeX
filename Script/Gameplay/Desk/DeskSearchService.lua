-- Engine adapter. Public entry points are server-only; no client RPC is exposed here.
local Manager=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskSearchManager')
local Config=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskOutcomeConfig')
local DeskClock=UGCGameSystem.UGCRequire('Script.Gameplay.Interaction.DeskClock')
local TeacherSpawner=UGCGameSystem.UGCRequire('Script.Gameplay.Desk.DeskTeacherSpawner')
local Service={}

local function valid(obj)
    return obj~=nil and KismetSystemLibrary.IsValid(obj)
end

local function log(text) ugcprint('[DeskSearch] '..text) end

local function clearReward(gm,actor)
    local pickup=gm.DeskRewardActors and gm.DeskRewardActors[actor]
    if valid(pickup) then pickup:K2_DestroyActor() end
    if gm.DeskRewardActors then gm.DeskRewardActors[actor]=nil end
end

local function cancelEffect(gm,actor)
    local timer=gm.DeskEffectTimers and gm.DeskEffectTimers[actor]
    if timer then UGCTimerUtility.RemoveLuaTimer(timer); gm.DeskEffectTimers[actor]=nil end
    clearReward(gm,actor)
end

local function spawnReward(gm,actor,outcome)
    if outcome.ItemId==nil then return end
    local drawer=actor.Drawer
    if not valid(drawer) then
        log('ERROR: cannot spawn fixed reward without drawer desk='..tostring(actor.DeskState and actor.DeskState.DeskId))
        return
    end
    -- Spawn in the opened drawer. The pickup wrapper is a replicated world actor,
    -- so late joiners see the same reward without replaying the desk animation.
    local location=UGCMathUtility.TransformLocation(
        drawer:K2_GetComponentToWorld(),Vector.New(0,-18.8,62))
    local pickup=UGCItemSystemV2.SpawnPickupWrapper(
        location,outcome.ItemId,outcome.PickupCount or 1)
    if valid(pickup) then
        gm.DeskRewardActors[actor]=pickup
        log('Spawned fixed reward item='..tostring(outcome.ItemId)..' desk='..tostring(actor.DeskState and actor.DeskState.DeskId))
    else
        log('ERROR: SpawnPickupWrapper failed item='..tostring(outcome.ItemId))
    end
end

local function scheduleEffects(gm,actor,data)
    local outcome=Config.Outcomes[data.FinalOutcomeId]
    if not outcome then return end
    local hasEffects=outcome.Effects and #outcome.Effects>0
    if not hasEffects and outcome.ItemId==nil then return end
    cancelEffect(gm,actor)
    gm.DeskEffectTimers[actor]=UGCTimerUtility.CreateLuaTimer(data.RevealOffset or 0.8,function()
        if not valid(gm) or not gm.DeskSearchManager or not valid(actor) then return end
        gm.DeskEffectTimers[actor]=nil
        local current=gm.DeskSearchManager:GetSnapshot(data.DeskId)
        if not current or current.ResetVersion~=data.ResetVersion or current.OpenEventId~=data.OpenEventId then return end
        spawnReward(gm,actor,outcome)
        for _,effect in ipairs(outcome.Effects or {}) do
            -- Text feedback is the initial UI/broadcast implementation; audio resources remain configurable work.
            local recipients={}
            if effect.Audience=='All' then recipients=UGCGameSystem.GetAllPlayerController(false)
            else
                local pc=UGCGameSystem.GetPlayerControllerByPlayerKey(data.SearcherPlayerId)
                if valid(pc) then recipients={pc} end
            end
            if effect.Text then
                for _,pc in pairs(recipients) do
                    if valid(pc) then UGCWidgetManagerSystem.ShowTipsUIByServer(effect.Text,pc) end
                end
            end
        end
        log('Revealed event='..tostring(data.OpenEventId)..' outcome='..tostring(data.FinalOutcomeId))
    end,false)
end

local function validate(actor,key,radius)
    if not valid(actor) then return false,'DESK_DESTROYED' end
    local pc=UGCGameSystem.GetPlayerControllerByPlayerKey(key)
    local pawn=UGCGameSystem.GetPlayerPawnByPlayerKey(key)
    if not valid(pc) or not valid(pawn) then return false,'PLAYER_UNAVAILABLE' end
    if not UGCPlayerStateSystem.IsAlive(key) or UGCPlayerStateSystem.IsExit(key) then
        return false,'PLAYER_DEAD_OR_EXITED'
    end
    if actor.DeskRequireStanding and pawn.PoseState~=ESTEPoseState.Stand
        and pawn.PoseState~=ESTEPoseState.Sprint then return false,'NOT_STANDING' end
    if not valid(actor.SearchArea) then return false,'MISSING_SEARCH_AREA' end
    local point=actor.SearchArea:K2_GetComponentLocation()
    local pos=pawn:K2_GetActorLocation()
    local x,y,z=pos.X-point.X,pos.Y-point.Y,pos.Z-point.Z
    local areaRadius=actor.SearchArea:GetScaledSphereRadius()
    if x*x+y*y+z*z>math.min(radius,areaRadius)^2 then return false,'TOO_FAR' end
    return true
end

local function itemExists(itemId)
    local wrappers=UGCItemSystemV2.GetPickupWrapperListByItemID(itemId,true)
    if wrappers and #wrappers>0 then return true end
    for _,pawn in ipairs(UGCGameSystem.GetAllPlayerPawn() or {}) do
        local count=UGCBackPackSystem.GetItemCount(pawn,itemId)
        if type(count)=='number' and count>0 then return true end
    end
    return false
end

local function removeTaggedActors(gm, config)
    if not config or type(config.Tag)~='string' or config.Tag=='' then
        log('ERROR: tagged actor removal is missing a tag')
        return 0
    end
    local actors=UGCActorComponentUtility.GetAllActorsWithTag(gm,config.Tag) or {}
    local matched,removed=0,0
    for _,actor in pairs(actors) do
        matched=matched+1
        if valid(actor) then
            actor:K2_DestroyActor()
            removed=removed+1
        end
    end
    if config.ExpectedCount and matched~=config.ExpectedCount then
        log(string.format('WARNING: tagged actor removal tag=%s expected=%d matched=%d',
            config.Tag,config.ExpectedCount,matched))
    end
    log(string.format('Removed tagged actors tag=%s matched=%d removed=%d',
        config.Tag,matched,removed))
    return removed
end

function Service.Get(gm)
    if not valid(gm) or not gm:HasAuthority() then return nil,'SERVER_ONLY' end
    return gm.DeskSearchManager
end

function Service.Setup(gm)
    if not gm:HasAuthority() or gm.DeskSearchManager then return end
    gm.DeskEffectTimers={}
    gm.DeskRewardActors={}
    gm.DeskSearchManager=Manager.new({
        now=function() return DeskClock.ServerNow(gm) end,
        roll=function(pool) return Config.Roll(pool) end,
        validate=validate,
        itemExists=itemExists,
        log=log,
        emit=function(actor,data,kind,reason)
            if valid(actor) then
                -- Replace the whole table; consumers register this one atomic replication field.
                actor.DeskState=data
                if actor.OnDeskServerState then actor:OnDeskServerState(data,kind,reason) end
            end
            if kind=='Reset' or kind=='Removed' then cancelEffect(gm,actor)
            elseif kind=='Opened' then
                TeacherSpawner.OnCompleted(gm,data.CompletedSearchCount)
                local action=Config.CountTriggers and Config.CountTriggers[data.CompletedSearchCount]
                if action=='EnableSecondRoute' then
                    TeacherSpawner.OnRouteMilestone(gm)
                elseif action and Config.TaggedActorRemovals
                    and Config.TaggedActorRemovals[action] then
                    removeTaggedActors(gm,Config.TaggedActorRemovals[action])
                elseif action then
                    log('Unknown count trigger '..tostring(action))
                end
                scheduleEffects(gm,actor,data)
            end
            log(string.format('desk=%s version=%s interaction=%s state=%s event=%s reason=%s count=%d epoch=%d',
                tostring(data.DeskId),tostring(data.ResetVersion),tostring(data.InteractionId),
                tostring(data.State),kind,tostring(reason),gm.DeskSearchManager:GetOpenedCount(),
                gm.DeskSearchManager.CounterEpoch))
        end,
    },Config)
    gm.DeskSearchTimer=UGCTimerUtility.CreateLuaTimer(0.1,function()
        if not valid(gm) or not gm.DeskSearchManager then return end
        gm.DeskSearchManager:Update()
    end,true,'EscapeX.DeskSearch.Update')
    log('Server service initialized')
end

function Service.Shutdown(gm)
    for _,timer in pairs(gm.DeskEffectTimers or {}) do UGCTimerUtility.RemoveLuaTimer(timer) end
    gm.DeskEffectTimers={}
    for actor in pairs(gm.DeskRewardActors or {}) do clearReward(gm,actor) end
    gm.DeskRewardActors={}
    if gm.DeskSearchTimer then
        UGCTimerUtility.RemoveLuaTimer(gm.DeskSearchTimer)
        gm.DeskSearchTimer=nil
    end
    gm.DeskSearchManager=nil
end

function Service.Register(gm,actor,id,options)
    local m,reason=Service.Get(gm)
    if not m then return false,reason or 'SERVICE_NOT_READY' end
    if not valid(actor) then return false,'INVALID_DESK' end
    local ok,detail=m:Register(actor,id,options)
    m:FlushEvents()
    return ok,detail
end

function Service.StartSearch(gm,actor,pc)
    local m,reason=Service.Get(gm)
    if not m then return false,reason or 'SERVICE_NOT_READY' end
    if not valid(pc) then return false,'INVALID_PLAYER' end
    local d=m:FindActor(actor)
    if not d then return false,'UNKNOWN_DESK' end
    local key=UGCGameSystem.GetPlayerKeyByPlayerController(pc)
    if key==nil or key<0 then return false,'INVALID_PLAYER_KEY' end
    local ok,detail,version=m:StartSearch(d.id,key)
    m:FlushEvents()
    return ok,detail,version
end

function Service.GetOpenedCount(gm)
    local m,reason=Service.Get(gm)
    if not m then return nil,reason or 'SERVICE_NOT_READY' end
    return m:GetOpenedCount()
end

function Service.CancelPlayer(gm,pc,reason)
    local m,detail=Service.Get(gm)
    if not m then return false,detail or 'SERVICE_NOT_READY' end
    if not valid(pc) then return false,'INVALID_PLAYER' end
    local key=UGCGameSystem.GetPlayerKeyByPlayerController(pc)
    local id=m.players[key]
    if not id then return true end
    local d=m.desks[id]
    if not d then return false,'UNKNOWN_DESK' end
    local ok,result=m:CancelSearch(id,d.version,d.interaction,reason or 'PLAYER_CANCELLED')
    m:FlushEvents()
    return ok,result
end

function Service.ResetOpenedCount(gm)
    local m,reason=Service.Get(gm)
    if not m then return false,reason or 'SERVICE_NOT_READY' end
    local ok=m:ResetOpenedCount()
    log('Count reset epoch='..m.CounterEpoch)
    return ok
end

function Service.ResetDesk(gm,actor)
    local m,reason=Service.Get(gm)
    if not m then return false,reason or 'SERVICE_NOT_READY' end
    local ok,detail=m:ResetDesk(actor)
    m:FlushEvents()
    return ok,detail
end

function Service.ResetAllDesks(gm)
    local m,reason=Service.Get(gm)
    if not m then return false,reason or 'SERVICE_NOT_READY' end
    local ok,detail=m:ResetAllDesks()
    m:FlushEvents()
    return ok,detail
end

function Service.Unregister(gm,actor)
    local m,reason=Service.Get(gm)
    if not m then return false,reason or 'SERVICE_NOT_READY' end
    local ok,detail=m:Unregister(actor)
    m:FlushEvents()
    return ok,detail
end

return Service
