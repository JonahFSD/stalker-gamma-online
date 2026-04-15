# GAMMA Multiplayer — Agent Context

Read this ENTIRE file before doing anything. It's your map. Without it you'll grep blindly and waste 10 tool calls re-learning things.

## What This Is

Multiplayer mod for STALKER GAMMA (661K Discord members, 400+ mods). Host-authoritative A-Life sync — one machine runs the simulation, clients receive entity state over GameNetworkingSockets. Goal: "two dudes in the Zone."

## Owner

Jonah (jonahwelliott@gmail.com). Does not want to be parented or told to go to bed. Prefers direct, technical communication. Expects you to read code before asking questions.

## Architecture (30-second version)

The host IS singleplayer running normally. Our code watches A-Life callbacks (spawn/death/despawn/position) and broadcasts events to clients over Valve's GNS. Clients suppress their local A-Life (`set_mp_client_mode(true)`) and apply the host's event stream. No client prediction, no reconciliation — host is authoritative.

## Current Phase

**Phase 0**: Two instances see the same world. Entity spawn/death/despawn/position sync. Weather/time sync. No player-to-player visibility yet.

## Build State

All compiled and deployed:
- AnomalyDX11.exe (patched, copied to AVX slot for MO2): `C:\ANOMALY\bin\`
- gns_bridge.dll + 5 dependency DLLs: `C:\ANOMALY\bin\`
- 6 Lua .script files: `C:\GAMMA\overwrite\gamedata\scripts\`
- UI XML: `C:\GAMMA\overwrite\gamedata\configs\ui\`

---

## PIN — File Map (search-optimized)

Use this to jump directly to the right file. Don't grep for things that are listed here.

### Lua Sync Layer (`gamma-mp/lua-sync/`) — THE CORE

| File | Purpose | Key Functions | Key State |
|------|---------|---------------|-----------|
| `mp_core.script` | State machine, init/shutdown, update loop, save blocking, F10 keybind | `mp_init()`, `mp_host(port)`, `mp_connect(ip,port)`, `mp_activate_client_mode()`, `mp_on_connect_failed(reason)`, `mp_disconnect()`, `mp_update()`, `mp_on_connection_event(evt)`, `mp_shutdown()`, `block_client_saves()`, `restore_client_saves()`, `on_game_start()` | `_is_initialized`, `_is_host`, `_is_connecting`, `_is_client`, `_host_ip`, `_host_port` |
| `mp_protocol.script` | Message serialization, dispatch | `serialize_event(type,data)`, `serialize_positions(type,entities)`, `deserialize(str)`, `on_message(conn_id,raw,size)`, `dispatch_client(type,data,conn)`, `dispatch_host(type,data,conn)`, `send_event()`, `broadcast_event()`, `send_snapshot()`, `broadcast_snapshot()` | `MSG` table (ES/ED/ER/SA/IC/WS/TS/FS/PE/EP/PP/PS) |
| `mp_host_events.script` | Host-side: hooks callbacks, tracks entities, broadcasts events+snapshots, streams full state, handles level transitions | `register_callbacks()`, `unregister_callbacks()`, `build_entity_registry()`, `on_entity_register(se_obj,source_tag)`, `on_entity_unregister(se_obj)`, `on_npc_death(npc,killer)`, `send_snapshots()`, `send_environment_sync()`, `send_full_state(conn_id)`, `tick_full_state()`, `cancel_full_state(conn_id)`, `on_host_level_load()` | `_tracked_entities` (id->true), `_tracked_count`, `_tracked_ids` (flat array), `_tracked_id_index` (id->pos), `_snapshot_cursor` (round-robin), `_full_state_pending` (conn->state), `_connected_clients`, `_last_level_name` |
| `mp_client_state.script` | Client-side: applies host events, ID mapping, sync state machine | `resolve_id(host_id)`, `map_id(host,local)`, `unmap_id(host)`, `on_local_entity_registered(se_obj)`, `on_entity_spawn(data)`, `do_entity_spawn(data)`, `on_entity_death(data)`, `on_entity_despawn(data)`, `on_entity_positions(entities)`, `apply_entity_position(host_id,x,y,z,h)`, `on_full_state(data)`, `client_tick()`, `tick_cleanup()`, `tick_sync()` | `_host_to_local`, `_local_to_host`, `_network_entities`, `_pending_spawns` (key->list), `_pending_positions`, `_sync_state` (IDLE/CLEANING/SYNCING/ACTIVE), `_cleanup_ids`, `_spawn_queue` |
| `mp_alife_guard.script` | Intercepts alife():create()/release() on client (Bug #11) | `install()`, `uninstall()`, `internal_create(sim,...)`, `internal_release(sim,...)`, `get_block_counts()` | `_orig_create`, `_orig_release`, `_installed` |
| `mp_ui.script` | F10 in-game menu (Host/Connect/Disconnect/Status/Shutdown) | `UIMultiplayerMenu:InitControls()`, `OnHost()`, `OnConnect()`, `OnDisconnect()`, `OnStatus()`, `OnShutdown()`, `open_menu()`, `close_menu()` | `GUI` singleton |

### UI Layout

| File | Purpose |
|------|---------|
| `gamma-mp/lua-sync/ui/ui_mp_menu.xml` | XML layout for F10 menu — 400x340 panel, IP/port inputs, 7 buttons |

### GNS Bridge DLL (`gamma-mp/gns-bridge/`)

| File | Purpose | Key Exports |
|------|---------|-------------|
| `gns_bridge.h` | C API header | `gns_init()`, `gns_host(port)`, `gns_connect(ip,port)`, `gns_disconnect()`, `gns_send_reliable(conn,data,size)`, `gns_send_unreliable(conn,data,size)`, `gns_poll(msgs,max)`, `gns_poll_connection_events(evts,max)`, `gns_get_client_count()` |
| `gns_bridge.cpp` | Implementation — wraps Valve GNS | Connection state machine in `OnConnectionStatusChanged`. Events: CONNECTED=1, DISCONNECTED=2, REJECTED=3. `gns_connect()` is ASYNC (returns 0 = "initiated", not "connected"). Broadcast: conn_id=-1. Max message: 64KB. |
| `gns_bridge_luabind.cpp` | Engine integration — loads DLL, registers `gns.*` namespace in Lua | `LoadGnsBridge()` uses `GetModuleFileNameA` for absolute path. Registers all gns_* functions under Lua `gns` namespace via luabind. |
| `gns_bridge_poll.cpp` | Lua-friendly poll wrappers | Returns Lua tables from `gns.poll()` and `gns.poll_events()` |

### Engine Patches (`gamma-mp/engine-patch/`) — 4 patches, all applied

| File | What It Does |
|------|--------------|
| `alife_update_manager.h.patch` | Adds `m_mp_client_mode` bool + setter/getter to CALifeUpdateManager |
| `alife_update_manager.cpp.patch` | Guards `update()` and `shedule_Update()` with early return when `m_mp_client_mode`. Constructor init to false. |
| `alife_simulator_script.cpp.patch` | Lua bindings: `alife():set_mp_client_mode(bool)`, `alife():mp_client_mode()` |
| `level_script.cpp.patch` | `level.set_game_time(h,m,s)` — absolute time set for MP sync (engine only has `change_game_time` which is delta-only). Handles backward time via 24h wraparound. |

### Docs & Prompts (`gamma-mp/`)

| File | Purpose |
|------|---------|
| `BUG_TRACKER.md` | All 15 identified bugs with severity, status, file locations, and fixes. READ THIS FIRST when resuming bug work. |
| `SETUP_GUIDE.md` | End-to-end setup guide for other players |
| `docs/BUILD_GUIDE.md` | How to build the engine + DLL from source |
| `docs/DISCOVERIES.md` | Engine internals discovered during development |
| `CLAUDE_CODE_PROMPT.md` | Full setup from scratch |
| `CLAUDE_CODE_BUILD_DX11.md` | Build DX11 exe |
| `CLAUDE_CODE_DEPLOY.md` | Deploy all files to GAMMA |
| `CLAUDE_CODE_DEPLOY_MENU.md` | Deploy F10 menu files |
| `CLAUDE_CODE_PATCH_AND_REDEPLOY.md` | Patch _g.script + redeploy |
| `CLAUDE_CODE_TEST.md` | In-game test protocol |
| `CLAUDE_CODE_MOD_AUDIT.md` | Parallel adversarial mod audit |
| `audit_results/MASTER_AUDIT_REPORT.md` | 123 conflicts across 80 mods (25 CRIT, 38 HIGH) |
| `deploy.ps1` | One-command deploy: copies all scripts + UI XML to GAMMA overwrite |
| `TEST_CHECKLIST.md` | Post-deploy smoke test checklist |
| `CLAUDE_CODE_SETUP_INFRA.md` | Infrastructure setup prompt for new Claude Code sessions |

### Machine Layout

```
C:\ANOMALY\bin\           Engine exe + DLLs (AnomalyDX11AVX.exe is our patched build)
C:\GAMMA\                 GAMMA/MO2 install
C:\GAMMA\overwrite\       MO2 overwrite folder — scripts and UI go here
C:\Users\jonah\Documents\GitHub\stalker-gamma-online\  Source repo
```

---

## Cross-File Call Map

```
mp_core.mp_update()  [every frame, actor_on_update callback]
  ├── gns.poll_events() → mp_on_connection_event(evt)
  │     ├── EVENT_CONNECTED + host → mp_host_events.send_full_state(conn_id)
  │     ├── EVENT_CONNECTED + connecting → mp_activate_client_mode()
  │     ├── EVENT_DISCONNECTED + client → mp_disconnect()
  │     └── EVENT_REJECTED + connecting → mp_on_connect_failed(reason)
  ├── gns.poll() → mp_protocol.on_message(conn_id, data, size)
  │     ├── client → dispatch_client() → mp_client_state.on_entity_*()
  │     └── host → dispatch_host() → mp_host_events.on_client_player_*()
  ├── [client] mp_client_state.client_tick()
  │     ├── STATE_CLEANING → tick_cleanup() (50 releases/frame)
  │     └── STATE_SYNCING → tick_sync() (20 spawns/frame)
  ├── [host] mp_host_events.tick_full_state() (every frame, streams 50 spawns/frame to new clients)
  └── [host] mp_host_events.send_snapshots() (20Hz, 100 entities via round-robin cursor)
        ├── mp_protocol.broadcast_snapshot(ENTITY_POS, entities)
        ├── mp_protocol.broadcast_snapshot(PLAYER_POS, actor)
        └── [every 5s] send_environment_sync() → broadcast WEATHER_SYNC + TIME_SYNC
