# GAMMA Multiplayer — Claude Code Setup Prompt

Copy everything below the line and paste it into Claude Code on your Windows machine.

---

I'm building a multiplayer fork of STALKER GAMMA (the biggest Anomaly modpack, 661K Discord members). The architecture is host-authoritative A-Life with client suppression — one machine runs A-Life, clients receive the results over the network. All the code has been written and is sitting in a folder on this machine. I need you to set up the entire dev environment, apply patches, build everything, and get it to a testable state.

## What exists already (in my gamma-mp folder)

Find the `gamma-mp` folder on this machine (likely in a recently selected/mounted folder, or on the Desktop, or in Documents — search for it). It contains:

- `setup.ps1` — PowerShell script that automates repo cloning, vcpkg setup, patch application, and GNS bridge building
- `engine-patch/` — Human-readable .patch files describing exact C++ changes to xray-monolith
- `gns-bridge/` — Complete GNS bridge DLL source (gns_bridge.h, gns_bridge.cpp, CMakeLists.txt, gns_bridge_luabind.cpp, gns_bridge_poll.cpp)
- `lua-sync/` — Four Anomaly .script files (mp_core.script, mp_protocol.script, mp_host_events.script, mp_client_state.script)
- `docs/` — BUILD_GUIDE.md, DISCOVERIES.md with full technical details

## What I need you to do (in order)

### Phase 1: Dev Environment

1. **Check if Visual Studio 2022 is installed.** Look for vswhere.exe at `${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe`. If VS2022 isn't installed, download the Community installer from https://visualstudio.microsoft.com/thank-you-downloading-visual-studio/?sku=Community&channel=Release&version=VS2022 and tell me to run it with these workloads:
   - Desktop development with C++
   - Individual Components: MSVC v140 (VS 2015 C++ build tools), Windows 8.1 SDK, C++ MFC, C++ ATL

2. **Install Git** if not present: `winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements`

3. **Install CMake** if not present: `winget install --id Kitware.CMake -e --source winget --accept-package-agreements --accept-source-agreements`

4. **Set up vcpkg** at `C:\vcpkg`:
   ```
   git clone https://github.com/microsoft/vcpkg.git C:\vcpkg
   cd C:\vcpkg && .\bootstrap-vcpkg.bat
   ```

5. **Add firewall rule** for the GNS default port:
   ```
   New-NetFirewallRule -DisplayName "GAMMA MP" -Direction Inbound -Protocol UDP -LocalPort 44140 -Action Allow
   New-NetFirewallRule -DisplayName "GAMMA MP TCP" -Direction Inbound -Protocol TCP -LocalPort 44140 -Action Allow
   ```

### Phase 2: Clone Repositories

Clone these to `C:\gamma-mp\`:

- `git clone https://github.com/themrdemonized/xray-monolith.git` then `git submodule update --init --recursive` inside it
- `git clone https://github.com/ValveSoftware/GameNetworkingSockets.git`
- `git clone https://github.com/damiansirbu-stalker/AlifePlus.git`
- `git clone https://github.com/damiansirbu-stalker/xlibs.git`
- `git clone https://github.com/Grokitach/Stalker_GAMMA.git`

### Phase 3: Apply Engine Patches

The engine fork requires ~30 lines of C++ changes across 4 files. Here are the EXACT changes:

#### File 1: `C:\gamma-mp\xray-monolith\src\xrGame\alife_update_manager.h`

Add member variable. Find `bool m_changing_level;` and add after it:
```cpp
bool m_mp_client_mode;  // GAMMA MP: A-Life suppression for clients
```

Add method declarations. Find `virtual ~CALifeUpdateManager();` and add after it:
```cpp
void set_mp_client_mode(bool value);
bool mp_client_mode() const { return m_mp_client_mode; }
```

#### File 2: `C:\gamma-mp\xray-monolith\src\xrGame\alife_update_manager.cpp`

In constructor, find `m_first_time = true;` and add after it:
```cpp
m_mp_client_mode = false;  // GAMMA MP
```

In `update()` function (around line 113), add at the very top of the function body:
```cpp
if (m_mp_client_mode) return;  // GAMMA MP: skip A-Life on client
```

In `shedule_Update()`, find `if (!initialized()) return;` and add after it:
```cpp
if (m_mp_client_mode) return;  // GAMMA MP: skip scheduled A-Life on client
```

Add at the END of the file:
```cpp
void CALifeUpdateManager::set_mp_client_mode(bool value)
{
    m_mp_client_mode = value;
    if (value)
        Msg("* [GAMMA MP] A-Life client mode ENABLED");
    else
        Msg("* [GAMMA MP] A-Life client mode DISABLED");
}
```

#### File 3: `C:\gamma-mp\xray-monolith\src\xrGame\alife_simulator_script.cpp`

Find the `force_update` function (around line 455) and add AFTER it:
```cpp
// GAMMA MP: A-Life suppression
void set_mp_client_mode(CALifeSimulator* self, bool value) { self->set_mp_client_mode(value); }
bool get_mp_client_mode(CALifeSimulator* self) { return self->mp_client_mode(); }
```

Find `.def("force_update", &force_update)` in the Lua binding registration and add after it:
```cpp
.def("set_mp_client_mode", &set_mp_client_mode)
.def("mp_client_mode", &get_mp_client_mode)
```

#### File 4: `C:\gamma-mp\xray-monolith\src\xrGame\level_script.cpp`

