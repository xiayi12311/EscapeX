local Aim = {}

local WeaponPollSeconds = 0.04
local MaxCameraOffsetCm = 450
local MinAimAgreement = math.cos(math.rad(25))
local Rpc = 'ServerRequestBossBreakShot'
local points = {}
local watchedWeapon, weaponTimer

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

local function finite(n)
    return type(n) == 'number' and n > -math.huge and n < math.huge
end

local function isVector(v)
    local kind = type(v)
    return (kind == 'table' or kind == 'userdata') and finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function dot(a, b)
    return a.X*b.X + a.Y*b.Y + a.Z*b.Z
end

local function between(a,b)
    return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z}
end

local function active(point)
    return valid(point) and point.BreakCueState and point.BreakCueState.Phase == 'Active'
end

local function hitDistance(center, radius, origin, direction, maxDistance)
    local relative = between(center, origin)
    local forward = dot(relative,direction)
    if forward <= 0 then return nil end
    local depth = radius*radius - math.max(0,dot(relative,relative) - forward*forward)
    if depth < 0 then return nil end
    local entry = math.max(0,forward-math.sqrt(depth))
    if entry <= maxDistance then return entry end
end

local function sendShot(weapon)
    if weapon ~= watchedWeapon then return end
    local controller = UGCGameSystem.GetLocalPlayerController()
    local camera = controller and controller.PlayerCameraManager
    if not camera then return end
    local origin = camera:GetCameraLocation()
    local direction = KismetMathLibrary.GetForwardVector(camera:GetCameraRotation())
    local range = UGCGunSystem.GetBulletRange(weapon)
    local nearest, nearestCenter, distance
    for point in pairs(points) do
        if active(point) then
            local center = point.BreakPointWidget:K2_GetComponentLocation()
            -- Use the authored radius as geometry only. No scene collision lookup.
            local hit = hitDistance(center, point.HitBox:GetScaledCapsuleRadius(), origin, direction, range)
            if hit and (not distance or hit < distance) then
                nearest, nearestCenter, distance = point, center, hit
            end
        end
    end
    if nearest then
        UnrealNetwork.CallUnrealRPC(controller,controller,Rpc,nearest,weapon,weapon:GetCurShootID(),
            origin.X,origin.Y,origin.Z,direction.X,direction.Y,direction.Z,
            nearestCenter.X,nearestCenter.Y,nearestCenter.Z)
    end
end

local function watchWeapon(weapon)
    if weapon == watchedWeapon then return end
    if valid(watchedWeapon) then watchedWeapon.OnWeaponShootDelegate:Remove(sendShot,watchedWeapon) end
    watchedWeapon = nil
    if valid(weapon) and weapon.OnWeaponShootDelegate then
        watchedWeapon = weapon
        weapon.OnWeaponShootDelegate:Add(sendShot,weapon)
    end
end

local function updateWeapon()
    local pawn = UGCGameSystem.GetLocalPlayerPawn()
    watchWeapon(valid(pawn) and UGCWeaponManagerSystem.GetCurrentWeapon(pawn) or nil)
end

function Aim.Track(point)
    points[point] = true
    if weaponTimer then return end
    updateWeapon()
    weaponTimer = UGCTimerUtility.CreateLuaTimer(WeaponPollSeconds,updateWeapon,true)
end

function Aim.Untrack(point)
    points[point] = nil
    if not weaponTimer or next(points) then return end
    UGCTimerUtility.RemoveLuaTimer(weaponTimer)
    weaponTimer = nil
    watchWeapon(nil)
end

function Aim.ResolveShot(controller,point,weapon,shotId,origin,direction,center)
    if type(point) ~= 'userdata' or type(weapon) ~= 'userdata'
        or not active(point) or not valid(weapon) or not finite(shotId) or shotId < 0
        or shotId % 1 ~= 0 or not isVector(origin) or not isVector(direction) or not isVector(center) then return end
    local skill = point.BossBreakSkill
    if not valid(skill) or skill.BossCastPhase ~= 'Charging' then return end
    local window = skill.BossBreakWindow
    if not window or window.Points[point.BossBreakPointId] ~= point or not valid(window.Boss) then return end

    local pawn = UGCGameSystem.GetPlayerPawnByPlayerController(controller)
    if not valid(pawn) or UGCPawnAttrSystem.GetHealth(pawn) <= 0
        or UGCWeaponManagerSystem.GetCurrentWeapon(pawn) ~= weapon
        or not weapon.OnWeaponShootDelegate or weapon:GetOwnerPlayerController() ~= controller then return end

    local offset = between(origin,pawn:K2_GetActorLocation())
    if dot(offset,offset) > MaxCameraOffsetCm^2 or math.abs(dot(direction,direction)-1) > 0.01 then return end
    local controlDirection = KismetMathLibrary.GetForwardVector(controller:GetControlRotation())
    if dot(direction,controlDirection) < MinAimAgreement then return end

    local now = UGCGameSystem.GetGameState():GetServerWorldTimeSeconds()
    if now > point.BreakCueState.Deadline then return end
    local last = controller.BossBreakLastShot
    if last and last.Weapon == weapon and (last.Id == shotId
        or now - last.At < weapon:GetShootIntervalFromEntity()*0.5) then return end
    -- A dedicated server can be several meters away from the rendered hand pose.
    -- Verify that the sampled point belongs to this cast and stays within the Boss's pose scale.
    local displacement = between(center,point:K2_GetActorLocation())
    local bodyHeight = 2 * window.Boss.CapsuleComponent:GetScaledCapsuleHalfHeight()
    if dot(displacement,displacement) > bodyHeight^2
        or not hitDistance(center,point.HitBox:GetScaledCapsuleRadius(),origin,direction,UGCGunSystem.GetBulletRange(weapon)) then return end

    controller.BossBreakLastShot = {Weapon=weapon,Id=shotId,At=now}
    skill:BreakBossPoint(point)
end

return Aim
