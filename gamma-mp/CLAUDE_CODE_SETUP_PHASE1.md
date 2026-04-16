# Claude Code Prompt: Phase 1 — Player Visibility

Paste everything below the line into a fresh Claude Code session on Windows.

---

## Who You Are

You're picking up an active multiplayer mod project for STALKER GAMMA. The owner is Jonah. He works fast (28 commits in one day), does not want to be parented or told to go to bed, prefers direct technical communication, and expects you to read code before asking questions. Curses freely — match the energy.

## What This Is

Multiplayer fork of STALKER GAMMA (661K Discord members, 400+ mods). Host-authoritative A-Life sync — one machine runs the simulation, clients receive entity state over Valve's GameNetworkingSockets. The goal is "two dudes in the Zone."

## What's Done (Phase 0 — COMPLETE)

Phase 0 is fully built, deployed, and working:
- Entity sync (spawn/death/despawn/position) via A-Life callbacks
- Weather and time sync (every 5s)
- A-Life suppression on client via engine patch (`alife():set_mp_client_mode(true)`)
- Bidirectional entity ID mapping (host IDs ↔ client IDs via pending spawn key matching)
- Mod compatibility: metatable guard on `alife():create/release` blocks 400+ mod conflicts on client
- Save blocking on client (F5 + console `save` interception)
- Level transition handling (LEVEL_CHANGE message, client resets sync state)
- F10 in-game menu (host/connect/disconnect/status/shutdown)
- Full state streaming for new connections (50 entities/frame budget)
- 20Hz position snapshots (100 entities/frame, round-robin cursor)
- GNS bridge DLL wrapping Valve GameNetworkingSockets for Lua 5.1
- Distribution repo with pre-built binaries

## What's Next (Phase 1 — Player Visibility)

Phase 1 = "two players SEE each other." We spawn a puppet NPC for each remote player and sync position/heading/animation from the network.

### Read These Files First

Before doing ANYTHING, read these files in order:

1. `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\.claude\CLAUDE.md` — Full architecture, file map, cross-file call map, message types, callback registrations, entity ID mapping flow, client sync state machine. THIS IS YOUR MAP.

2. `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\docs\PHASE1_IMPLEMENTATION_MAP.md` — The complete Phase 1 plan: 16 atomic commits, dependency graph, discovery flags, risk register, mod conflicts. THIS IS YOUR EXECUTION PLAN.

3. `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\BUG_TRACKER.md` — Known bugs and their status.

## Architecture (30-second version)

The host IS singleplayer running normally. Our Lua code watches A-Life callbacks (spawn/death/despawn/position) and broadcasts events to clients over GNS. Clients suppress their local A-Life and apply the host's event stream. No client prediction, no reconciliation — host is authoritative.

### The Stack (bottom to top)

1. **Engine patches** (C++, xray-monolith fork) — `set_mp_client_mode`, `set_game_time`, `set_body_yaw`, GNS bridge bindings
2. **GNS Bridge DLL** (gns-bridge/) — Wraps Valve GNS for Lua 5.1/luabind
3. **Lua Sync Layer** (lua-sync/, 6 .script files) — Core state machine, protocol, host events, client state, alife guard, UI

### Key Files

| File | What It Does |
|------|-------------|
| `lua-sync/mp_core.script` | State machine, init/shutdown, main update loop on `actor_on_update`, save blocking, F10 keybind |
| `lua-sync/mp_protocol.script` | Text serialization `"MSG_TYPE\|key=val\|..."`, dispatch, send/broadcast helpers |
| `lua-sync/mp_host_events.script` | Host-side callbacks, entity tracking, 20Hz snapshots, full state streaming, environment sync |
| `lua-sync/mp_client_state.script` | Client-side event application, bidirectional ID mapping, sync state machine (IDLE→CLEANING→SYNCING→ACTIVE) |
| `lua-sync/mp_alife_guard.script` | Metatable patch on `alife():create/release` — blocks mod calls on client |
| `lua-sync/mp_ui.script` | F10 in-game menu |

### Machine Layout

```
C:\ANOMALY\bin\                    Engine exe + DLLs (AnomalyDX11AVX.exe is our patched build)
C:\GAMMA\                          GAMMA/MO2 install
C:\GAMMA\overwrite\gamedata\scripts\   MO2 overwrite — scripts go here
C:\Users\jonah\Documents\GitHub\stalker-gamma-online\   Source repo
```

