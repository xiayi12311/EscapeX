local Catalog = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseCatalog')
local Geometry = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseWindowGeometry')
local Config = Catalog.BoardPresentation
local Presentation = {}
local plankClass

local function valid(object)
    return object ~= nil and KismetSystemLibrary.IsValid(object)
end

local function destroy(actor)
    if valid(actor) then UGCActorComponentUtility.DestroyActor(actor) end
end

local function configureVaultBlocker(blocker)
    blocker:SetCollisionObjectType(ECollisionChannel.ECC_WorldStatic)
    blocker:SetCollisionResponseToAllChannels(ECollisionResponse.ECR_Ignore)
    blocker:SetCollisionResponseToChannel(ECollisionChannel.ECC_Pawn, ECollisionResponse.ECR_Block)
    blocker:SetCollisionResponseToChannel(ECollisionChannel.ECC_GameTraceChannel3, ECollisionResponse.ECR_Block)
    blocker:SetCollisionResponseToChannel(ECollisionChannel.ECC_GameTraceChannel15, ECollisionResponse.ECR_Block)
end

local function addBoard(window, view, slot, animated)
    if not plankClass then
        plankClass = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(Config.ClassPath))
    end
    assert(valid(plankClass), 'DEFENSE_BOARD_VISUAL_CLASS_UNAVAILABLE')
    local pos = view.Geometry.Board
    local offset = (slot - (view.Capacity + 1) / 2) * window.SlotSpacing
    local actor = UGCActorComponentUtility.SpawnActor(window, plankClass,
        {X = pos.X, Y = pos.Y, Z = pos.Z + offset}, view.Geometry.Rotation,
        {X = 1, Y = window.BoardWidth / Config.AssetWidth, Z = 1}, window)
    assert(valid(actor) and valid(actor.BoardCollision), 'DEFENSE_BOARD_COLLISION_SPAWN_FAILED')
    local collision = actor.BoardCollision
    collision:SetCollisionObjectType(ECollisionChannel.ECC_WorldDynamic)
    collision:SetCollisionResponseToAllChannels(ECollisionResponse.ECR_Ignore)
    collision:SetCollisionResponseToChannel(ECollisionChannel.ECC_Pawn, ECollisionResponse.ECR_Block)
    collision:SetCollisionResponseToChannel(ECollisionChannel.ECC_GameTraceChannel3, ECollisionResponse.ECR_Block) -- PlayerPawn
    collision:SetCollisionEnabled(ECollisionEnabled.QueryOnly)
    view.Boards[slot] = actor
    if not view.Render then return end
    assert(valid(actor.BoardMesh) and valid(actor.InstallSequence)
        and valid(actor.RemoveSequence), 'DEFENSE_BOARD_VISUAL_SPAWN_FAILED')
    if animated then
        actor.InstallSequence:StartPlay(0, true)
        actor.InstallSequence.SequencePlayer:JumpToPosition(0)
    end
end

local function removeBoard(view, slot, animated)
    local actor = view.Boards[slot]
    view.Boards[slot] = nil
    if not valid(actor) then return end
    actor.BoardCollision:SetCollisionEnabled(ECollisionEnabled.NoCollision)
    if not animated or not view.Render then
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
    local closed = next(desired) ~= nil
    if view.VaultBlocked ~= closed then
        window.VaultBlocker:SetCollisionEnabled(closed and ECollisionEnabled.QueryOnly or ECollisionEnabled.NoCollision)
        view.VaultBlocked = closed
    end
end

function Presentation.Begin(window)
    if window.DefenseBoardView or not window.Enabled then return end
    local geometry = assert(Geometry.Build(window))
    Geometry.Apply(window, geometry)
    configureVaultBlocker(window.VaultBlocker)
    window.DefenseBoardView = {Capacity = window.BoardsPerWindow, Boards = {}, Removing = {},
        Geometry = geometry, Render = not KismetSystemLibrary.IsDedicatedServer(window)}
    Presentation.Apply(window, false)
end

function Presentation.End(window)
    local view = window.DefenseBoardView
    if not view then return end
    window.DefenseBoardView = nil
    if valid(window.VaultBlocker) then window.VaultBlocker:SetCollisionEnabled(ECollisionEnabled.NoCollision) end
    for _, actor in pairs(view.Boards) do destroy(actor) end
    for actor in pairs(view.Removing) do
        view.Removing[actor] = nil
        destroy(actor)
    end
end

return Presentation
