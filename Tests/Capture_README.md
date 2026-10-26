# Capture regression checks

`capture_test.txt` and `capture_flow_test.txt` contain Lua 5.1 tests. Keep their `.txt` extensions: this editor validates every `.lua` file in the UGC project, including test directories.

From the repository root, with an external Lua 5.1 interpreter:

```sh
lua -e "TEST_ROOT='.'; dofile('Tests/capture_test.txt'); dofile('Tests/capture_flow_test.txt')"
```

The tests also run with Python Lupa's `lupa.lua51.LuaRuntime` when `TEST_ROOT` is set to the absolute repository path before executing the two files. Keep that Python runner and any dependencies outside the editor project.

Expected output: `capture rules ok` followed by `capture flow integration ok: 21 groups`.

For an explicitly authorized PIE test, dispatch `capture_pie_driver1.txt` to the DS to create temporary posts on the player's current ground plane. The fixture is intended for the current flat test area, not terrain placement in production. Dispatch `capture_clean_retest.txt` to the DS for an automated service-level flow check. This automatic input test does not replace a person clicking the native break-free button.

Capture now replaces the old damage settlement. `HTDamage` is not read by Lua, its legacy blueprint default is zero, and diagnostic `HTCommon.TRACE` is disabled. Native UI, replication and position evidence is recorded in `Docs/HeadTeacher_capture_three_issues_20261026.md`.