## Engine Patch: SetBodyYaw (APPLIED, rebuild may be pending)

Three C++ files in xrGame were patched to add `game_obj:set_body_yaw(heading)`:
- `script_game_object.h` — declaration
- `script_game_object3.cpp` — implementation (writes `m_body.current.yaw` + `m_body.target.yaw`)
- `script_game_object_script3.cpp` — luabind registration

**Why**: `force_set_rotation()` gets overwritten by `UpdateCL` every frame. `set_desired_direction()` is gated behind `movement_type != eMovementTypeStand` — dead for standing NPCs. SetBodyYaw writes through the engine's own rotation pipeline. Setting target=current prevents the lerp in `CustomMonster_VCPU.cpp:36` from fighting us.

**Status**: Patch files in `engine-patch/`. Build prompt in `CLAUDE_CODE_REBUILD_DEPLOY.md`. Check if exe has been rebuilt by grepping for `set_body_yaw` string in `C:\ANOMALY\bin\AnomalyDX11AVX.exe`.

## Phase 1 Execution Order

```
Engine rebuild (if not done) → C1 → C5 → C2 → C3 → C6 → C7 → C8 → C4 → C10 → C9 → C11-C16
```

- **C1**: Extend PP message format (add heading, body_state, move_type)
- **C5**: Write mp_puppet.script (spawn/despawn puppet with companion infoportion)
- **C2**: Host sends enhanced PP
- **C3**: Client sends PP to host
- **C6**: Puppet position updates
- **C7**: Puppet heading (uses set_body_yaw)
- **C8**: Puppet animation state
- **C4**: Host relays all player positions
- **C10**: Mod conflict guards (surge patches)
- **C9**: INTEGRATION — wire puppet into client update loop = "see another player"
- **C11-C16**: Polish (interpolation, equipment visuals, edge cases, multi-client, filtering, deploy)

Each commit is atomic, testable, has rollback instructions. Do them ONE AT A TIME.

## Key Decisions Already Made

1. **Puppet mod protection**: `npcx_is_companion` infoportion protects against Dynamic Despawner (~30s kill without it), DNPCAV, and No Exos — all three check this infoportion. No mod patches needed for these.

2. **Surge protection**: Requires direct patches to `surge_manager.script` and `surge_rush_scheme_common.script`. Goes in MO2 overwrite.

3. **Heading sync**: Resolved via engine source reading. SetBodyYaw is the solution. C0 (spike test) was eliminated from the plan.

4. **Puppet section**: `stalker_sim_default_military_0` as default — guaranteed to exist in GAMMA. Fallback list for edge cases.

5. **Protocol**: Text-based for Phase 1 (easy debugging). Binary (MessagePack) swap planned for Phase 2.

## Open Discovery Flags

These are things we KNOW we don't know yet — must be resolved by running the code:

- **D2**: Which position API works on puppets without movement manager fighting us
- **D3**: Whether animation APIs (`set_body_state`, `set_movement_type`) work on AI-suppressed puppet
- **D4**: Exact API for reading actor body state and movement type
- **D5**: Best puppet section with full animation set
- **D8**: Whether puppet appears in `db.OnlineStalkers` (companion infoportion should protect)

## Global Helpers

```lua
_G.is_mp_client()  -- true if connected as client
_G.is_mp_host()    -- true if hosting
_G.is_mp_active()  -- true if either
```

Used by `_g.script` wrappers and mod patches to guard MP-sensitive code paths.

## Deploy

After modifying any .script file:
```powershell
cd C:\Users\jonah\Documents\GitHub\stalker-gamma-online
.\gamma-mp\deploy.ps1
```
Or manually copy from `gamma-mp\lua-sync\` to `C:\GAMMA\overwrite\gamedata\scripts\`.

## What NOT To Do

- Do NOT modify Phase 0 code unless fixing a bug. It works.
- Do NOT do a full engine rebuild unless you changed C++ files. Lua changes are script-only deploys.
- Do NOT skip reading CLAUDE.md and PHASE1_IMPLEMENTATION_MAP.md. They exist so you don't waste 50 tool calls rediscovering the architecture.
- Do NOT batch multiple commits together. One at a time, test, move on.
- Do NOT tell Jonah to go to bed, be careful, slow down, or take breaks.

## Your Task

Ask Jonah which commit to start on. If he says "just go" or "next one", check what's been done and pick up where the plan left off. Read the actual code before writing any code. Every commit must be atomic and correct.
