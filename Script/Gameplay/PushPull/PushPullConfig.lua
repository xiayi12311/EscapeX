-- PushPullConfig is the single source of truth for the prototype. Business modules must
-- read these values instead of carrying local copies of animation paths or tuning.
local C = {}

C.Animations = {
    OnPosition = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_OnPosition.CG009_Puzzle_OnPosition',
    Idle = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_Idle.CG009_Puzzle_Idle',
    PushStart = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PushStart.CG009_Puzzle_PushStart',
    Push = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_Push.CG009_Puzzle_Push',
    PushStop = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PushStop.CG009_Puzzle_PushStop',
    PullStart = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PullStart.CG009_Puzzle_PullStart',
    Pull = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_Pull.CG009_Puzzle_Pull',
    PullStop = '/Game/Actor_Timeliness/Maze2/Arts_Players/Anim/CG009_Puzzle_PullStop.CG009_Puzzle_PullStop',
}

-- User-approved DS timing contract. These values are copied from the design document
-- section 2.1 because /Game animation packages are client-only in this build. The
-- owning client still loads the real sequence and validates the length below.
C.AnimationDurations = {
    OnPosition = 1.333,
    Idle = 1.533,
    PushStart = 1.333,
    Push = 2.100,
    PushStop = 0.800,
    PullStart = 0.600,
    Pull = 1.000,
    PullStop = 0.733,
}

C.Interaction = {
    DetectInterval = 0.1,
    PositionInterval = 0.02,
    MonitorInterval = 0.25,
    TraceDistance = 350,
    SurfaceInteractionBand = 90,
    MaxFacingAngle = 60,
    MaxParticipants = 8,
    MinGripSpacing = 70,
    EdgeMargin = 28,
    AutoSpreadMax = 40,
    AutoSpreadStep = 5,
    GripStandOff = 45,
    AllowJoinWhileMoving = false,
    JoinMaxSpeed = 15,
    CrateClassPath = '/EscapeX/Asset/Blueprint/Prefabs/Interactables/BP_PushPullCrate.BP_PushPullCrate_C',
    WidgetClassPath = '/EscapeX/Asset/MIG/Blueprint/AI_PatientMonster/WBP_Interact_patient.WBP_Interact_patient_C',
    OutlineThickness = 2,
    OutlineColor = {R = 1, G = 0.8, B = 0, A = 0.8},
    ReadyRetryTicks = 100,
    Label = '推拉',
    ReleaseLabel = '松开',
}

C.Movement = {
    BaseSpeed = 55,
    MaxSpeed = 220,
    Acceleration = 240,
    Deceleration = 360,
    OppositionDeadzone = 0.15,
    MotionTickRate = 30,
    StatePublishInterval = 1 / 15,
}


C.Network = {
    ActorUpdateFrequency = 30,
    MinActorUpdateFrequency = 15,
    ActorConsiderFrequency = 30,
}

C.Input = {
    Tag = 'Input.Move.MoveForward',
    Deadzone = 0.15,
    Heartbeat = 0.15,
    Lease = 0.35,
    MaxRpcRate = 15,
}

C.Action = {
    AlignDuration = 0.15,
    MinLoopRate = 0.75,
    MaxLoopRate = 1.6,
    InputPollInterval = 0.05,
    AnimationDurationSafetyMax = 5.0,
}

C.ActionStateTags = {
    'PawnState.Movement.Walking',
    'PawnState.Action.Sprint',
    'PawnState.Action.Jump',
    'PawnState.Action.Vault',
    'PawnState.Action.HoldWeapon',
    'PawnState.Action.HoldGrenade',
    'PawnState.Action.MeleeAttack',
    'PawnState.Action.Pick',
    'PawnState.Action.SwitchWeapon',
    'PawnState.Action.UseConsumables',
    'PawnState.Gun.GunFire',
    'PawnState.Gun.GunADS',
    'PawnState.Pose.Crouch',
    'PawnState.Pose.Prone',
}

C.Reasons = {
    CRATE_DESTROYED = true,
    CRATE_DISABLED = true,
    PLAYER_UNAVAILABLE = true,
    PLAYER_BUSY = true,
    TOO_FAR = true,
    WRONG_FACE = true,
    NO_FREE_GRIP = true,
    STALE_REQUEST = true,
    CRATE_BLOCKED = true,
}

return C
