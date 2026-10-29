-- Local view presentation only. The authoritative capture state is replicated separately.
local M={}
local current=nil
local interval=0.03
local carryYawOffset=180
local carryPitch=-50
local prisonPitch=0

local function valid(o) return o~=nil and KismetSystemLibrary.IsValid(o) end

function M.Stop(actor)
    if not current or (actor and current.actor~=actor) then return end
    local c=current
    current=nil
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    if valid(c.controller) then c.controller:SetIgnoreLookInput(false) end
    ugcprint('[CaptureCamera] view released')
end

local function update(c)
    if current~=c then return end
    if not valid(c.actor) or not valid(c.controller) or not valid(c.pawn)
        or UGCGameSystem.GetLocalPlayerPawn()~=c.pawn then
        M.Stop(c.actor)
        return
    end
    local ok,err=pcall(function()
        local rotation=c.actor:K2_GetActorRotation()
        local yaw=rotation.Yaw
        local pitch=prisonPitch
        if c.kind=='carry' then yaw=yaw+carryYawOffset; pitch=carryPitch end
        UGCPlayerControllerSystem.SetControlRotation(c.controller,{Roll=0,Pitch=pitch,Yaw=yaw})
    end)
    if not ok then
        ugcprint('[CaptureCamera] view update failed: '..tostring(err))
        M.Stop(c.actor)
    end
end

function M.Start(actor,kind)
    if current and current.actor==actor and current.kind==kind then return end
    M.Stop()
    local controller=UGCGameSystem.GetLocalPlayerController()
    local pawn=UGCGameSystem.GetLocalPlayerPawn()
    if not (valid(actor) and valid(controller) and valid(pawn)) then
        ugcprint('[CaptureCamera] cannot lock view: actor, controller or pawn unavailable')
        return
    end
    local c={actor=actor,controller=controller,pawn=pawn,kind=kind}
    current=c
    controller:SetIgnoreLookInput(true)
    update(c)
    if current~=c then return end
    c.timer=UGCTimerUtility.CreateLuaTimer(interval,function() update(c) end,true,'EscapeX.CaptureCamera')
    ugcprint('[CaptureCamera] view locked '..kind)
end

return M
