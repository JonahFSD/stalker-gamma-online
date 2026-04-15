# Key Discoveries from Engine Analysis

Findings from reading the xray-monolith source that reduce scope significantly.

## The C++ Work Is Smaller Than Expected

The architecture doc estimated ~500 lines of C++ changes. After reading the actual
source, the required engine changes are approximately **30 lines across 4 files**.

### Already Exposed to Lua (zero engine work needed):

| Function | File | What It Does |
|----------|------|-------------|
| `level.set_weather(name, forced)` | level_script.cpp:162 | Sets weather preset |
| `level.change_game_time(d, h, m)` | level_script.cpp:285 | Adds time (delta) |
| `level.set_time_factor(factor)` | level_script.cpp:230 | Sets time speed |
| `level.get_weather()` | level_script.cpp:157 | Gets current weather |
| `obj:force_set_position(pos)` | script_game_object3.cpp:1800 | Force-moves entity |
| `obj:force_set_rotation(rot)` | script_game_object3.cpp | Force-rotates entity |
| `alife():teleport_object(id,gvid,lvid,pos)` | alife_update_manager.cpp:400 | Moves offline entity |
| `alife():create(section,pos,lvid,gvid[,pid])` | alife_simulator_script.cpp | Spawns entity |
| `alife():release(se_obj)` | alife_simulator_script.cpp | Removes entity |
| `alife():kill_entity(obj[,killer])` | alife_simulator_script.cpp | Kills entity |
| `alife():set_switch_online(id, bool)` | alife_simulator_script.cpp | Force online |
| `alife():set_switch_offline(id, bool)` | alife_simulator_script.cpp | Force offline |
| `alife():force_update()` | alife_simulator_script.cpp:455 | Force A-Life tick |
| `alife():object(id)` | alife_simulator_script.cpp | Query entity |

### Only Engine Change Required: A-Life Suppression

The ONLY thing Lua cannot do is skip the A-Life update loop. That loop runs in C++:

```
// alife_update_manager.cpp, line 113
void CALifeUpdateManager::update()
{
    update_switch();       // online/offline switching
    update_scheduled(false); // background entity simulation
}
```

The fix: one boolean flag and two early returns. That's it.

The `set_game_time()` addition is optional (nice to have for precise sync)
but `change_game_time()` can work with delta calculations from Lua.

## The xbus Event System

AlifePlus uses `xbus` (in xlibs) — a clean pub/sub bus:
- `xbus.subscribe(event_name, callback, subscriber_name)`
- `xbus.publish(event_name, data_table)`

Events flow: engine callback → AlifePlus cause → xbus → consequences.
We subscribe to xbus to capture all A-Life decisions on the host.

## The Lua Write Surface Is Complete

Every state mutation the sync layer needs is already callable from Lua.
The C++ boundary is exactly as described in the architecture doc —
only things Lua literally cannot do.

## Engine Is Actively Maintained

themrdemonized's xray-monolith had a release on April 13, 2026 (yesterday).
PR #493 exposed `force_update()` to Lua. The engine is gaining more
Lua-accessible surface area over time, which works in our favor.

## Standard Lua 5.1, Not LuaJIT

The engine uses `lua51.lib`, not LuaJIT. The `USE_LUAJIT_ONE` define is
explicitly undefined in all project files. This means:
- No FFI for loading DLLs from Lua
- Must use luabind registration (adding C++ files to xrGame project)
- LuaJIT-2 source exists in `3rd party/` but isn't linked

This is why the GNS bridge needs the luabind registration files
(`gns_bridge_luabind.cpp` and `gns_bridge_poll.cpp`) compiled into xrGame.
