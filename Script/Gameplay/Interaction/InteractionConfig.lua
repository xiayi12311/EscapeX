-- Tunables for the local interaction layer. Kept in one place because the migrated
-- source had a 0.1s configured cadence against a 0.2s hardcoded one (see
-- Docs/UnifiedInteraction_migration_plan.md); the plan requires a single source.
return {
    DetectInterval = 0.1,          -- seconds between local focus scans
    MonitorInterval = 0.25,        -- seconds between local-pawn identity checks
    TraceDistance = 350,           -- cm the crosshair ray may find a target
    OutlineThickness = 2,
    OutlineColor = {R = 1, G = 0.8, B = 0, A = 0.8},
    WidgetClassPath = '/EscapeX/Asset/MIG/Blueprint/AI_PatientMonster/WBP_Interact_patient.WBP_Interact_patient_C',
    DeskClassPath = '/EscapeX/Asset/Blueprint/Prefabs/Interactables/BP_SearchableDesk.BP_SearchableDesk_C',
    -- Give up instead of erroring forever when the local player is not ready;
    -- one explicit log, then the session stops.
    ReadyRetryTicks = 100,
}
