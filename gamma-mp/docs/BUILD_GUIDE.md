# GAMMA Multiplayer — Build Guide (Windows)

Everything you need to go from "fresh Windows install" to "two STALKER instances
connected with synced A-Life." Follow in order. Estimated time: ~2 hours for setup,
then iterative builds are ~5-20 min.

---

## Step 1: Install Visual Studio 2022

1. Download **Visual Studio 2022 Community** (free): https://visualstudio.microsoft.com/
2. During install, select these workloads:
   - **Desktop development with C++**
3. In **Individual Components**, also check:
   - MSVC v140 - VS 2015 C++ build tools (v14.00)
   - Windows 8.1 SDK
   - C++ MFC for latest v143 build tools
   - C++ ATL for latest v143 build tools
4. Install. This is the biggest download (~8-15 GB). Go grab food.

## Step 2: Install Git

1. Download Git for Windows: https://git-scm.com/download/win
2. Install with defaults. Make sure "Git from the command line" is selected.

## Step 3: Install CMake

1. Download latest CMake: https://cmake.org/download/
2. Install. Check "Add CMake to system PATH."

## Step 4: Install vcpkg

Open a **Developer Command Prompt for VS 2022** (search Start menu):

```
cd C:\
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
bootstrap-vcpkg.bat
```

## Step 5: Clone the Engine

```
cd C:\dev
git clone https://github.com/themrdemonized/xray-monolith.git
cd xray-monolith
git submodule update --init --recursive
```

The main branch is `all-in-one-vs2022-wpo`.

## Step 6: Apply the Engine Patch

Open these files and make the changes described in the `.patch` files
in `gamma-mp/engine-patch/`:

1. `src/xrGame/alife_update_manager.h` — add `m_mp_client_mode` member + setter
2. `src/xrGame/alife_update_manager.cpp` — add flag guard to `update()` + `shedule_Update()`
3. `src/xrGame/alife_simulator_script.cpp` — expose `set_mp_client_mode` to Lua
4. `src/xrGame/level_script.cpp` — add `set_game_time()` function

Each patch file shows exactly what to find and what to replace.

Then add the GNS bridge Lua registration:
5. Copy `gns_bridge_luabind.cpp` to `src/xrGame/`
6. Copy `gns_bridge_poll.cpp` to `src/xrGame/`
7. Add both files to the xrGame project in Visual Studio (right-click xrGame → Add → Existing Item)

In the script registration chain (find where other `script_register` calls happen):
8. Add: `extern void gns_bridge_script_register(lua_State* L);`
9. Add: `extern void gns_bridge_poll_register(lua_State* L);`
10. Call both after the existing registrations.

## Step 7: Build the Engine

1. Open `engine-vs2022.sln` in Visual Studio 2022 **as Administrator**
2. Select **Release** configuration (not VerifiedDX11 unless debugging)
3. Build → Rebuild Solution
4. Or use: `batch_build.bat` from command line

Output: `_build_game/bin_dbg/` — you need the new `.exe` and `.dll` files.

## Step 8: Build the GNS Bridge DLL

```
cd C:\dev\gamma-mp\gns-bridge

# Install GameNetworkingSockets via vcpkg
C:\vcpkg\vcpkg install gamenetworkingsockets:x64-windows

# Build
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake
cmake --build build --config Release
```

Output: `build/bin/Release/gns_bridge.dll` + `GameNetworkingSockets.dll`

## Step 9: Install STALKER Anomaly + GAMMA

1. Download STALKER Anomaly 1.5.3 from moddb.com (free standalone)
2. Clone GAMMA: `git clone https://github.com/Grokitach/Stalker_GAMMA.git`
3. Run the GAMMA installer: `.Grok's Modpack Installer/G.A.M.M.A. Launcher.exe`
4. Let it download all mods. Takes 20-40 min.

## Step 10: Install the Multiplayer Components

1. Copy the forked engine binary from Step 7 to your Anomaly `bin/` folder
   (replaces the stock Demonized exe)
2. Copy `gns_bridge.dll` and `GameNetworkingSockets.dll` to Anomaly `bin/`
3. Copy the Lua scripts from `gamma-mp/lua-sync/` to
   `Anomaly/gamedata/scripts/`:
   - `mp_core.script`
   - `mp_protocol.script`
   - `mp_host_events.script`
   - `mp_client_state.script`

## Step 11: Test

### Test A: Engine builds and GAMMA still works
1. Launch GAMMA normally
2. Load a save or start new game
3. Play for 5 minutes — A-Life should work normally
4. Open console (~) and run: `mp_core.mp_init()` — should print initialization success

### Test B: A-Life suppression works
1. Open console: `alife():set_mp_client_mode(true)`
2. A-Life should stop updating (NPCs freeze in background simulation)
3. `alife():set_mp_client_mode(false)` — A-Life resumes
4. Game should not crash in either state

### Test C: Two instances connect
1. Run two copies of the game
2. Instance 1 (host): `mp_core.mp_host(44140)`
3. Instance 2 (client): `mp_core.mp_connect("127.0.0.1", 44140)`
4. Check console output for connection messages

---

## Quick Reference: What Goes Where

```
Anomaly/
├── bin/
│   ├── AnomalyDX11.exe          ← your forked engine build
│   ├── gns_bridge.dll            ← GNS bridge
│   └── GameNetworkingSockets.dll ← Valve's networking lib
└── gamedata/
    └── scripts/
        ├── mp_core.script        ← core multiplayer module
        ├── mp_protocol.script    ← serialization & dispatch
        ├── mp_host_events.script ← host event capture
        └── mp_client_state.script ← client state application
```

## Troubleshooting

**Engine won't compile:**
- Make sure you ran `git submodule update --init --recursive`
- Verify Windows 8.1 SDK is installed
- Verify MSVC v140 build tools are installed
- Run VS2022 as Administrator

**gns_bridge.dll won't load:**
- Check that GameNetworkingSockets.dll is in the same directory
- Check that Visual C++ Redistributable 2022 is installed
- Run `dumpbin /dependents gns_bridge.dll` to check dependencies

**Game crashes on A-Life suppression:**
- This is the Phase 0 gate test. If it crashes, check the log at
  `Anomaly/appdata/logs/` for the exact failure point.
- Most likely: mods calling `alife():object()` getting nil when
  the registry isn't populated. The fix is in the sync layer.

**Can't connect two instances on same machine:**
- Make sure firewall allows the port (default 44140)
- Try different ports if 44140 is taken
- Check console for GNS error messages
