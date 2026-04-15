# Adversarial Mod Conflict Audit — Claude Code Prompt

Paste everything below the line into Claude Code on Windows.

---

I'm building GAMMA Multiplayer — a multiplayer layer on top of STALKER GAMMA (400+ mods). My multiplayer code hooks into Anomaly's callback system and manipulates entities, saves, weather, and time. I need you to audit EVERY mod script in the GAMMA installation for conflicts with my MP code.

**This is a parallelizable task. You MUST use subagents to split the work.** There are ~358 mod folders with ~644 `.script` files. Split them into 7 batches of ~50 mods each and run them ALL simultaneously as parallel subagents (use the Task tool or spawn subshells). Each subagent scans its batch and writes results to a file. Then you merge all results into one final report.

## My Multiplayer Scripts

Read these 4 files first to understand exactly what we hook and call:
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync\mp_core.script`
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync\mp_protocol.script`
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync\mp_host_events.script`
- `C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\lua-sync\mp_client_state.script`

### Summary of what we hook and call

**Callbacks we register:**

| Callback | Who | Purpose |
|---|---|---|
| `actor_on_update` | mp_core | Main update loop (polling GNS, sending snapshots) |
| `server_entity_on_register` | mp_core (client), mp_host_events (host) | Spawn interception for ID mapping / entity tracking |
| `server_entity_on_unregister` | mp_host_events (host) | Entity untracking + broadcast despawn |
| `npc_on_death_callback` | mp_host_events (host) | Death event broadcast |
| `monster_on_death_callback` | mp_host_events (host) | Death event broadcast |
| `on_before_save_input` | mp_core (client) | Block saves to prevent corruption |
| `on_key_press` | mp_core (client) | Show tooltip on F5 (quicksave blocked) |

**Engine/API calls we make:**
- `alife():set_mp_client_mode(true/false)` — suppresses A-Life on client
- `alife():create()`, `alife():release()`, `alife():kill_entity()` — entity lifecycle on client
- `alife():object()`, `level.object_by_id()` — entity lookups
- `obj:force_set_position()`, `alife():teleport_object()` — position sync on client
- `level.set_weather()`, `level.set_game_time()`, `level.change_game_time()`, `level.set_time_factor()` — environment sync on client
- `SIMBOARD:get_smart_by_name()`, `SIMBOARD:assign_squad_to_smart()` — squad sync on client
- `gns.*` — networking (our custom DLL, no conflicts possible)

**Critical state:**
- Client A-Life is SUPPRESSED — `alife()` update loop does not run on the client
- Client saves are BLOCKED — `on_before_save_input` returns false
- Bidirectional ID mapping table: `_host_to_local` / `_local_to_host` in mp_client_state
- Entity tracking registry: `_tracked_entities` table in mp_host_events (host only)

## Parallel Audit Architecture

The GAMMA mods are at:
```
C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\Stalker_GAMMA\G.A.M.M.A\modpack_addons\
```

### Step 1: Enumerate and chunk

```powershell
$modsDir = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\Stalker_GAMMA\G.A.M.M.A\modpack_addons"
$allMods = Get-ChildItem -Directory $modsDir | Sort-Object Name
$totalMods = $allMods.Count
$chunkSize = [math]::Ceiling($totalMods / 7)
Write-Host "Total mods: $totalMods, Chunk size: $chunkSize"

# Create output directory for audit results
$auditDir = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\audit_results"
New-Item -ItemType Directory -Force -Path $auditDir | Out-Null

