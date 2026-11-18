local M = {}

local function distance(a, b)
    return (a.X - b.X)^2 + (a.Y - b.Y)^2
end

local function positive(value)
    return type(value) == 'number' and value > 0 and value < math.huge
end

function M.Prepare(actor, geometry, config)
    local start = geometry.Outside
    local landing = actor.InsideLanding:K2_GetComponentLocation()
    local dx, dy = start.X-landing.X, start.Y-landing.Y
    local length = math.sqrt(dx*dx + dy*dy)
    if not (length > 0 and type(config.WaitOffsets) == 'table' and #config.WaitOffsets > 0
        and positive(config.Clearance) and positive(config.StopRadius)
        and positive(config.StallSeconds) and positive(config.RetrySeconds)
        and positive(config.ProgressDistance) and positive(config.VerticalClearance)
        and positive(config.ProjectionTolerance)) then return nil, 'INVALID_CONFIG' end
    local function project(offset)
        if type(offset) ~= 'number' or not positive(math.abs(offset)) then return nil end
        local candidate = {X=start.X-dy/length*offset, Y=start.Y+dx/length*offset, Z=start.Z}
        local range = config.ProjectionTolerance
        local ok, ground = UGCNavigationSystem.ProjectPointToNavigation(actor, candidate,
            {X=range,Y=range,Z=range})
        if not ok or not geometry.Exterior(ground) or distance(candidate,ground) > range^2
            or math.abs(ground.Z-start.Z) > range then return nil end
        return ground
    end
    local retreat = project(config.RetreatOffset)
    if not retreat then return nil, 'RETREAT_OFF_NAVIGATION' end
    if distance(start,retreat) < config.Clearance^2 then return nil, 'RETREAT_TOO_CLOSE' end
    local queue = {Id=actor.PointId, Actor=actor, Geometry=geometry, Start=start, Landing=landing,
        Retreat=retreat, Config=config, Slots={}, Ticket=0}
    for index, offset in ipairs(config.WaitOffsets) do
        local goal = project(offset)
        local name = 'WAIT_' .. index
        if not goal then return nil, name .. '_OFF_NAVIGATION' end
        if distance(goal,start) < config.Clearance^2
            or distance(goal,retreat) < config.Clearance^2 then return nil, name .. '_TOO_CLOSE' end
        for _, slot in ipairs(queue.Slots) do
            if distance(goal,slot.Goal) < config.Clearance^2 then return nil, name .. '_TOO_CLOSE' end
        end
        queue.Slots[#queue.Slots+1] = {Goal=goal}
    end
    return queue
end

local function clear(queue, point, exclude, positions)
    for actor, position in pairs(positions) do
        if actor ~= exclude and math.abs(position.Z-point.Z) <= queue.Config.VerticalClearance
            and distance(point, position) < queue.Config.Clearance^2 then return false end
    end
    return true
end

local function release(member, now, retry)
    local queue, binding = member.Queue, member.Binding
    if member.Slot then member.Slot.Member = nil end
    if queue.Lead == member then queue.Lead = nil end
    binding.QueueMember, binding.RepathAt = nil, nil
    if retry then binding.QueueRetry = {Queue=queue, Until=now+queue.Config.RetrySeconds} end
end

local function atGoal(member, position, radius, now)
    local goal = M.Destination(member)
    local current = math.sqrt(distance(position,goal))
    if not member.Best or current <= radius or member.Best-current >= member.Queue.Config.ProgressDistance then
        member.Best, member.LastProgress = current, now
    end
    return current <= radius, now-member.LastProgress >= member.Queue.Config.StallSeconds
end

function M.Destination(member)
    if member.Withdrawing then return member.Queue.Retreat end
    return member.Slot and member.Slot.Goal or member.Queue.Start
end

function M.Update(queue, positions, now, startRadius, sealed)
    queue.LandingClear = clear(queue,queue.Landing,nil,positions)
    local function valid(member)
        local position = positions[member.Actor]
        return queue.Actor.Enabled and position and queue.Geometry.Exterior(position)
    end
    local lead = queue.Lead
    if lead and not lead.Binding.Vault then
        if not valid(lead) then
            release(lead, now, false)
        else
            local position = positions[lead.Actor]
            local arrived, stalled = atGoal(lead, position,
                lead.Withdrawing and queue.Config.StopRadius or startRadius, now)
            if lead.Withdrawing then
                if arrived or stalled then release(lead, now, true) end
            elseif stalled then
                lead.Withdrawing, lead.Best = true, nil
                lead.Binding.RepathAt = nil
            end
        end
    end
    local first
    queue.HasWaiting = false
    for _, slot in ipairs(queue.Slots) do
        local member = slot.Member
        if member then
            if not valid(member) then
                release(member, now, false)
            else
                local _, stalled = atGoal(member, positions[member.Actor], queue.Config.StopRadius, now)
                if stalled then
                    release(member, now, true)
                else
                    queue.HasWaiting = true
                    if not first or member.Ticket < first.Ticket then first = member end
                end
            end
        end
    end
    queue.StartClear = clear(queue,queue.Start,nil,positions)
    if not queue.Lead and first and (sealed or queue.LandingClear)
        and clear(queue,queue.Start,first.Actor,positions) then
        first.Slot.Member, first.Slot, first.Best = nil,nil,nil
        first.Binding.RepathAt = nil
        queue.Lead = first
    end
    queue.LaunchClear = queue.Lead and clear(queue,queue.Start,queue.Lead.Actor,positions)
end

function M.Offer(queue, binding, now, sealed)
    local retry = binding.QueueRetry
    if retry and retry.Queue == queue and now < retry.Until then return nil end
    if not queue.Lead and not queue.HasWaiting and queue.StartClear and (sealed or queue.LandingClear) then
        return queue
    end
    for _, slot in ipairs(queue.Slots) do
        if not slot.Member then return slot end
    end
end

function M.Assign(queue, slot, actor, binding)
    queue.Ticket = queue.Ticket+1
    local member = {Queue=queue, Actor=actor, Binding=binding, Ticket=queue.Ticket}
    binding.QueueMember = member
    if slot == queue then
        queue.Lead = member
    else
        slot.Member, member.Slot = member, slot
        queue.HasWaiting = true
    end
end

function M.AfterVault(member, landed)
    if landed then
        release(member, nil, false)
    else
        member.Withdrawing, member.Best = true, nil
    end
end

return M
