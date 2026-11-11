-- Prototype content IDs used by placed point Actors; no automatic startup.
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseConfig')
return {
    Modes = {Prototype = Config},
    SpawnGroups = {Default = {}},
    Enemies = {NormalZombie = {
        ClassPath = 'Asset/Blueprint/Prefabs/Monsters/NormalZombie.NormalZombie_C',
        DeathEvent = 'NormalZombie.BPDie',
        Placement = {SearchRadius=400,Rings=3,SamplesPerRing=8,Radius=34,HalfHeight=88,
            Spacing=10,GroundClearance=3,QueryExtent={X=40,Y=40,Z=200},ObjectTypes={0,1,2,3,4,7,12}},
    }},
    EntranceGroups = {}, Barricades = {}, Shops = {},
}