# Write chunk manifests
for ($i = 0; $i -lt 7; $i++) {
    $start = $i * $chunkSize
    $chunk = $allMods | Select-Object -Skip $start -First $chunkSize
    $chunk | ForEach-Object { $_.FullName } | Out-File "$auditDir\chunk_$i.txt" -Encoding UTF8
    Write-Host "Chunk $i: $($chunk.Count) mods (starting: $($chunk[0].Name))"
}
```

### Step 2: Launch 7 parallel subagents

**IMPORTANT: Launch these simultaneously, not sequentially.** Each subagent gets:
1. The shared context (our MP callbacks/calls listed above)
2. Its chunk manifest (list of mod folders to scan)
3. Instructions to write findings to `audit_results\findings_N.md`

Each subagent must do the following for every `.script` file in every mod folder in its chunk:

**Read the script file and check for these 8 conflict types:**

1. **Callback Collisions** — Does this script register any of our callbacks? (`server_entity_on_register`, `server_entity_on_unregister`, `npc_on_death_callback`, `monster_on_death_callback`, `on_before_save_input`, `on_key_press`, `actor_on_update`). If so: does it modify arguments (like `flags.ret_value`), consume/block events, or have load-order dependencies?

2. **Entity Lifecycle Interference** — Does this script call `alife():create()`, `alife():release()`, or `alife():kill_entity()` independently? Those entities won't be in our tracking table → ghost entities or missed despawns on clients.

3. **Position/Movement Override** — Does this script call `force_set_position()` or `teleport_object()`? Will fight our position sync on clients.

4. **Weather/Time Override** — Does this script call `level.set_weather()`, `level.change_game_time()`, `level.set_time_factor()`? Will conflict with our environment sync on clients.

5. **Save System Interference** — Does this script hook `on_before_save_input` or modify save behavior? Could conflict with our save blocker.

6. **SIMBOARD/Squad Manipulation** — Does this script call `SIMBOARD:assign_squad_to_smart()` or manipulate squads directly? Could conflict with our squad sync.

7. **Global Table Pollution** — Does this script overwrite functions in other scripts, monkey-patch globals, or write to shared tables we depend on?

8. **A-Life Dependency** — Does this script assume A-Life is always running? (e.g., iterates `alife()` objects on a timer, reads A-Life state in `actor_on_update`). Will malfunction on client where A-Life is suppressed.

**For each conflict found, the subagent writes:**

```
---
MOD: [mod folder name]
FILE: [script filename]
CONFLICT TYPE: [callback collision | entity lifecycle | position override | weather/time | save system | simboard | global pollution | alife dependency]
SEVERITY: [CRITICAL | HIGH | MEDIUM | LOW]
DETAILS: [What exactly the script does that conflicts]
OUR IMPACT: [What breaks in our MP code — be specific: host-side, client-side, or both]
FIX: [Specific mitigation — load order change, guard clause, wrapper function, or "acceptable for Phase 0"]
---
```

**Severity guide for subagents:**
- **CRITICAL**: Could crash the game, corrupt state, or prevent MP from functioning. (e.g., a mod that blocks `server_entity_on_register` callbacks from firing)
- **HIGH**: Will cause visible bugs in MP but won't crash. (e.g., a mod that spawns entities outside our tracking)
- **MEDIUM**: Minor sync issues or cosmetic problems in MP. (e.g., weather flicker from competing set_weather calls)
- **LOW**: Theoretical concern only, or client-side-only issue that's acceptable for Phase 0. (e.g., a mod that reads A-Life state for UI display — will show stale data on client, no harm)

**Subagent critical reminders:**
- READ THE ACTUAL FILES. Do not guess from filenames.
- Anomaly's callback system allows MULTIPLE registrations — they all fire. The question is whether any MODIFY shared state or arguments.
- Mods that ONLY conflict on the CLIENT side (where A-Life is suppressed) are generally LOW severity for Phase 0 — the client is a thin display layer, mod features that depend on A-Life simply won't work there, and that's expected.
- HOST-side conflicts are the serious ones.
- If a script has NO conflicts, skip it entirely — only report conflicts.

### Step 3: Merge results

After all 7 subagents complete, merge all `findings_N.md` files into one master report:

```powershell
$auditDir = "C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\audit_results"
$masterReport = "$auditDir\MASTER_AUDIT_REPORT.md"

# Merge all findings
$allFindings = @()
for ($i = 0; $i -lt 7; $i++) {
    $file = "$auditDir\findings_$i.md"
    if (Test-Path $file) {
        $allFindings += Get-Content $file -Raw
    }
}
```

Write the merged report with:
1. **Executive summary** — total conflicts by severity (CRITICAL / HIGH / MEDIUM / LOW)
2. **Critical conflicts** — full details, sorted by severity descending
3. **Conflict matrix** — which callbacks are shared by how many mods
4. **Action items** — specific code changes needed in our 4 MP scripts before deployment
5. **"Acceptable for Phase 0" list** — things that will be broken on client but don't matter yet

Save the master report to:
```
C:\Users\jonah\Documents\GitHub\stalker-gamma-online\gamma-mp\audit_results\MASTER_AUDIT_REPORT.md
```

### Pre-scan hints (I already found these — verify and expand)

Scripts hooking `server_entity_on_register` (CRITICAL — our spawn interception callback):
- `207- Mags Redux/wep_binder.script`
- `Anomaly Magazines Redux/wep_binder.script`
- `G.A.M.M.A. Artefacts Reinvention/zz_item_artefact.script`
- `G.A.M.M.A. ZCP 1.4 Balanced Spawns/sim_squad_scripted.script`
- `G.A.M.M.A. ZCP 1.4 Balanced Spawns/smart_terrain.script`
- `Warfare Patch/sim_squad_scripted.script`
- `ZCP 1.5d/sim_squad_scripted.script`
- `ZCP 1.5d/smart_terrain.script`

Read each of these FIRST, before the general audit, and report EXACTLY what they do in the callback and whether they could interfere with our ID mapping.

Scripts calling `alife():create()` or `alife():release()` (HIGH — untracked entities):
- `drx_da_main.script` (Dynamic Anomalies)
- `placeable_furniture.script` (Hideout Furniture)
- `surge_manager.script` (NPCs Die in Emissions)
- `axr_companions.script` (GAMMA UI)
- `guards_spawner.script` (Guards Spawner)
- `itms_manager.script` (Starter Items / Wildkins)
- `quickdraw.script` (Close Quarter Combat)
- And more — the full scan will find them all.

## Final deliverable

The `MASTER_AUDIT_REPORT.md` file with every conflict cataloged, every severity assigned, and every fix specified. This becomes the pre-deployment checklist. Do not deploy until every CRITICAL and HIGH item has a mitigation plan.