```

## Entity ID Mapping Flow

```
1. Host sends ENTITY_SPAWN with id=4200, section="stalker_bandit", pos=(100.5, 20.3, 50.7)
2. mp_client_state.do_entity_spawn():
   - Builds key: "stalker_bandit_100.5000_20.3000_50.7000"
   - Stores: _pending_spawns[key] = { 4200 }  (FIFO list)
   - Calls: alife():create("stalker_bandit", pos, lvid, gvid)
3. Engine fires server_entity_on_register SYNCHRONOUSLY with se_obj.id=7831
4. mp_core.on_client_entity_registered(se_obj) → mp_client_state.on_local_entity_registered(se_obj)
   - Rebuilds key from se_obj:section_name() + se_obj.position
   - Pops 4200 from _pending_spawns[key] list
   - Maps: _host_to_local[4200] = 7831, _local_to_host[7831] = 4200
   - Flushes any _pending_positions[4200] (Bug #13 fix)
5. All subsequent messages: host ID 4200 → resolve_id() → local ID 7831
```

## Client Sync State Machine

```
IDLE → [on_full_state()] → CLEANING → [all deleted] → SYNCING → [queue drained] → ACTIVE
         collects all         releases 50/frame        processes 20 spawns/frame
         entity IDs           from _cleanup_ids         from _spawn_queue
```

## Message Types (mp_protocol MSG table)

| Code | Name | Channel | Direction | Purpose |
|------|------|---------|-----------|---------|
| ES | ENTITY_SPAWN | reliable | host→client | New entity created |
| ED | ENTITY_DEATH | reliable | host→client | Entity killed (with killer context) |
| ER | ENTITY_DESPAWN | reliable | host→client | Entity released from world |
| SA | SQUAD_ASSIGN | reliable | host→client | Squad assigned to smart terrain |
| WS | WEATHER_SYNC | reliable | host→client | Weather preset |
| TS | TIME_SYNC | reliable | host→client | Game time + time factor |
| FS | FULL_STATE | reliable | host→client | Initial state marker (entity_count) |
| EP | ENTITY_POS | unreliable | host→client | Batch position snapshot |
| PP | PLAYER_POS | unreliable | both | Player position |
| PE | PLAYER_EQUIP | reliable | both | Player equipment (Phase 2) |
| PS | PLAYER_STATS | unreliable | client→host | Health, armor (Phase 2) |
| IC | INVENTORY_CHANGE | reliable | host→client | Item pickup/drop (Phase 2) |
| LC | LEVEL_CHANGE | reliable | host→client | Host changed level — client resets to IDLE |

## Callback Registrations

| When | Callback | Handler | File |
|------|----------|---------|------|
| `on_game_start` | `actor_on_update` | `mp_core.mp_update` | mp_core |
| `on_game_start` | `on_console_execute` | `mp_core.on_console_execute` | mp_core |
| `on_game_start` | `on_key_press` | `mp_core.on_mp_key_press` (F10) | mp_core |
| `mp_host()` | `server_entity_on_register` | `mp_host_events.on_entity_register` | mp_host_events |
| `mp_host()` | `server_entity_on_unregister` | `mp_host_events.on_entity_unregister` | mp_host_events |
| `mp_host()` | `npc_on_death_callback` | `mp_host_events.on_npc_death` | mp_host_events |
| `mp_host()` | `monster_on_death_callback` | `mp_host_events.on_monster_death` | mp_host_events |
| `mp_host()` | `on_game_load` | `mp_host_events.on_host_level_load` | mp_host_events |
| `mp_activate_client_mode()` | `server_entity_on_register` | `mp_core.on_client_entity_registered` | mp_core |
| `block_client_saves()` | `on_before_save_input` | `mp_core.block_save_attempt` | mp_core |
| `block_client_saves()` | `on_key_press` | `mp_core.on_client_key_press` (F5 msg) | mp_core |
| `on_game_start` | — | `mp_alife_guard.install()` | mp_alife_guard |

## Global Helpers (registered in on_game_start)

```lua
_G.is_mp_client()  -- true if connected as client
_G.is_mp_host()    -- true if hosting
_G.is_mp_active()  -- true if either
```

Used by `_g.script` wrappers and mod patches to guard MP-sensitive code paths.

## Technical Notes

- Engine uses Lua 5.1 (NOT LuaJIT) — no FFI
- Lua bindings use luabind: `module(L, "namespace") [ def("func", &func) ]`
- Engine fork: themrdemonized/xray-monolith, branch `all-in-one-vs2022-wpo`
- GNS default port: 44140 (UDP+TCP)
- Snapshot rate: 20Hz (50ms), 100 entities/frame via round-robin cursor over indexed array
- Protocol: text-based (`"MSG_TYPE|key=val|..."` for events, `"EP|id,x,y,z,h;..."` for positions)
- `alife():create()` fires `server_entity_on_register` SYNCHRONOUSLY (confirmed via engine source)
- `alife():release(se_obj, true)` — offline entities release synchronously, online entities async via GE_DESTROY
- MO2 virtual filesystem: overwrite folder layers on top of all mods
- GAMMA defaults to `AnomalyDX11AVX.exe` — our patched build is copied into this slot

## Current State (Phase 0 — COMPLETE)

Working and deployed:
- Entity sync (spawn/death/despawn/position) — host A-Life broadcasts to client
- Weather and time sync (every 5s)
- A-Life suppression on client via engine patch
- Bidirectional entity ID mapping (host IDs ↔ client IDs)
- Mod compatibility: metatable guard blocks 400+ mod conflicts, source tag filtering, _g.script wrappers
- Save blocking on client (both F5 and console `save`)
- Level transition handling (LEVEL_CHANGE message, client resets to IDLE)
- F10 in-game menu (host/connect/disconnect/status/shutdown)
- Full state streaming for new connections (50 entities/frame budget)
- 20Hz position snapshots (100 entities/frame, round-robin)
- Distribution repo: github.com/JonahFSD/gamma-mp-release (pre-built binaries + one-click installer)
- Host networking: Windows firewall rules + AT&T BGW210-700 port forwarding on 44140 TCP/UDP

## Full Co-Op Roadmap (everything short of dedicated server)

### Phase 1: Player Visibility
- Spawn puppet stalker entity for remote player
- Position interpolation between 20Hz snapshots (smooth movement)
- Correct outfit/armor visual display
- Correct weapon in hands
- Walk/run/crouch/idle/sprint animations matching actual movement
- Head direction tracking
- **Status: Phase 1 audit prompt written, not yet run**

### Phase 2: Combat & Damage
- Damage sync on NPCs/mutants (both players can shoot the same target)
- Damage aggregation on host (host-authoritative hit registration)
- Player health/radiation/bleeding sync
- Friendly fire between players (configurable, default off)
- Player death and respawn handling
- Mutant/NPC attacks on remote player puppet → damage to actual client

### Phase 3: Inventory & Economy
- Loot sync — looting a body removes items for both players
- Item drops visible to both players
- Drop-and-grab item sharing between players
- Artifact pickup sync from anomaly fields
- Trader inventory (host-authoritative, NPCs live on host)
- Money/economy sync
- Shared stash access
- Campfire cooking, weapon repair, crafting as host RPCs

### Phase 4: World Integration
- PDA map sync — see friend's position on map
- Quest awareness (shared markers at minimum)
- Independent level transitions (host in Rostok, client in Garbage)
- Reconnection handling (client crash → rejoin → full state re-stream)
- Client inventory/stats persistence between sessions (save client state separately)

### Phase 5: Communication & Polish
- Text chat through MP menu (new message type through GNS)
- Proximity-based VOIP (Opus codec → unreliable GNS → OpenAL with distance scaling) — stretch goal
- UI polish, status indicators, player nameplates

### Phase FINAL: Dedicated Server (not in current scope)
- Headless host, no renderer, `--dedicated` launch flag
- Both players connect as clients
- Same sync code, skip graphics init