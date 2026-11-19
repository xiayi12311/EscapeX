local Inventory = {}
local CapacityAttribute = 'PawnBackpackCapacity'
local CapacityBonus = 100000
local WeaponCheckSeconds = 0.1

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

local function restoreGun(pawn)
    local previous = pawn.EscapeXGMAmmoWeapon
    if valid(previous) then UGCGunSystem.EnableInfiniteBullets(previous, pawn.EscapeXGMAmmoOriginal) end
    pawn.EscapeXGMAmmoWeapon, pawn.EscapeXGMAmmoOriginal = nil, nil
end

local function updateGun(pawn, class)
    local gun = UGCWeaponManagerSystem.GetCurrentWeapon(pawn)
    if gun == pawn.EscapeXGMAmmoWeapon then return end
    restoreGun(pawn)
    if valid(gun) and UE.IsA(gun, class) then
        pawn.EscapeXGMAmmoWeapon = gun
        pawn.EscapeXGMAmmoOriginal = gun:GetIsInfiniteBulletNum()
        UGCGunSystem.ForceReloadAndEnableInfiniteBullets(gun, true)
    end
end

local function returnConsumed(pawn, _, _, defineId, count)
    if not pawn.EscapeXGMFreeSupplies or not defineId or count <= 0 then return end
    local id = defineId.TypeSpecificID
    UGCTimerUtility.CreateLuaTimer(0.01, function()
        if valid(pawn) and not UGCBackPackSystem.AddItem(pawn, id, count) then
            ugcprint('[EscapeX GM] Could not return consumed item '..tostring(id))
        end
    end, false)
end

function Inventory.StopAmmo(pawn)
    local backpack = pawn.EscapeXGMConsumeBackpack
    if valid(backpack) then backpack.ItemConsumedDelegate:Remove(returnConsumed, pawn) end
    pawn.EscapeXGMConsumeBackpack = nil
    if pawn.EscapeXGMAmmoTimer then
        UGCTimerUtility.RemoveLuaTimer(pawn.EscapeXGMAmmoTimer)
        pawn.EscapeXGMAmmoTimer = nil
    end
    restoreGun(pawn)
end

function Inventory.SetFreeSupplies(pawn, enable)
    if not enable then
        Inventory.StopAmmo(pawn)
        pawn.EscapeXGMFreeSupplies = false
        return true
    end
    local class = UE.LoadClass('/Script/ShadowTrackerExtra.STExtraShootWeapon')
    local backpack = UGCBackPackSystem.GetBackpackComponent(pawn)
    if not valid(class) or not valid(backpack) then return false end
    local timer = UGCTimerUtility.CreateLuaTimer(WeaponCheckSeconds, function()
        if valid(pawn) then updateGun(pawn, class) end
    end, true, 'EscapeX.GM.Ammo')
    if not timer then return false end
    pawn.EscapeXGMAmmoTimer = timer
    pawn.EscapeXGMFreeSupplies = true
    pawn.EscapeXGMConsumeBackpack = backpack
    backpack.ItemConsumedDelegate:Add(returnConsumed, pawn)
    updateGun(pawn, class)
    return true
end

function Inventory.SetCapacityBonus(pawn, enable)
    local before = UGCAttributeSystem.GetGameAttributeValue(pawn, CapacityAttribute)
    if type(before) ~= 'number' then return false end
    local bonus = enable and CapacityBonus or -pawn.EscapeXGMCapacityBonus
    local oldMax = UGCBackPackSystem.GetMaxCapacity(pawn)
    if type(oldMax) ~= 'number' then return false end
    UGCAttributeSystem.SetGameAttributeValue(pawn, CapacityAttribute, before + bonus)
    local newMax = UGCBackPackSystem.GetMaxCapacity(pawn)
    if type(newMax) ~= 'number' or (newMax - oldMax) * bonus <= 0 then
        UGCAttributeSystem.SetGameAttributeValue(pawn, CapacityAttribute, before)
        ugcprint('[EscapeX GM] Backpack capacity did not update')
        return false
    end
    pawn.EscapeXGMCapacityBonus = enable and bonus or nil
    return true
end

return Inventory
