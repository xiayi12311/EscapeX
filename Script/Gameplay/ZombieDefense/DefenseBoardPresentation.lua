local Catalog = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseCatalog')
local Config = Catalog.BoardPresentation
local Presentation = {}
local plankClass

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

local function destroy(actor)
    if valid(actor) then UGCActorComponentUtility.DestroyActor(actor) end
end

local function addBoard(window, view, slot, animated)
    if not plankClass then
        plankClass = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(Config.ClassPath))
    end
    assert(valid(plankClass), 'DEFENSE_BOARD_VISUAL_CLASS_UNAVAILABLE')
    local pos = window.BoardRoot:K2_GetComponentLocation()
    local direction = UGCMathUtility.FindLookAtRotation(window.OutsideApproach:K2_GetComponentLocation(),
        window.InsideLanding:K2_GetComponentLocation())
    local offset = (slot - (view.Capacity + 1) / 2) * Config.SlotSpacing
    local actor = UGCActorComponentUtility.SpawnActor(window, plankClass,
        {X = pos.X, Y = pos.Y, Z = pos.Z + offset}, {Pitch = 0, Yaw = direction.Yaw, Roll = 0},
        {X = 1, Y = 1, Z = 1}, window)
    assert(valid(actor) and valid(actor.BoardMesh) and valid(actor.InstallSequence)
        and valid(actor.RemoveSequence), 'DEFENSE_BOARD_VISUAL_SPAWN_FAILED')
    view.Boards[slot] = actor
    if animated then
        actor.InstallSequence:StartPlay(0, true)
        actor.InstallSequence.SequencePlayer:JumpToPosition(0)
    end
end

local function removeBoard(view, slot, animated)
    local actor = view.Boards[slot]
    view.Boards[slot] = nil
    if not animated or not valid(actor) then
        destroy(actor)
        return
    end
    if actor.InstallSequence.SequencePlayer then actor.InstallSequence:StopPlay() end
    view.Removing[actor] = true
    actor.RemoveSequence:StartPlay(0, true)
    actor.RemoveSequence.SequencePlayer.OnFinished:Add(function()
        if not view.Removing[actor] then return end
        view.Removing[actor] = nil
        destroy(actor)
    end, actor)
end

function Presentation.Apply(window, animated)
    local view = window.DefenseBoardView
    if not view then return end
    local desired = {}
    for value in string.gmatch(window.DefenseBoardSlots, '%d+') do
        local slot = tonumber(value)
        assert(slot >= 1 and slot <= view.Capacity and not desired[slot], 'INVALID_DEFENSE_BOARD_SLOT')
        desired[slot] = true
    end
    for slot in pairs(view.Boards) do
        if not desired[slot] then removeBoard(view, slot, animated) end
    end
    for slot in pairs(desired) do
        if not view.Boards[slot] then addBoard(window, view, slot, animated) end
    end
end

function Presentation.Begin(window)
    if window.DefenseBoardView or not window.Enabled or KismetSystemLibrary.IsDedicatedServer(window) then return end
    local profile = assert(Catalog.Barricades[window.BarricadeConfigId], 'DEFENSE_BOARD_CONFIG_UNAVAILABLE')
    window.DefenseBoardView = {Capacity = profile.BoardsPerWindow, Boards = {}, Removing = {}}
    Presentation.Apply(window, false)
end

function Presentation.End(window)
    local view = window.DefenseBoardView
    if not view then return end
    window.DefenseBoardView = nil
    for _, actor in pairs(view.Boards) do destroy(actor) end
    for actor in pairs(view.Removing) do
        view.Removing[actor] = nil
        destroy(actor)
    end
end

return Presentation
