-- Server-owned state machine. Engine access is injected and callbacks run after commit.
local Manager = {}
Manager.__index = Manager

function Manager.new(deps, config)
    assert(deps.now and deps.validate and deps.roll, 'missing desk dependencies')
    return setmetatable({deps=deps, config=config or {}, desks={}, players={},
        TotalOpenedCount=0, CounterEpoch=1, serial=0, events={}}, Manager)
end

local function snapshot(d)
    return {DeskId=d.id, ResetVersion=d.version, InteractionId=d.interaction, Revision=d.revision,
        State=d.state, SearchingPlayerId=d.player, SearchStartTime=d.startTime,
        SearchEndTime=d.endTime, FinalOutcomeId=d.outcome, OpenEventId=d.event,
        OpenStartTime=d.openTime, OpenDuration=d.openDuration, RevealOffset=d.revealOffset,
        CounterEpoch=d.epoch, SearcherPlayerId=d.searcher}
end

function Manager:publish(d, kind, reason)
    d.revision=(d.revision or 0)+1
    self.events[#self.events+1] = {actor=d.actor, data=snapshot(d), kind=kind, reason=reason}
end

-- Detach queue before dispatch: callbacks may reset/start other sessions safely.
function Manager:FlushEvents()
    local events=self.events
    self.events={}
    if not self.deps.emit then return end
    for _,e in ipairs(events) do
        local ok,err=pcall(self.deps.emit,e.actor,e.data,e.kind,e.reason)
        if not ok and self.deps.log then self.deps.log(tostring(err)) end
    end
end

function Manager:Register(actor,id,options)
    if actor==nil or id==nil or id=='' then return false,'INVALID_DESK' end
    if self.desks[id] then return false,'DUPLICATE_DESK_ID' end
    local opt=options or {}
    local duration=opt.SearchDuration or 3
    local radius=opt.InteractRadius or 180
    local cancel=opt.CancelRadius or 220
    local openDuration=opt.OpenDuration or 1
    local reveal=opt.RevealOffset or math.min(0.8,openDuration)
    if duration<=0 or radius<=0 or cancel<radius or openDuration<0 or reveal<0 or reveal>openDuration then
        return false,'INVALID_CONFIG'
    end
    local candidate=self.deps.roll(opt.OutcomePoolId)
    if not candidate then return false,'EMPTY_OUTCOME_POOL' end
    local d={actor=actor,id=id,version=1,interaction=0,state='Closed',
        duration=duration,radius=radius,cancelRadius=cancel,openDuration=openDuration,revealOffset=reveal,
        pool=opt.OutcomePoolId,candidate=candidate}
    self.desks[id]=d
    self:publish(d,'Registered')
    return true
end

function Manager:FindActor(actor)
    for _,d in pairs(self.desks) do if d.actor==actor then return d end end
end

function Manager:release(d)
    if d.player~=nil and self.players[d.player]==d.id then self.players[d.player]=nil end
    d.player=nil; d.startTime=nil; d.endTime=nil
end

function Manager:StartSearch(id,player)
    local d=self.desks[id]
    if not d then return false,'UNKNOWN_DESK' end
    if player==nil then return false,'INVALID_PLAYER' end
    if d.state~='Closed' then return false,'DESK_BUSY_OR_OPEN' end
    if self.players[player] then return false,'PLAYER_BUSY' end
    local valid,reason=self.deps.validate(d.actor,player,d.radius)
    if not valid then return false,reason or 'INVALID_PLAYER_OR_DISTANCE' end
    self.serial=self.serial+1
    d.interaction=self.serial; d.player=player
    d.startTime=self.deps.now(); d.endTime=d.startTime+d.duration
    d.state='Searching'; self.players[player]=id
    self:publish(d,'SearchStarted')
    return true,d.interaction,d.version
end

function Manager:CancelSearch(id,version,interaction,reason)
    local d=self.desks[id]
    if not d or d.state~='Searching' or d.version~=version or d.interaction~=interaction then
        return false,'STALE_SESSION'
    end
    self:release(d); d.state='Closed'
    self:publish(d,'SearchCancelled',reason)
    return true
end

function Manager:CompleteSearch(id,version,interaction)
    local d=self.desks[id]
    if not d or d.state~='Searching' or d.version~=version or d.interaction~=interaction then
        return false,'STALE_SESSION'
    end
    local valid,reason=self.deps.validate(d.actor,d.player,d.cancelRadius)
    if not valid then
        self:CancelSearch(id,version,interaction,reason)
        return false,reason or 'INVALID_PLAYER_OR_DISTANCE'
    end
    local now=self.deps.now()
    if now<d.endTime then return false,'TOO_EARLY' end
    local nextCount=self.TotalOpenedCount+1
    local fixed=self.config.FixedSearchOutcomes or {}
    d.outcome=fixed[nextCount] or d.candidate
    d.event=tostring(d.id)..':'..d.version..':'..d.interaction
    d.searcher=d.player
    d.epoch=self.CounterEpoch; d.openTime=now
    d.state='Opening'; self.TotalOpenedCount=nextCount
    self:release(d)
    self:publish(d,'Opened')
    return true,d.outcome,nextCount
end

function Manager:Update()
    local now=self.deps.now()
    for id,d in pairs(self.desks) do
        if d.state=='Searching' then
            local valid,reason=self.deps.validate(d.actor,d.player,d.cancelRadius)
            if not valid then self:CancelSearch(id,d.version,d.interaction,reason)
            elseif now>=d.endTime then self:CompleteSearch(id,d.version,d.interaction) end
        elseif d.state=='Opening' and now>=d.openTime+d.openDuration then
            d.state='Opened'; self:publish(d,'Settled')
        end
    end
    self:FlushEvents()
end

function Manager:GetOpenedCount() return self.TotalOpenedCount end
function Manager:GetSnapshot(id)
    local d=self.desks[id]
    if d then return snapshot(d) end
end

function Manager:ResetOpenedCount()
    self.TotalOpenedCount=0; self.CounterEpoch=self.CounterEpoch+1
    return true
end

function Manager:ResetDesk(actor)
    local d=self:FindActor(actor)
    if not d then return false,'UNKNOWN_DESK' end
    -- Resolve random data before mutation; an invalid pool must not half-reset a desk.
    local candidate=self.deps.roll(d.pool)
    if not candidate then return false,'EMPTY_OUTCOME_POOL' end
    self:release(d); d.version=d.version+1; d.state='Closed'
    d.candidate=candidate; d.outcome=nil; d.event=nil; d.openTime=nil; d.epoch=nil; d.searcher=nil
    self:publish(d,'Reset')
    return true
end

function Manager:ResetAllDesks()
    local failed={}
    for _,d in pairs(self.desks) do
        local ok,reason=self:ResetDesk(d.actor)
        if not ok then failed[#failed+1]={DeskId=d.id,Reason=reason} end
    end
    return #failed==0,failed
end

function Manager:Unregister(actor)
    local d=self:FindActor(actor)
    if not d then return false,'UNKNOWN_DESK' end
    self:release(d); d.version=d.version+1; d.state='Closed'
    self.desks[d.id]=nil; self:publish(d,'Removed')
    return true
end

return Manager
