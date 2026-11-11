-- Prototype content IDs used by placed point Actors; no automatic startup.
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseConfig')
return {
    Modes = {Prototype = Config},
    SpawnGroups = {Default = {}},
    Enemies = {NormalZombie = {
        ClassPath = 'Asset/Blueprint/Prefabs/Monsters/NormalZombie.NormalZombie_C',
        DeathEvent = 'NormalZombie.BPDie',
    }},
    EntranceGroups = {}, Barricades = {}, Shops = {},
}
