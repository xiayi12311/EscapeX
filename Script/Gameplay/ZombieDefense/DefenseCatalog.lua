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
    EntranceGroups = {Default = {}},
    -- Board numbers only; no price, no reward. Free boarding is the current
    -- suggestion and is not yet a confirmed economy decision.
    Barricades = {Default = {
        BoardsPerWindow = 3, BoardDurability = 120, InstallSeconds = 2,
        InstallRange = 180, ClimbCapacity = 1, AssaultConfigId = 'Default',
    }},
    -- Zombie side of the same window: one shared profile, referenced by id so it
    -- can be tuned per window type without touching the board rules.
    Assaults = {Default = {
        DamagePerSecond = 25, AttackRange = 200, ClimbSeconds = 2.5, MaxAttackers = 2,
    }},
    -- The 400 cm collision-tested skill is enabled only at the verified west window.
    Vaults = {ZombieTest = {WindowNW = {
        ClassPath = "Asset/Blueprint/Prefabs/Skills/ZS_WindowVault.ZS_WindowVault_C",
        Slot = "Skill.Slot.Slot0", Travel = 400,
        StartRadius = 15, LandingRadius = 35, FootTolerance = 15,
    }}},
    Shops = {},
}
