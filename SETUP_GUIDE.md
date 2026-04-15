# GAMMA Multiplayer — Setup Guide

Two dudes in the Zone. This guide gets you from zero to connected.

## What This Is

A multiplayer mod for STALKER GAMMA. One player hosts, the other connects. The host runs the game normally — their A-Life simulation (NPCs, mutants, anomalies, squads) is broadcast over the network to the client. The client's A-Life is suppressed and replaced with the host's world state. Both players see the same Zone.

**Current state (Phase 0):** World sync works — entities spawn, move, die, and despawn in sync. Weather and time sync. No player-to-player visibility yet (that's Phase 1).

## Requirements

Both players need:

- **STALKER Anomaly 1.5.3** installed (the base game)
- **GAMMA modpack** installed via the GAMMA installer (uses Mod Organizer 2)
- **Windows 10/11, 64-bit**
- **Port 44140** open (UDP) on the host's router/firewall — only the host needs this

This guide assumes GAMMA is installed at `C:\GAMMA` and Anomaly is at `C:\ANOMALY`. Adjust paths if yours differ.

## Architecture (How It Works)

```
HOST (runs game normally)              CLIENT (suppressed A-Life)
┌──────────────────────┐               ┌──────────────────────┐
│  A-Life simulation   │               │  A-Life SUPPRESSED   │
│  (NPCs, mutants,     │   UDP/TCP     │  (no local sim)      │
│   squads, anomalies) │──────────────>│                      │
│                      │  port 44140   │  Receives host state  │
│  mp_host_events      │   via GNS     │  mp_client_state     │
│  captures events     │               │  applies events      │
└──────────────────────┘               └──────────────────────┘
```

The host IS the singleplayer game. Our code just watches what happens and tells the client about it.

---

## Setup — Step by Step

There are two ways to set this up. **Option A** is fully automated using Claude Code. **Option B** is manual if you don't have Claude Code.

### What You Need From This Repo

The repo contains source code. The files that actually go into the game are:

**Engine files** (go in `C:\ANOMALY\bin\`):
- `AnomalyDX11.exe` — patched engine with MP support (must be built from source)
- `gns_bridge.dll` — networking bridge (must be built from source)
- `GameNetworkingSockets.dll` — Valve's networking library (built with gns_bridge)
- `abseil_dll.dll` — GNS dependency
- `libcrypto-3-x64.dll` — GNS dependency
- `libprotobuf.dll` — GNS dependency

**Lua scripts** (go in GAMMA's MO2 overwrite: `C:\GAMMA\overwrite\gamedata\scripts\`):
- `mp_core.script` — core module, init/shutdown, main loop
- `mp_protocol.script` — message serialization
- `mp_host_events.script` — host-side event capture
- `mp_client_state.script` — client-side state application
- `mp_alife_guard.script` — blocks mod interference on client (metatable patch)
- `mp_ui.script` — in-game multiplayer menu

**UI layout** (goes in `C:\GAMMA\overwrite\gamedata\configs\ui\`):
- `ui_mp_menu.xml` — XML layout for the F10 menu

**Mod compatibility patch** (goes in `C:\GAMMA\overwrite\gamedata\scripts\`):
- `mp_g_patches.script` OR patched `_g.script` — blocks mod conflicts on client

---

## Option A: Automated Setup with Claude Code

If you have [Claude Code](https://claude.com/claude-code) (Anthropic's CLI tool), you can set everything up by pasting prompts. Run these in order.

### A1. Clone the Repo

```bash
git clone https://github.com/JonahFSD/stalker-gamma-online.git
cd stalker-gamma-online
```

### A2. Build Everything from Source

Open Claude Code in the repo directory and paste the contents of:

```
gamma-mp/CLAUDE_CODE_PROMPT.md
```

This is the master setup prompt. It will:
1. Clone all dependencies (xray-monolith engine fork, GameNetworkingSockets, AlifePlus, engine libs)
2. Build the GNS bridge DLL
3. Apply engine patches to xray-monolith
4. Build the engine (DX11 exe)
5. Deploy everything

**This takes a while.** The engine has 31 projects. Go make coffee.

### A3. Deploy to GAMMA

After building, paste the contents of:

```
gamma-mp/CLAUDE_CODE_DEPLOY.md
```

This finds your Anomaly and GAMMA installs, copies the exe + DLLs to `C:\ANOMALY\bin\`, and copies the Lua scripts to GAMMA's MO2 overwrite folder.

### A4. Patch Mod Compatibility

Paste the contents of:

```
gamma-mp/CLAUDE_CODE_PATCH_AND_REDEPLOY.md
```

This patches `_g.script` (or creates `mp_g_patches.script`) to block ~50 mod conflicts on the client side.

### A5. Deploy the MP Menu

Paste the contents of:

```
gamma-mp/CLAUDE_CODE_DEPLOY_MENU.md
```

This deploys the F10 menu UI files.

### A6. Swap the Exe into the AVX Slot

GAMMA defaults to launching `AnomalyDX11AVX.exe`. Our patched exe is `AnomalyDX11.exe`. We need to swap it:

```powershell
Copy-Item "C:\ANOMALY\bin\AnomalyDX11AVX.exe" "C:\ANOMALY\bin\AnomalyDX11AVX_stock.exe" -Force
Copy-Item "C:\ANOMALY\bin\AnomalyDX11.exe" "C:\ANOMALY\bin\AnomalyDX11AVX.exe" -Force
```

This backs up the stock AVX exe and replaces it with ours. GAMMA now launches our patched engine automatically.

### A7. Open Port 44140 (Host Only)

The host needs port 44140 open. Run PowerShell as Administrator:

```powershell
New-NetFirewallRule -DisplayName "GAMMA Multiplayer" -Direction Inbound -Protocol UDP -LocalPort 44140 -Action Allow
New-NetFirewallRule -DisplayName "GAMMA Multiplayer TCP" -Direction Inbound -Protocol TCP -LocalPort 44140 -Action Allow
```

If you're behind a router, also forward port 44140 (UDP + TCP) to your PC's local IP. Look up "port forwarding" for your router model if you're not sure how.

---

## Option B: Manual Setup (No Claude Code)

### B1. Clone and Build

```bash
git clone https://github.com/JonahFSD/stalker-gamma-online.git
cd stalker-gamma-online
```

You need:
- **Visual Studio 2022** with C++ desktop workload
- **CMake 3.20+**
- **vcpkg** (for GNS dependencies)

#### Build GNS Bridge

```powershell
cd gamma-mp\gns-bridge
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

Output: `build\bin\Release\gns_bridge.dll` plus dependency DLLs.

#### Build Engine

1. Clone the engine fork:
   ```bash
   cd gamma-mp
   git clone https://github.com/themrdemonized/xray-monolith.git --branch all-in-one-vs2022-wpo
   ```

2. Apply patches from `gamma-mp/engine-patch/` to the engine source. Each `.patch` file shows which file to modify and what to change.

3. Add `gns_bridge_luabind.cpp` and `gns_bridge_poll.cpp` from `gamma-mp/gns-bridge/` to the xrGame project.

4. Open `gamma-mp/xray-monolith/xray-16.sln` in Visual Studio 2022, set to Release|x64, and build.

Output: `_build\_game\bin_dbg\AnomalyDX11.exe` (and DX9 variant).

### B2. Deploy Files

**Engine files → `C:\ANOMALY\bin\`:**

```powershell
$bin = "C:\ANOMALY\bin"

# Patched exe
Copy-Item "gamma-mp\xray-monolith\_build\_game\bin_dbg\AnomalyDX11.exe" "$bin\" -Force

# GNS DLLs
$gnsBin = "gamma-mp\gns-bridge\build\bin\Release"
Copy-Item "$gnsBin\gns_bridge.dll" "$bin\" -Force
Copy-Item "$gnsBin\GameNetworkingSockets.dll" "$bin\" -Force
Copy-Item "$gnsBin\abseil_dll.dll" "$bin\" -Force
Copy-Item "$gnsBin\libcrypto-3-x64.dll" "$bin\" -Force
Copy-Item "$gnsBin\libprotobuf.dll" "$bin\" -Force
```

**Swap into AVX slot:**

```powershell
Copy-Item "$bin\AnomalyDX11AVX.exe" "$bin\AnomalyDX11AVX_stock.exe" -Force
Copy-Item "$bin\AnomalyDX11.exe" "$bin\AnomalyDX11AVX.exe" -Force
```

**Lua scripts → MO2 overwrite:**

```powershell
$scripts = "C:\GAMMA\overwrite\gamedata\scripts"
$ui = "C:\GAMMA\overwrite\gamedata\configs\ui"
New-Item -ItemType Directory -Force -Path $scripts | Out-Null
New-Item -ItemType Directory -Force -Path $ui | Out-Null

Copy-Item "gamma-mp\lua-sync\mp_core.script" "$scripts\" -Force
Copy-Item "gamma-mp\lua-sync\mp_protocol.script" "$scripts\" -Force
Copy-Item "gamma-mp\lua-sync\mp_host_events.script" "$scripts\" -Force
Copy-Item "gamma-mp\lua-sync\mp_client_state.script" "$scripts\" -Force
Copy-Item "gamma-mp\lua-sync\mp_alife_guard.script" "$scripts\" -Force
Copy-Item "gamma-mp\lua-sync\mp_ui.script" "$scripts\" -Force
Copy-Item "gamma-mp\lua-sync\ui\ui_mp_menu.xml" "$ui\" -Force
```

### B3. Open Port 44140 (Host Only)

Same as A7 above.

---

## Playing

### Host

1. Launch GAMMA through Mod Organizer 2 as normal
2. Load your save (or start a new game)
3. Press **F10** to open the MP menu
4. Click **Host**
5. You should see "GAMMA MP hosting on port 44140" on screen
6. Give your friend your IP address

Your game runs completely normally. Play as you always would. The mod watches what happens and broadcasts it.

### Client

1. Launch GAMMA through Mod Organizer 2 as normal
2. Load a save (any save — the world state will be overwritten by the host's)
3. Press **F10** to open the MP menu
4. Enter the host's IP address (and port if not 44140)
5. Click **Connect**
6. You should see "Connecting to [ip]:44140..." on screen

Once connected:
- Your A-Life is suppressed — NPCs, mutants, and squads stop doing their own thing
- The host's world state streams in — entities spawn, move, die, and despawn in sync
- Saves are blocked — your world is synthetic, saving would create a corrupt file
- Weather and time sync to the host

### In the Menu

| Button | What It Does |
|--------|-------------|
| **Host** | Start hosting on the port shown |
| **Connect** | Connect to the IP/port shown |
| **Disconnect** | Disconnect from host (re-enables your A-Life) |
| **Stop Host** | Stop hosting |
| **Status** | Show connection info (clients, tracked entities) |
| **Shutdown** | Full MP shutdown |

Press **ESC** or **Close** to dismiss the menu. Press **F10** again to reopen it.

---

## Troubleshooting

### "gns is nil" error on launch

The patched exe isn't running. Check that you swapped it into the AVX slot:
```powershell
# Verify the exe has our code
$bytes = [System.IO.File]::ReadAllBytes("C:\ANOMALY\bin\AnomalyDX11AVX.exe")
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
if ($text.Contains("[GAMMA MP]")) { "PATCHED" } else { "STOCK — need to swap" }
```

### Can't connect / connection times out

- Host: is port 44140 open? Check firewall + router port forwarding
- Are both players on the same game version?
- Try connecting on LAN first (use the host's local IP like 192.168.x.x)

### Game crashes on connect

Check the engine log at `C:\ANOMALY\appdata\logs\` for the most recent `.log` file. Search for `[GAMMA MP]` — every MP action is logged with this prefix.

### Entities not syncing

- Client should see "[GAMMA MP] Receiving full world state from host..." in the log
- If entity count is 0, the host's entity tracking might not have initialized — try stopping and re-hosting

### Save blocked message

This is intentional. The client's world is synthetic (built from network data). Saving it would create a corrupt save file. Your original save is safe — just disconnect before saving.

### Reverting to Stock

To remove MP and go back to stock GAMMA:

```powershell
# Restore stock exe
Copy-Item "C:\ANOMALY\bin\AnomalyDX11AVX_stock.exe" "C:\ANOMALY\bin\AnomalyDX11AVX.exe" -Force

# Remove MP scripts (optional — they're harmless without the patched exe)
Remove-Item "C:\GAMMA\overwrite\gamedata\scripts\mp_*.script" -Force
Remove-Item "C:\GAMMA\overwrite\gamedata\configs\ui\ui_mp_menu.xml" -Force
```

---

## Technical Details

For the curious. Skip this if you just want to play.

### The Stack

1. **Engine patches** (C++) — 4 files in xray-monolith. Adds `set_mp_client_mode()` to suppress A-Life updates, `set_game_time()` for time sync, and GNS bridge bindings.

2. **GNS bridge DLL** — Wraps Valve's GameNetworkingSockets for Lua. Exposes init, host, connect, poll, send_reliable, send_unreliable to the Lua scripting layer.

3. **Lua sync layer** (6 .script files) — The actual multiplayer logic. Host captures events via engine callbacks, serializes them, broadcasts over GNS. Client receives, deserializes, and applies to local world.

### Entity ID Mapping

The hardest problem. When the host sends "entity 4200 spawned," the client can't use ID 4200 — its engine assigns its own IDs. So:

1. Host sends ENTITY_SPAWN with id=4200, section="stalker_bandit", position=(x,y,z)
2. Client stores a pending key: `"stalker_bandit_100_20_50" → 4200`
3. Client calls `alife():create("stalker_bandit", pos)` — engine assigns local ID 7831
4. Engine fires `server_entity_on_register` callback with the new se_obj (id=7831)
5. Client matches the pending key, creates mapping: host 4200 → local 7831
6. All future messages about entity 4200 resolve to local ID 7831

### Protocol

Text-based for Phase 1 (easy debugging). Events use `"MSG_TYPE|key=val|key=val"`. Position batches use `"EP|id,x,y,z,h;id,x,y,z,h"`. Reliable channel (TCP-like) for events, unreliable (UDP) for positions.

### Mod Compatibility

GAMMA has 400+ mods. We audited all 644 mod scripts and found 123 conflicts (25 critical). The biggest fix: `_g.script` defines global wrappers (`alife_create`, `alife_release`, etc.) that ~50 mods call. We patch these with `is_mp_client()` guards so they no-op on the client. This blocks entity lifecycle conflicts in one shot.

### Phases

- **Phase 0** (current): World sync. Host A-Life broadcasts to client. Entities, weather, time.
- **Phase 1**: See each other. Render remote players as visible actors. Position interpolation. Equipment sync.
- **Phase 2**: Interact. Damage sync, item drops/pickup, crafting/trading as host RPCs.
- **Phase 3**: Dedicated server. Headless host, both players connect as clients.

---

## License

This project wraps Valve's GameNetworkingSockets (BSD-3). Engine patches are against themrdemonized's xray-monolith fork. GAMMA is a community modpack. We don't distribute any copyrighted game assets.
