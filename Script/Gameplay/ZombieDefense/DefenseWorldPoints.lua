local Registry = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefensePointRegistry')
local WorldPoints = {}

WorldPoints.Classes = {
    Spawn = 'Asset/Blueprint/ZombieSurvival/Points/BP_ZS_SpawnPoint.BP_ZS_SpawnPoint_C',
    Window = 'Asset/Blueprint/ZombieSurvival/Points/BP_ZS_WindowPoint.BP_ZS_WindowPoint_C',
    Shop = 'Asset/Blueprint/ZombieSurvival/Points/BP_ZS_ShopPoint.BP_ZS_ShopPoint_C',
    Start = 'Asset/Blueprint/ZombieSurvival/Points/BP_ZS_StartPoint.BP_ZS_StartPoint_C',
}

function WorldPoints.Collect(context, catalog)
    assert(context and KismetSystemLibrary.IsValid(context), 'INVALID_WORLD_CONTEXT')
    assert(context:HasAuthority(), 'POINT_COLLECTION_SERVER_ONLY')
    local points = {}
    for _, kind in ipairs({'Spawn', 'Window', 'Shop', 'Start'}) do
        local path = WorldPoints.Classes[kind]
        local class = UE.LoadClass(UGCGameSystem.GetUGCResourcesFullPath(path))
        assert(class, 'POINT_CLASS_UNAVAILABLE: ' .. path)
        local actors = UGCActorComponentUtility.GetAllActorsOfClass(context, class)
        assert(type(actors) == 'table', 'INVALID_POINT_QUERY: ' .. kind)
        for _, actor in pairs(actors) do
            points[#points + 1] = {Kind = kind, Actor = actor}
        end
    end
    return Registry.Build(points, catalog, function(object)
        return object ~= nil and KismetSystemLibrary.IsValid(object)
    end)
end

return WorldPoints
