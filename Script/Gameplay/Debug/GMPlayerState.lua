local State = {}
local InvisibleTag = 'PVENian.PawnState.Invisible'
local ChooseEnemyTag = 'LogicPart.Class.ChooseEnemy'

function State.IsInvisible(pawn)
    return pawn.EscapeXGMInvisible == true
end

function State.SetInvisible(pawn, enabled)
    if State.IsInvisible(pawn) == enabled then return true end
    local changed
    if enabled then
        changed = UGCPersistEffectSystem.EnterDynamicState(pawn, InvisibleTag)
    else
        changed = UGCPersistEffectSystem.LeaveDynamicState(pawn, InvisibleTag)
    end
    if not changed then
        ugcprint('[EscapeX GM] Could not change invisible state: '..InvisibleTag)
        return false
    end
    pawn.EscapeXGMInvisible = enabled
    return true
end

function State.ConfigureZombieTargeting(mob)
    local manager = mob.LogicPartManagerComp
    if manager == nil or not KismetSystemLibrary.IsValid(manager) then
        ugcprint('[EscapeX GM] Native zombie has no LogicPartManagerComp')
        return
    end
    local part = manager:GetLogicPartByTag(UGCGameplayTagSystem.RequestGameplayTag(ChooseEnemyTag))
    local tag = UGCGameplayTagSystem.RequestGameplayTag(InvisibleTag)
    if part == nil or not KismetSystemLibrary.IsValid(part) or not UGCGameplayTagSystem.IsValidTag(tag) then
        ugcprint('[EscapeX GM] Native zombie target filter setup failed')
        return
    end
    local producers = part.TargetProducers
    for index = 1, producers:Num() do
        local producer = producers:Get(index)
        local excludes = producer.FilterExcludeTags
        if not UGCGameplayTagSystem.HasTag(excludes, tag, true) then
            UGCGameplayTagSystem.AddGameplayTagToContainer(excludes, tag)
            producer:SetTargetFilter(producer.FilterCampRelations, producer.FilterEntityTypeTags,
                producer.FilterIncludeTags, excludes)
        end
    end
end

function State.IsGMInvincible(pawn)
    return pawn.EscapeXGMInvincible == true
end

-- Release only this owner's immunity; restore the native flag after the last release.
local function setInvincible(pawn, ownerField, otherField, enabled)
    if (pawn[ownerField] == true) == enabled then return true end

    local before = UGCPlayerPawnSystem.GetIsInvincible(pawn)
    local original = pawn.EscapeXInvincibleBeforeProtection
    if original == nil then original = before end
    local desired = enabled or pawn[otherField] == true or original
    if desired ~= before then
        UGCPlayerPawnSystem.SetIsInvincible(pawn, desired)
        if UGCPlayerPawnSystem.GetIsInvincible(pawn) ~= desired then return false end
    end

    pawn[ownerField] = enabled
    if enabled or pawn[otherField] == true then
        pawn.EscapeXInvincibleBeforeProtection = original
    else
        pawn.EscapeXInvincibleBeforeProtection = nil
    end
    return true
end

function State.SetGMInvincible(pawn, enabled)
    return setInvincible(pawn, 'EscapeXGMInvincible', 'EscapeXCaptureInvincible', enabled)
end

function State.SetCaptureInvincible(pawn, enabled)
    return setInvincible(pawn, 'EscapeXCaptureInvincible', 'EscapeXGMInvincible', enabled)
end

return State
