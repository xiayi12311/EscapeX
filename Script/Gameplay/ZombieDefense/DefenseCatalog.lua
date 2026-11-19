-- Prototype content IDs used by placed point Actors; no automatic startup.
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseConfig')
local targeting = {RepathSeconds = 0.6, WindowStopRadius = 5}
return {
    Modes = {Prototype = Config},
    BoardItemId = 8310006,
    SpawnGroups = {Default = {}},
    Enemies = {NormalZombie = {
        ClassPath = 'Asset/Blueprint/Prefabs/Monsters/NormalZombie.NormalZombie_C',
        DeathEvent = 'NormalZombie.BPDie',
        BoardDropChance = 0.25,
        Placement = {SearchRadius=400,Rings=3,SamplesPerRing=8,Radius=34,HalfHeight=88,
            Spacing=10,GroundClearance=3,QueryExtent={X=40,Y=40,Z=200},ObjectTypes={0,1,2,3,4,7,12}},
    }},
    WindowQueue = {
        WaitOffsets = {-110, -220, -330}, RetreatOffset = 110,
        Clearance = 85, StopRadius = 15, ProjectionTolerance = 35, VerticalClearance = 140,
        ProgressDistance = 15, StallSeconds = 4, RetrySeconds = 3,
    },
    BoardInstallCheckSeconds = 0.1,
    BoardAttackSkill = {
        ClassPath = 'Asset/Blueprint/Prefabs/Skills/ZS_BoardClaw.ZS_BoardClaw_C',
        Slot = 'Skill.Slot.Slot1',
    },
    BoardPresentation = {
        ClassPath = 'Asset/Blueprint/ZombieSurvival/Points/BP_ZS_BoardVisual.BP_ZS_BoardVisual_C',
        AssetWidth = 178,
    },
    BoardAssault = {
        DamagePerSecond = 25, AttackRange = 200, ClimbSeconds = 2.5, MaxAttackers = 2,
        SwingInterval = 1.6, HitDelay = 0.45,
    },
    Targeting = {ZombieTest = targeting, DefenseMainTest = targeting},
    Shops = {
        Prototype = {Range = 350, StartingFunds = 500},
        SpawnShop = {Range = 350, StartingFunds = 500, StandaloneLevel = 'UGCmap'},
    },
}
