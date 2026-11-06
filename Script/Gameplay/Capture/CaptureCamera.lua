-- Local view presentation only. The authoritative capture state is replicated separately.
-- Oasis TPP boom is UCustomSpringArmComponent -> USTExtraSpringArmComponent.
-- Collision ignore is AddIgonreActor/RemoveIgonreActor (CachedIgonreActor), NOT the
-- base USpringArmComponent.IgnoredActors field (prior patch wrote IgnoredActors and
-- still retracted into the head teacher). Reading a missing UFunction as a property
-- (arm.AddIgonreActor ~= nil) throws LuaExtend_GetProp on plain SpringArm components;
-- always probe via pcall around the call itself.
local M={}
local current=nil
local interval=0.03
local carryYawOffset=180
local carryPitch=-50
local prisonPitch=0
local ignoreCarrierOnSpringArm=true

local function valid(o) return o~=nil and KismetSystemLibrary.IsValid(o) end

local function pushUnique(list, item)
    if not valid(item) then return end
    for i=1,#list do if list[i]==item then return end end
    list[#list+1]=item
end

local function contains(list, item)
    if not list then return false end
    for i=1,#list do if list[i]==item then return true end end
    return false
end

-- CustomSpringArm is the live TPP arm; CurActiveSpringArm is often nil.
-- Do not blanket-touch ShoulderCameraSpringArm: it is a plain USpringArmComponent
-- without AddIgonreActor and property probes spam LuaException.
local function collectSpringArms(pawn)
    local arms={}
    if not valid(pawn) then return arms end
    -- Only Oasis custom TPP arms expose AddIgonreActor. CurActiveSpringArm often
    -- points at ShoulderCameraSpringArm (plain USpringArmComponent); calling
    -- AddIgonreActor there throws LuaExtend_GetProp and is not the boom in use.
    pushUnique(arms, pawn.CustomSpringArm)
    local ok, third=pcall(function() return pawn:GetThirdPersonSpringArm() end)
    if ok then pushUnique(arms, third) end
    return arms
end

local function setCarrierIgnoredOnArm(arm, actor, shouldIgnore)
    if not (valid(arm) and valid(actor)) then return false end
    local applied=false
    if shouldIgnore then
        -- Prefer Oasis AddIgonreActor; only treat that as applied for carry.
        local ok=pcall(function() arm:AddIgonreActor(actor) end)
        if ok then
            applied=true
            pcall(function()
                if valid(actor.Mesh) then arm:AddIgonreComponent(actor.Mesh) end
            end)
            pcall(function()
                if valid(actor.CapsuleComponent) then arm:AddIgonreComponent(actor.CapsuleComponent) end
            end)
        else
            pcall(function() arm.IgnoredActors:AddUnique(actor) end)
        end
    else
        local ok=pcall(function() arm:RemoveIgonreActor(actor) end)
        if ok then
            applied=true
            pcall(function()
                if valid(actor.Mesh) then arm:RemoveIgonreComponent(actor.Mesh) end
            end)
            pcall(function()
                if valid(actor.CapsuleComponent) then arm:RemoveIgonreComponent(actor.CapsuleComponent) end
            end)
        else
            local ok2=pcall(function() arm.IgnoredActors:Remove(actor) end)
            applied=ok2
        end
    end
    return applied
end

-- Ensure every currently relevant spring arm ignores the carrier. Only newly seen
-- arms get AddIgonreActor so CachedIgonreActor does not grow every tick.
local function ensureCarrierIgnore(c)
    if not (c and valid(c.pawn) and valid(c.ignoredCarrier)) then return 0 end
    c.ignoredArms=c.ignoredArms or {}
    local arms=collectSpringArms(c.pawn)
    local added=0
    for i=1,#arms do
        local arm=arms[i]
        if not contains(c.ignoredArms, arm) then
            if setCarrierIgnoredOnArm(arm, c.ignoredCarrier, true) then
                pushUnique(c.ignoredArms, arm)
                added=added+1
            end
        end
    end
    return added
end

local function clearSpringIgnore(c)
    if not c or not c.ignoredCarrier then return end
    if c.ignoredArms then
        for i=1,#c.ignoredArms do
            setCarrierIgnoredOnArm(c.ignoredArms[i], c.ignoredCarrier, false)
        end
    end
    c.ignoredCarrier=nil
    c.ignoredArms=nil
end

function M.Stop(actor)
    if not current or (actor and current.actor~=actor) then return end
    local c=current
    current=nil
    if c.timer then UGCTimerUtility.RemoveLuaTimer(c.timer) end
    clearSpringIgnore(c)
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
    if ignoreCarrierOnSpringArm and c.kind=='carry' and valid(c.ignoredCarrier) then
        ensureCarrierIgnore(c)
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
    if ignoreCarrierOnSpringArm and kind=='carry' then
        c.ignoredCarrier=actor
        local n=ensureCarrierIgnore(c)
        if n>0 then
            ugcprint('[CaptureCamera] spring arm ignores carrier via AddIgonreActor arms='..tostring(n))
        else
            ugcprint('[CaptureCamera] cannot ignore carrier on spring arm')
        end
    end
    update(c)
    if current~=c then return end
    c.timer=UGCTimerUtility.CreateLuaTimer(interval,function() update(c) end,true,'EscapeX.CaptureCamera')
    ugcprint('[CaptureCamera] view locked '..kind)
end

return M