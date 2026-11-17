-- Prototype content IDs used by placed point Actors; no automatic startup.
local Config = UGCGameSystem.UGCRequire('Script.Gameplay.ZombieDefense.DefenseConfig')
local function vaultProfile(skill)
    return {
        ClassPath = 'Asset/Blueprint/Prefabs/Skills/' .. skill .. '.' .. skill .. '_C',
        Slot = 'Skill.Slot.Slot0', Travel = 400,
        StartRadius = 15, LandingRadius = 35, FootTolerance = 15,
    }
end
local standardVault = vaultProfile('ZS_WindowVault')
local policeVault = vaultProfile('ZS_PoliceWindowVault')
local testTargeting = {RepathSeconds = 0.6, WindowStopRadius = 5}
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
    BoardPresentation = {
        ClassPath = 'Asset/Blueprint/ZombieSurvival/Points/BP_ZS_BoardVisual.BP_ZS_BoardVisual_C',
        SlotSpacing = 32,
    },
    -- Zombie side of the same window: one shared profile, referenced by id so it
    -- can be tuned per window type without touching the board rules.
    Assaults = {Default = {
        DamagePerSecond = 25, AttackRange = 200, ClimbSeconds = 2.5, MaxAttackers = 2,
    }},
    Targeting = {ZombieTest = testTargeting, DefenseMainTest = testTargeting},
    Vaults = {
        ZombieTest = {WindowNW = standardVault, WindowNE = standardVault},
        DefenseMainTest = {
            DefenseWindow01 = policeVault,
            DefenseWindow02 = policeVault,
            DefenseWindow03 = policeVault,
        },
    },
    Shops = {},
}
