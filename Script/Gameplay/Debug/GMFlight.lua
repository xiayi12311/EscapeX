-- GM flight applies on the server and the owning client for movement prediction.
local Flight = {}
local MoveNone, MoveFalling, MoveFlying = 0, 3, 5
local ForwardInput = 'Input.Move.MoveForward'
local InputInterval = 0.016
local FlyingBrakeDeceleration = 6000

function Flight.StopInput(pawn)
    if pawn.EscapeXFlightInputTimer then
        UGCTimerUtility.RemoveLuaTimer(pawn.EscapeXFlightInputTimer)
        pawn.EscapeXFlightInputTimer = nil
    end
end

local function startInput(pawn)
    if UGCGameSystem.IsServer() or not pawn:IsLocallyControlled() or pawn.EscapeXFlightInputTimer then return end
    pawn.EscapeXFlightInputTimer = UGCTimerUtility.CreateLuaTimer(InputInterval, function()
        if not pawn.EscapeXGMFlight or pawn.CharacterMovement.MovementMode ~= MoveFlying then return end
        local forward = UGCInputSystem.GetInputValue(pawn, ForwardInput)
        if type(forward) ~= 'number' or forward == 0 then return end
        local pitch = pawn:GetControlRotation().Pitch
        pawn:AddMovementInput({X=0, Y=0, Z=1}, forward * math.sin(math.rad(pitch)), false)
    end, true, 'EscapeX.GM.FlightInput')
end

function Flight.Apply(pawn, enabled)
    local movement = pawn.CharacterMovement
    local ownsMovement = pawn:HasAuthority() or pawn:IsLocallyControlled()
    if enabled then
        if ownsMovement then
            if pawn.EscapeXFlightPreviousBrake == nil then
                pawn.EscapeXFlightPreviousBrake = movement.BrakingDecelerationFlying
            end
            movement.BrakingDecelerationFlying = FlyingBrakeDeceleration
            movement:SetMovementMode(MoveFlying, 0)
        end
        if pawn.EscapeXFlightPreviousCollision == nil then
            pawn.EscapeXFlightPreviousCollision = pawn:GetActorEnableCollision()
        end
        pawn:SetActorEnableCollision(false)
        startInput(pawn)
        return
    end

    Flight.StopInput(pawn)
    local previous = pawn.EscapeXFlightPreviousCollision
    if previous == nil then return end
    pawn:SetActorEnableCollision(previous)
    pawn.EscapeXFlightPreviousCollision = nil
    local previousBrake = pawn.EscapeXFlightPreviousBrake
    if previousBrake ~= nil then
        movement.BrakingDecelerationFlying = previousBrake
        pawn.EscapeXFlightPreviousBrake = nil
    end
    if ownsMovement and movement.MovementMode == MoveFlying then
        movement:StopMovementImmediately()
        movement:SetMovementMode(MoveFalling, 0)
    end
end

function Flight.Set(pawn, enabled)
    local movement = pawn.CharacterMovement
    if not pawn:HasAuthority() or not KismetSystemLibrary.IsValid(movement) then return false end
    if enabled and (movement.MovementMode == MoveNone or not movement:IsComponentTickEnabled()) then
        ugcprint('[EscapeX GM] Flight cannot start while character movement is locked')
        return false
    end
    Flight.Apply(pawn, enabled)
    pawn.EscapeXGMFlight = enabled
    return true
end

return Flight
