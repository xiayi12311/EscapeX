-- AkAudioEvent object paths. Empty means no asset has been assigned yet.
-- Use /Game/... or an Asset/... project-relative object path.
return {
    DetectionSound = 'Asset/WwiseEvent/TeacherDiscover.TeacherDiscover',
    LockSound = 'Asset/WwiseEvent/RedWarning.RedWarning',
    NearSound = 'Asset/WwiseEvent/YellowWarning.YellowWarning',
    WhiteSound = 'Asset/WwiseEvent/WhiteWarning.WhiteWarning',
    -- Whole-arrow red overlay alpha while the target is being detected.
    RedOverlayFadeInSeconds = 2.0,
    RedOverlayFadeOutPerSecond = 4,
    RedOverlayMaxAlpha = 1.0,
    RedOverlayRefreshInterval = 0.016,
}
