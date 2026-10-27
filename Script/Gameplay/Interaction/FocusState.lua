-- Local presentation state only: server-owned DeskState is the source of truth.
local FocusState = {}
FocusState.__index = FocusState

function FocusState.new(playerKey)
    return setmetatable({playerKey=playerKey, focus=nil, active=nil, revisions={}}, FocusState)
end

function FocusState:SetFocus(actor)
    self.focus=actor
end

function FocusState:ApplyDeskState(actor, state)
    if not actor or not state then return false end
    local revision=state.Revision or 0
    if self.revisions[actor] and revision<self.revisions[actor] then return false end
    self.revisions[actor]=revision
    if state.State=='Searching' and state.SearchingPlayerId==self.playerKey then
        self.active=actor
    elseif self.active==actor then
        self.active=nil
    end
    return true
end

function FocusState:Remove(actor)
    if self.focus==actor then self.focus=nil end
    if self.active==actor then self.active=nil end
    self.revisions[actor]=nil
end

function FocusState:DisplayTarget()
    return self.active or self.focus
end

function FocusState:CanRequest()
    local desk=self.focus
    return self.active==nil and desk~=nil and desk.DeskState~=nil and desk.DeskState.State=='Closed'
end

return FocusState