Find the `change_game_time` function (around line 285) and add this NEW function AFTER it:
```cpp
void set_game_time(u32 hours, u32 mins, u32 secs)
{
    game_sv_Single* tpGame = smart_cast<game_sv_Single*>(Level().Server->game);
    if (!tpGame || !ai().get_alife()) return;
    u32 year = 0, month = 0, day = 0, c_hours = 0, c_mins = 0, c_secs = 0, c_milisecs = 0;
    split_time(Level().GetGameTime(), year, month, day, c_hours, c_mins, c_secs, c_milisecs);
    s32 current_tod = c_hours * 3600 + c_mins * 60 + c_secs;
    s32 target_tod = hours * 3600 + mins * 60 + secs;
    s32 delta = target_tod - current_tod;
    if (abs(delta) <= 1) return;
    if (delta < 0) delta += 86400;
    float fDelta = static_cast<float>(delta);
    u32 msDelta = delta * 1000;
    g_pGamePersistent->Environment().ChangeGameTime(fDelta);
    tpGame->alife().time_manager().change_game_time(msDelta);
}
```

Find `def("change_game_time", change_game_time),` and add after it:
```cpp
def("set_game_time", set_game_time),
```

### Phase 4: Add GNS Bridge to Engine

Copy these files from my `gamma-mp/gns-bridge/` folder into `C:\gamma-mp\xray-monolith\src\xrGame\`:
- `gns_bridge_luabind.cpp`
- `gns_bridge_poll.cpp`

Then find where Lua script registrations happen in the engine (search for other `script_register` function calls being invoked in sequence). Add these two lines:
```cpp
extern void gns_bridge_script_register(lua_State* L);
extern void gns_bridge_poll_register(lua_State* L);
```
And call them:
```cpp
gns_bridge_script_register(L);
gns_bridge_poll_register(L);
```

Also add both .cpp files to the xrGame.vcxproj so they get compiled. Find the `<ClCompile>` section and add entries for both files.

### Phase 5: Build GNS Bridge DLL

```
C:\vcpkg\vcpkg.exe install gamenetworkingsockets:x64-windows
cd C:\gamma-mp\gns-bridge
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake
cmake --build build --config Release
```

Output: `build/bin/Release/gns_bridge.dll`

### Phase 6: Build the Engine

This is the main build. Use the VS2022 developer command line tools:

```
cd C:\gamma-mp\xray-monolith
```

Open `engine-vs2022.sln` or use MSBuild from the Developer Command Prompt:
```
"C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" engine-vs2022.sln /p:Configuration=Release /p:Platform=x64 /m
```

If it fails, read the errors carefully. Most common issues:
- Missing Windows 8.1 SDK → install via VS Installer
- Missing MSVC v140 → install via VS Installer  
- Submodules not initialized → `git submodule update --init --recursive`

The build output goes to `_build_game\bin_dbg\`.

### Phase 7: Verify

After building:
1. Check that the engine exe exists in `_build_game\bin_dbg\`
2. Check that `gns_bridge.dll` exists in `gns-bridge\build\bin\Release\`
3. List the Lua .script files in `gamma-mp\lua-sync\`
4. Report what succeeded and what failed

## Key Technical Context

- The engine uses **Lua 5.1** (NOT LuaJIT) — `lua51.lib`. No FFI available.
- Lua bindings use **luabind** — `module(L, "namespace") [ def("func", &func) ]` pattern.
- The engine fork base is themrdemonized/xray-monolith, branch `all-in-one-vs2022-wpo`.
- The ONLY required C++ change for multiplayer is A-Life suppression (skipping `CALifeUpdateManager::update()`). Everything else (`set_weather`, `force_set_position`, `teleport_object`, `create`, `release`, `kill_entity`) is already exposed to Lua.
- GameNetworkingSockets has a flat C API, BSD-3 license, handles encryption + NAT punch-through.

## Lua Sync Layer Architecture (for reference)

The four `.script` files work together:

- **mp_core.script** — State management, init/shutdown, host/client API, main update loop. Blocks client saves to prevent corruption. Registers `server_entity_on_register` callback on client for ID mapping.
- **mp_protocol.script** — Text-based message serialization (`"MSG_TYPE|key=val|..."` for events, `"EP|id,x,y,z,h;..."` for positions). All entity IDs are the HOST's native IDs.
- **mp_host_events.script** — Hooks Demonized callbacks + AlifePlus xbus. Maintains a tracked entity registry (no linear scans). Broadcasts events and periodic position snapshots.
- **mp_client_state.script** — Applies host state to client world. **Maintains bidirectional ID mapping table** (`host_id <-> local_id`) because `alife():create()` generates new local IDs that differ from the host's. All entity lookups go through `resolve_id(host_id)`.

### ID Mapping Flow:
1. Host sends `ENTITY_SPAWN` with `id=4200` (host's native ID)
2. Client stores pending spawn key: `"section_x_y_z" -> 4200`
3. Client calls `alife():create(section, pos, lvid, gvid)` — engine generates local ID 7831
4. Engine fires `server_entity_on_register(se_obj)` with `se_obj.id = 7831`
5. Client's callback matches the pending spawn key, creates mapping: `4200 -> 7831`
6. All subsequent messages referencing host ID 4200 get resolved to local ID 7831

## If something goes wrong

- If patches don't apply cleanly, READ the actual source files and make the equivalent changes. The patches are simple — a bool flag, early returns, and new function definitions.
- If the engine build fails on unrelated errors, try `batch_build.bat` instead of MSBuild.
- If vcpkg can't find GNS, try: `C:\vcpkg\vcpkg.exe install gamenetworkingsockets:x64-windows --triplet x64-windows`
- The GNS bridge DLL and engine are independent builds. If one fails, the other can still proceed.

Do everything you can. Report what worked and what needs my intervention.
