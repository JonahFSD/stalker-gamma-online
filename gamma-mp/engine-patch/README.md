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

### Required C++ Changes (ONLY the A-Life suppression):
1. Add `mp_client_mode` flag to `CALifeUpdateManager`
2. Guard `update()` and `shedule_Update()` with that flag
3. Expose `set_mp_client_mode(bool)` to Lua
4. Add absolute `set_game_time(hours, mins, secs)` for precise time sync
   (change_game_time is delta-only — can add time but can't set it absolutely or go backwards)

That's it. ~30 lines of C++ across 3 files.

## Files to Modify

1. `src/xrGame/alife_update_manager.h` — add flag + setter declaration
2. `src/xrGame/alife_update_manager.cpp` — guard update() and shedule_Update()
3. `src/xrGame/alife_simulator_script.cpp` — expose to Lua
4. `src/xrGame/level_script.cpp` — add set_game_time()

## How to Apply

These are provided as both readable diffs and copy-paste patches.
See the .patch files in this directory.
