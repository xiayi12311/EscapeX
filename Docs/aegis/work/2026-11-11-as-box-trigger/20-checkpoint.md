# Checkpoint

Status: implementation saved; actual component/network acceptance still needs verification.

## Implemented
- Asset/Sequences/BP_ASBoxTrigger.uasset: BoxComponent subclass, grouped instance-editable SequenceComponentName (string) and Enabled (bool). Defaults ActorSequence/true, extent (100,100,150), overlaps, Trigger collision profile, replicated.
- Script/Sequences/BP_ASBoxTrigger.lua: owner AS lookup; server-only player overlap filter; per-component once latch; multicast StartPlay(0,true); cleanup. No changes to existing Run.lua.
- Asset/Sequences/Run.uasset: added ASBoxTrigger, configured Trigger collision, extent (100,100,150), bReplicates=true on template and actor. Both existing AS retained with bAutoPlay=false. No AS tracks intentionally changed; no unrelated map save.
- Important finding: add_component_to_blueprint used native Box defaults for extent/replication despite subclass CDO; explicitly corrected Run template and verified after compile/save.
- Backup: backup/2026-11-11-as-box-trigger/Asset/Sequences/Run.uasset, SHA256 9431EBD07231819AAF64D49227E8A44415A41B4821919BC6F15D159AC13E6EF5.

## Verification and limits
- Run compiled without errors; nine SCS components including original two AS.
- Variables PropertyFlags=5 (editable, blueprint-visible), Category=AS Trigger.
- CDO and Run template defaults read back. Run template replication=true, extent 100/100/150, collision profile Trigger.
- Existing PIE discovered active session 2392A5D8414387E1A9BE47812898FC79, player 10001. User explicitly chose to preserve session, NOT stop/restart. Do not restart it without permission.
- Injected isolated modeled logic test in existing client's Lua runtime: PASS filter, once latch, independent boxes/AS, disabled, missing target, cleanup. This was a re-expression of source with mocks, NOT execution of saved component or actual network/overlap validation.
- Direct loadfile test failed: snippet:1: attempt to call a nil value (global 'loadfile'). Runtime load=function, loadstring=nil,setfenv=nil. Project luacheck executable is custom keyword/directory checker, not standard luacheck; no syntax-check success claimed.

## Round 2 review
- Independent read-only review confirmed official multicast accepts ActorComponent; only relevant actor-holding clients receive it. Run CDO had bAlwaysRelevant=false, so set bAlwaysRelevant=true and saved Run; readback true plus bReplicates=true. This avoids distance relevance excluding current players.
- Current latch is once per component lifetime (map session), not automatically reset by project's capture/desk-search mini-round. Asked user to clarify intended boundary and permission to spawn a temporary test actor without PIE restart; question was cancelled. No permission inferred, no actor spawned.
- Review subagent 7c8f5a4d-8854-46ac-a786-99e9429c8e30 stopped externally after interim read-only findings; no pending work owned by that agent.
- Preserve current PIE; actual spawn/overlap/network tests remain unexecuted.

## Remaining acceptance
1. In a newly started test (when user allows), verify actual BoxComponent Lua ReceiveBeginPlay, owner AS lookup, component reliable multicast, real pawn overlap, once latch, two clients seeing playback.
2. Duplicate component within Run, move copy, set SequenceComponentName=ActorSequence1, verify independent playback; remove test copy unless desired by user.
3. Check box placement against intended path visually; current added box is at owner origin. User can edit position/extent in Run viewport.
4. Whole objective NOT complete; goal remains active. No forced restart or automatic stop. No fallback implementation.

## Use
Open Run blueprint, select ASBoxTrigger. Edit relative location/rotation and Box Extent. Under AS Trigger set SequenceComponentName to ActorSequence or ActorSequence1 (exact component variable name), Enabled controls triggering. Copy/paste the component in component tree; each copy stores its own name/config/latch. Owner and trigger replication must stay enabled. Restart PIE to load changed assets; current old session does not prove new behavior.
