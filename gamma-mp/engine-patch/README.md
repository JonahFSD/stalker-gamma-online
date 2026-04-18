# GAMMA Multiplayer — Engine Fork Patch

## Key Discovery

After reading the xray-monolith source, the required C++ changes are **even smaller** than
the architecture doc estimated. Here's why:

### Already Exposed to Lua (NO engine changes needed):
- `level.set_weather(name, forced)` — already in level_script.cpp
- `level.change_game_time(days, hours, mins)` — already in level_script.cpp (delta-based)
- `level.set_time_factor(factor)` — already in level_script.cpp
- `game_object:force_set_position(pos)` — already in script_game_object3.cpp
- `alife():teleport_object(id, gvid, lvid, pos)` — already in alife_simulator_script.cpp
- `alife():create() / release() / kill_entity()` — already exposed
- `alife():set_switch_online/offline()` — already exposed
- `alife():force_update()` — recently added (PR #493)

### Required C++ Changes

Phase 0 — A-Life suppression + time sync:
1. Add `mp_client_mode` flag to `CALifeUpdateManager`
2. Guard `update()` and `shedule_Update()` with that flag
3. Expose `set_mp_client_mode(bool)` to Lua
4. Add absolute `set_game_time(hours, mins, secs)` for precise time sync
   (change_game_time is delta-only — can add time but can't set it absolutely or go backwards)

Phase 1 — puppet heading:
5. Add `SetBodyYaw(float)` to `CScriptGameObject` (decl + impl + luabind registration)

Phase 1 — client resilience:
6. Soft-fail `lua_pcall_failed` on `mp_client_mode` (rate-limited log instead of `Debug.fatal`)

## Files to Modify

Phase 0 (patches 1–4, prose FIND/REPLACE format):
1. `src/xrGame/alife_update_manager.h` — add flag + setter declaration
2. `src/xrGame/alife_update_manager.cpp` — guard update() and shedule_Update()
3. `src/xrGame/alife_simulator_script.cpp` — expose to Lua
4. `src/xrGame/level_script.cpp` — add set_game_time()

Phase 1 (patches 5–7, prose FIND/REPLACE format):
5. `src/xrGame/script_game_object.h` — `SetBodyYaw(float)` declaration after `ForceSetRotation` (~line 1076)
6. `src/xrGame/script_game_object3.cpp` — `SetBodyYaw` implementation (writes `movement().m_body.current.yaw` and `.target.yaw`)
7. `src/xrGame/script_game_object_script3.cpp` — luabind `set_body_yaw` (~line 480)

Phase 1 (patch 8, proper git-format-patch output):
8. `src/xrServerEntities/script_engine.cpp` — soft-fail `lua_pcall_failed` when `ai().get_alife()->mp_client_mode()` is true. Rate limits: 20/signature for `gamma-mp`/`mp_*` sources, 5/signature for mods. Tags `[MP-OWN]`/`[MP-MOD]` for grep. Null-safe via `get_alife()` pointer accessor.

Phase 1 (patch 9, proper git-format-patch output):
9. `src/xrServerEntities/script_engine.cpp` — extends patch 8's soft-fail to `lua_error` (luabind `set_error_callback` path) and `lua_cast_failed` (luabind `set_cast_failed_callback` path). Factors the soft-fail block into a shared file-static helper `try_mp_client_soft_fail`; rate-limit map is shared across all three sites so the same error counts once regardless of dispatch path. Also guards `lua_tostring(L, -1)` with `lua_isstring` in `lua_error`. Without this, client-side Lua errors that dispatch through `set_error_callback` (the default path for engine-initiated calls) still fatal even on `mp_client_mode` clients.

## How to Apply

These are provided as both readable diffs and copy-paste patches.
See the .patch files in this directory.

Format note: patches 1–7 are prose-format ("FIND / REPLACE" narrative) — apply by hand.
Patches `0008_script_engine_soft_fail.patch` and `0009_script_engine_soft_fail_extend.patch` are proper `git format-patch` output and are `git am`-compatible.
