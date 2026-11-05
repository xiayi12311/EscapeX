-- AkAudioEvent object paths. Empty means no asset has been assigned yet.
-- Use /Game/... or an Asset/... project-relative object path.
return {
    DetectionSound = 'Asset/WwiseEvent/TeacherDiscover.TeacherDiscover',
    LockSound = 'Asset/WwiseEvent/RedWarning.RedWarning',
    NearSound = 'Asset/WwiseEvent/YellowWarning.YellowWarning',
    WhiteSound = 'Asset/WwiseEvent/WhiteWarning.WhiteWarning',
    -- Client-side visual duration; tune alongside the monster detection delay.
    DetectionProgressSeconds = 1.0,
    ProgressRefreshInterval = 0.016,
    ProgressReturnPerSecond = 4,
}
