-- Server-owned perspective setup for player login and respawn.
local M={}
local timers={}
local localOwner=nil
local localTimer=nil
local lockedPawn=nil

function M.Cancel(controller)
    local timer=timers[controller]
    if timer then UGCTimerUtility.RemoveLuaTimer(timer); timers[controller]=nil end
end

function M.Schedule(controller)
    if not (controller and KismetSystemLibrary.IsValid(controller)) then
        ugcprint('[FirstPerson] invalid controller; cannot set perspective')
        return
    end
    M.Cancel(controller)
    local attempts=0
    timers[controller]=UGCTimerUtility.CreateLuaTimer(0.2,function()
        if not KismetSystemLibrary.IsValid(controller) then M.Cancel(controller); return end
        attempts=attempts+1
        local pawn=UGCGameSystem.GetPlayerPawnByPlayerController(controller)
        if pawn and KismetSystemLibrary.IsValid(pawn) then
            M.Cancel(controller)
            local ok=UGCPlayerPawnSystem.SetIsFPP(pawn,true,true)
            ugcprint('[FirstPerson] set player='..tostring(controller.PlayerKey)..' accepted='..tostring(ok))
        elseif attempts>=50 then
            M.Cancel(controller)
            ugcprint('[FirstPerson] player pawn unavailable after 10 seconds; perspective not set')
        end
    end,true,'EscapeX.FirstPerson.'..tostring(controller.PlayerKey))
end

function M.Shutdown()
    for controller in pairs(timers) do M.Cancel(controller) end
end

-- The local controller persists through respawns; each replacement pawn needs its own lock.
function M.MonitorLocal(controller)
    if controller~=UGCGameSystem.GetLocalPlayerController() or localTimer then return false end
    localOwner=controller
    localTimer=UGCTimerUtility.CreateLuaTimer(0.2,function()
        local pawn=UGCGameSystem.GetLocalPlayerPawn()
        if pawn==lockedPawn or not (pawn and KismetSystemLibrary.IsValid(pawn)) then return end
        pawn:LockTPP(ELockTPPReason.LTR_Level)
        lockedPawn=pawn
        ugcprint('[FirstPerson] local third-person lock applied')
    end,true,'EscapeX.FirstPerson.LocalMonitor')
    return true
end

function M.StopLocal(controller)
    if controller~=localOwner then return end
    if localTimer then UGCTimerUtility.RemoveLuaTimer(localTimer) end
    localOwner=nil
    localTimer=nil
    lockedPawn=nil
end

return M
