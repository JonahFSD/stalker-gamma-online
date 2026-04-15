# GAMMA Multiplayer Mod Conflict Audit - Master Report

**Date:** 2026-04-15
**Scope:** 358 mod folders, 644 .script files
**Auditor:** 7 parallel subagents scanning all scripts against 4 MP modules

---

## Executive Summary

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 25 | Will crash the game, corrupt entity state, or prevent MP from functioning |
| HIGH | 38 | Will cause visible bugs in MP but won't crash |
| MEDIUM | 37 | Minor sync issues, cosmetic problems, or task/quest desync |
| LOW | 23 | Theoretical concern only, or client-side-only issue acceptable for Phase 0 |
| **TOTAL** | **123** | Across ~80 unique mod scripts |
| CLEAN | ~278 | Mods with no .script files or no MP-relevant conflicts |

### Top 3 Systemic Issues

1. **`flags.ret` vs `flags.ret_value` -- CLIENT SAVES ARE NOT BLOCKED.** Our `block_save_attempt()` sets `flags.ret_value = false` but the GAMMA MCM dispatcher reads `flags.ret`. Additionally, `exec_console_cmd("save")` in Sleep Balance and YACS bypasses our hook entirely. **Fix this before any testing.**

2. **Untracked entity lifecycle calls everywhere.** 50+ scripts call `alife():create()`, `alife_release()`, or `alife_create_item()` outside our entity tracking. On the host, these entities are invisible to clients. On the client, they crash or create ghost entities. A global wrapper in `_g.script` is the single choke point for a fix.

3. **ZCP/SIMBOARD is the backbone of GAMMA.** ZCP 1.4 and 1.5d replace `sim_squad_scripted.script` and `smart_terrain.script` which directly fire `SendScriptCallback("server_entity_on_register")`. Every squad and smart terrain registration triggers our ID-mapping on the client, corrupting the mapping table with host-only entities.

---

## Critical Conflicts (25)

### OUR OWN BUG: Save Blocker Field Mismatch

```
MOD: (our code) mp_core.script
FILE: mp_core.script:186-191
CONFLICT TYPE: Save System
SEVERITY: CRITICAL
DETAILS: block_save_attempt() sets flags.ret_value = false. The GAMMA MCM
dispatcher (ui_main_menu.script) checks flags.ret, not flags.ret_value.
Our save blocker is a no-op.
FIX: Change mp_core.script line 190 to: flags.ret = false
     Also intercept exec_console_cmd("save") on the client.
```

### ZCP / Simulation Board (6 CRITICAL)

```
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: sim_squad_scripted.script
CONFLICT TYPE: Callback Collision + SIMBOARD + Entity Lifecycle
SEVERITY: CRITICAL
DETAILS: on_register() fires SendScriptCallback("server_entity_on_register", self, "sim_squad_scripted").
         Extensive SIMBOARD mutations. smr_pop calls alife_create/release for squad spawning.
OUR IMPACT: Corrupts client ID-mapping table. alife calls crash on client.
FIX: Filter source_tag "sim_squad_scripted" in our client-side server_entity_on_register handler.
     Gate all smr_pop spawn/release behind is_mp_client().

MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: smart_terrain.script
CONFLICT TYPE: Callback Collision + SIMBOARD
SEVERITY: CRITICAL
DETAILS: on_register() fires SendScriptCallback("server_entity_on_register", self, "se_smart_terrain").
OUR IMPACT: Floods our client-side entity tracking with smart terrain objects.
FIX: Filter source_tag "se_smart_terrain" in our client handler.

MOD: ZCP 1.5d
FILE: sim_squad_scripted.script
SEVERITY: CRITICAL
DETAILS: Same as ZCP 1.4 plus civil war squad-setup injection in create_squad().
FIX: Same filtering + gate civil war setup behind host-only.

MOD: ZCP 1.5d
FILE: smart_terrain.script
SEVERITY: CRITICAL
DETAILS: Same as ZCP 1.4 smart_terrain.
FIX: Same filtering.

MOD: ZCP 1.5d
FILE: game_setup.script
SEVERITY: CRITICAL
DETAILS: actor_on_update iterates SIMBOARD.squads, calls squad:remove_squad().
         actor_on_first_update: 65534-ID scan + alife():release() + alife():teleport_object().
         One-time guard flag in save state = re-runs on client every session.
FIX: Gate entire actor_on_first_update and squad-removal block behind is_mp_client().

MOD: Warfare Patch
FILE: sim_squad_scripted.script
SEVERITY: CRITICAL
DETAILS: Full class replacement. Fires SendScriptCallback same as ZCP.
FIX: Same source_tag filtering approach.
```

### Magazines Redux System (6 CRITICAL)

```
MOD: Anomaly Magazines Redux
FILE: magazines.script
CONFLICT TYPE: Callback Collision (actor_on_update)
SEVERITY: CRITICAL
DETAILS: actor_on_update polls enhanced_animations.used_item every tick.
         On client, nil-index crashes the entire update chain.
         on_key_press sets flags.ret_value = false, blocking all reloads.
FIX: Nil-guard enhanced_animations.used_item. Add is_client() early return to reload block.

MOD: Anomaly Magazines Redux
FILE: magazines.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: CRITICAL
DETAILS: alife_create_item called on every weapon reload/unjam. Unconditional.
FIX: Wrap all alife_create_item in is_host() guard.

MOD: Anomaly Magazines Redux
FILE: magazines_loot.script
CONFLICT TYPE: Callback Collision + Entity Lifecycle
SEVERITY: CRITICAL
DETAILS: npc_on_death_callback spawns magazine items via alife_create_item on every NPC death.
FIX: Add is_client() guard around alife_create_item.

MOD: Anomaly Magazines Redux
FILE: magazines_loot.script
CONFLICT TYPE: Global Table Pollution
SEVERITY: CRITICAL
DETAILS: Permanently replaces death_manager.set_weapon_drop_condition.
         Calls itm:unload_magazine() and random_pop_mag() on every weapon death-drop.
FIX: Add is_host() guard inside replacement body.

MOD: ATHI's Mags Redux Mod Madness
FILE: magazines_loot.script
SEVERITY: CRITICAL
DETAILS: Duplicate of Anomaly Magazines Redux npc_on_death + death_manager patches.
         Double-registration = death logic fires twice.
FIX: Same is_host() guards. Ensure only one magazines_loot.script is active.
```

### Entity Lifecycle (7 CRITICAL)

```
MOD: 234- Dynamic Anomalies Overhaul
FILE: drx_da_main.script
SEVERITY: CRITICAL
DETAILS: actor_on_update loop (100ms) calls alife():create() and alife():release() directly.
         Runs on every client tick = persistent crash/orphan entities.
FIX: Guard drx_da_actor_on_update_callback with if is_mp_client() then return end.

MOD: G.A.M.M.A. Dynamic Despawner
FILE: grok_dynamic_despawner.script
SEVERITY: CRITICAL
DETAILS: Every ~43s iterates online NPCs and calls alife_release() on threshold-exceeding NPCs.
         Runs on ALL peers independently = double-free corruption. 12+ undeclared globals.
FIX: Gate entire despawn logic behind is_host(). Localize all globals. Consider disabling in MP.

MOD: G.A.M.M.A. UI
FILE: axr_companions.script
SEVERITY: CRITICAL
DETAILS: Four conflict vectors: alife_create (squad spawn), teleport_object (unstuck),
         SIMBOARD:setup_squad_and_group, server_entity_on_unregister callback collision.
FIX: Gate all alife/SIMBOARD calls behind is_host(). Disable companion_unstuck on client.

MOD: G.A.M.M.A. Artefacts Reinvention
FILE: zz_item_artefact.script
SEVERITY: CRITICAL
DETAILS: Overrides se_artefact.on_register/on_unregister on the SE class.
         Manually fires SendScriptCallback. actor_on_update iterates cond_t with alife_object().
         Calls alife_create_item/alife_release for artefact container break/assemble.
FIX: Guard entity_unregister_plan_b with is_client() return. Gate alife calls to host-only.

MOD: G.A.M.M.A. Artefacts Reinvention
FILE: perk_based_artefacts.script
SEVERITY: CRITICAL
DETAILS: sim:release() kills monsters bypassing our death broadcast.
         alife_create_item for loot drops. Anonymous actor_on_update closures leak memory.
FIX: Gate sim:release() and alife_create_item to host only. Replace anonymous closures.

MOD: G.A.M.M.A. Alife fixes
FILE: alife_storage_manager.script
SEVERITY: CRITICAL
DETAILS: Migration path iterates 65534 A-Life slots. CALifeStorageManager_before_save
         is a direct engine callback our save hook cannot intercept.
FIX: Add if mp_is_client then return end at top of on_after_load_state().

MOD: 294- Autolooter
FILE: z_auto_looter.script
SEVERITY: CRITICAL
DETAILS: handle_delete calls sim:release(sim:object()) -- crashes on nil or releases
         host-owned entities from the client.
FIX: Wrap handle_delete body in if not is_client() then.
```

### Other CRITICAL (5)

```
MOD: G.A.M.M.A. Radiation Dynamic Areas
FILE: gamma_dynamic_radiation_areas_from_arzsi.script
SEVERITY: CRITICAL
DETAILS: on_game_load spawns anomaly entities via alife():create() loop. Unguarded _G globals.
FIX: Wrap spawn_radiation_fields in is_host() guard. Localize globals.

MOD: G.A.M.M.A. Miracle Machine Remake
FILE: release_restr_in_x16.script
SEVERITY: CRITICAL
DETAILS: 65534-ID scan + alife_release on game load. No host guard.
FIX: Gate behind is_host().

MOD: G.A.M.M.A. Snipers Remover
FILE: grok_sniper_remover.script
SEVERITY: CRITICAL
DETAILS: actor_on_update + unilateral alife():release() calls.
FIX: Guard behind is_host().

MOD: G.A.M.M.A. Rostok Mutant Arena Remover
FILE: z_ph_door_bar_arena_remover.script
SEVERITY: CRITICAL
DETAILS: alife_release_id on actor_on_first_update + monkey-patches ph_door globally.
FIX: Gate behind is_host().

MOD: G.A.M.M.A. Vehicles in Darkscape
FILE: grok_vehicles_spawner.script
SEVERITY: CRITICAL
DETAILS: Direct alife():create() for 25+ vehicles on actor_on_first_update. Unscoped globals.
FIX: Wrap behind is_mp_client guard. Convert globals to local.

MOD: G.A.M.M.A. YACS no quit
FILE: ish_campfire_saving.script
SEVERITY: CRITICAL
DETAILS: on_before_save_input uses flags.ret = true (matches engine but conflicts with our code).
         Shift+F5 calls exec_console_cmd("save") directly, bypassing our block.
FIX: On client, short-circuit on_before_save_input. Disable create_emergency_save on client.

MOD: Dark Valley Lamp Remover
FILE: dark_valley_lamp_remover.script
SEVERITY: CRITICAL
DETAILS: 65534-ID iteration + alife_release_id on actor_on_first_update.
FIX: Guard with is_client() return.

MOD: Agroprom Underground Remake
FILE: agroprom_drugkit_spawner_gamma.script
SEVERITY: CRITICAL
DETAILS: alife_create_item on actor_on_first_update with hardcoded vertex IDs.
FIX: Guard with is_client() return.
```

---

## Callback Collision Matrix

How many mods register each of our 7 callbacks:

| Callback | Mod Count | Risk Level |
|----------|-----------|------------|
| `actor_on_update` | 40+ | HIGH - Most are benign HUD/animation. ~15 call alife() or SIMBOARD. |
| `server_entity_on_register` | 6 | CRITICAL - ZCP 1.4, ZCP 1.5d, Warfare Patch fire it from class overrides. Artefacts Reinvention overrides SE class. |
| `server_entity_on_unregister` | 10 | HIGH - Mags Redux (2x), Guards Spawner, Mark Switch, Shaders pack, axr_companions, ZCP, tasks_guide |
| `npc_on_death_callback` | 15+ | HIGH - Magazines loot, death_manager, ZCP smr_loot, Bounty Squads, Stealth, Kill Tracker, Loot Claim, Disguise, tasks |
| `monster_on_death_callback` | 8 | MEDIUM - Kill Tracker, Loot Claim, tasks (baba_yaga, house_of_horrors, brain_game, etc.) |
| `on_before_save_input` | 3 | CRITICAL - YACS, Cooking Overhaul, Cars Fixes. Field name mismatch: flags.ret vs flags.ret_value. |
| `on_key_press` | 20+ | LOW - Most are cosmetic (NVG, aim, sprint, melee). Only Autolooter triggers destructive entity ops. |

---

## High Conflicts (38) -- Summary Table

| Mod | File | Conflict Type |
|-----|------|---------------|
| 207- Mags Redux | magazines.script | Callback + Entity Lifecycle (server_entity_on_unregister x2) |
| 207- Mags Redux | magazines_loot.script | npc_on_death + alife_create_item |
| 207- Mags Redux | actor_stash_patch.script | alife_create (backpack stash) |
| Anomaly Magazines Redux | mags_patches.script | 5 monkey-patches of item_parts/item_weapon |
| Anomaly Magazines Redux | magazines_loot.script | trader_autoinject monkey-patch |
| ATHI Mags Redux | actor_stash_patch.script | alife_create + alife_release (stash) |
| Autolooter | z_auto_looter.script | on_key_press triggers destructive pipeline |
| Autolooter fix | zzzz_auto_looter_fix_by_kdvfirehawk.script | handle_disassemble monkey-patch |
| 234- Dynamic Anomalies | drx_da_main.script | level.change_game_time (Flash anomaly) |
| 234- Dynamic Anomalies | drx_da_main.script | actor_on_update A-Life dependency |
| 245- Hideout Furniture | placeable_furniture.script | alife_create (furniture placement) |
| 245- Hideout Furniture | bind_workshop_furniture.script | alife_create (workshop stash) |
| 265- NPCs Die in Emissions | surge_manager.script | alife_release + alife_create (zombie conversion) |
| 265- NPCs Die in Emissions | zz_surge_manager_npc_die.script | Monkey-patch + alife_release |
| 203- YACS Campfire Saves | ish_campfire_saving.script | flags.ret mismatch (save blocker) |
| 225- Placeable Campfires | campfire_placeable.script | alife_create + change_game_time |
| 248- Night Mutants | night_mutants.script | SIMBOARD:create_squad in actor_on_update |
| 156- No Exos in the South | grok_nes.script | alife():release() in npc_on_update |
| 156- No Exos in the South | grok_no_north_faction.script | alife():release() in npc_on_update |
| Artefacts Reinvention | grok_artefacts_random_spawner.script | alife():create() + sim:actor() nil crash |
| Artefacts Reinvention | exo_loot.script | death_manager.spawn_cosmetics monkey-patch |
| Artefacts Reinvention | dialogs_agr_u.script | alife():actor() nil + alife_release |
| Arti Recipes Overhaul | zzzz_arti_jamming_repairs.script | Raw alife():register() pattern |
| AI Rework | xr_conditions.script | 30+ unguarded SIMBOARD reads |
| Better Quick Release System | item_backpack.script | alife_create/release stash flow |
| Darkasleif's Cars Fixes | LevelChangeCars.script | flags.ret save field mismatch |
| Cooking Overhaul | campfire_placeable.script | 65534-scan + alife_release + change_game_time |
| Cooking Overhaul | bind_campfire.script | on_before_save_input flags.ret conflict |
| Close Quarter Combat | quickdraw.script | Raw alife():create()/release() |
| Bounty Squads Rework | sim_squad_bounty.script | SIMBOARD:create_squad + force_set_goodwill |
| Economy | TB_RF_Receiver_Packages.script | alife_create (hostile NPC spawn) |
| Economy | death_manager.script | Extensive alife_create_item in loot generation |
| Lottery Rebalance | dialogs_mlr.script | alife + SIMBOARD + teleport_object |
| Books Pass Time | Wait.script | level.change_game_time |
| G.A.M.M.A. UI | item_cooking.script | alife_release + alife_create_item (cooking) |
| Quests Rebalance | xr_effects.script | alife_create + set_weather + SIMBOARD |
| Short Psi Storms | psi_storm_manager.script | level.set_time_factor (overwrites sync) |
| Sleep Balance | ui_sleep_dialog.script | change_game_time + exec_console_cmd("save") bypass |
| Starter items not broken | itms_manager.script | alife_release at session start |
| Starting Loadouts | grok_remove_knife_ammo.script | alife_release_id at session start |
| ZCP 1.4 | smr_loot.script | npc_on_death + alife_create_item |
| ZCP 1.4 | bind_anomaly_field.script | alife_create anomaly spawn |
| ZCP 1.4 | game_setup.script | SIMBOARD + alife_release + alife_create_item |
| ZCP 1.4 | bind_awr.script | npc_on_death mechanic lamp toggle |
| Recruitable Companions | stalker_cloning_utility.script | alife_create + SIMBOARD + alife_release |
| Rostok CLOSER | lc_custom.script | alife():create() + TeleportObject + SIMBOARD |
| Weapon Pack | close_combat_weapons_launchers.script | npc_on_death + npc_on_choose_weapon |
| Kill Tracker | ish_kill_tracker.script | npc_on_death + monster_on_death |
| Teivaz Quick Melee | quickdraw.script | alife():create()/release() on key press |
| Wildkins Ammo Parts | itms_manager.script | Full itms_manager replacement with alife():create() |
| Rare Stashes Balance | treasure_manager.script | alife_create_item on corpse loot |
| xcvb's Guards Spawner | guards_spawner.script | SIMBOARD:create_squad + server_entity_on_unregister |
| Pre-0.9.3.1 Saves Fix | tasks_mirage.script | set_actor_position fights position sync |
| ZCP 1.5d | smr_loot.script | npc_on_death + alife_create_item loot |
| ZCP 1.5d | smr_pop.script | SIMBOARD:create_squad + alife_release_id |

---

## Action Items for MP Scripts Before Deployment

### 1. FIX OUR SAVE BLOCKER (Priority 0 -- do this now)

In `mp_core.script:186-191`, change:
```lua
-- BEFORE (broken):
function block_save_attempt(flags)
    if _is_client and flags then
        flags.ret_value = false
    end
end

-- AFTER (fixed):
function block_save_attempt(flags)
    if _is_client and flags then
        flags.ret = false       -- what GAMMA MCM dispatcher checks
        flags.ret_value = false  -- keep for vanilla Anomaly path
    end
end
```

Also intercept `exec_console_cmd` on the client to block `save` commands:
```lua
-- In mp_connect(), after block_client_saves():
local _original_exec_console_cmd = exec_console_cmd
exec_console_cmd = function(cmd)
    if _is_client and cmd and cmd:find("^save") then
        printf("[GAMMA MP] Console save blocked -- client mode")
        return
    end
    _original_exec_console_cmd(cmd)
end
```

### 2. Filter ZCP Source Tags in Entity Registration (Priority 1)

In `mp_core.script:on_client_entity_registered()` and `mp_host_events.script:on_entity_register()`:
```lua
function on_client_entity_registered(se_obj, source_tag)
    if _is_client and se_obj then
        -- Skip ZCP infrastructure objects on client -- they are host-only
        if source_tag == "sim_squad_scripted" or source_tag == "se_smart_terrain" then
            return
        end
        mp_client_state.on_local_entity_registered(se_obj)
    end
end
```

### 3. Patch _g.script Wrappers (Priority 2)

The `_g.script` (Log spam remover) defines global `alife_create`, `alife_release`, `TeleportObject` wrappers. Add MP client guards inside these:
```lua
-- In _g.script alife_create wrapper:
function alife_create(...)
    if mp_core and mp_core.is_client() then
        printf("[GAMMA MP] alife_create blocked on client")
        return nil
    end
    -- original logic...
end
```

This is the **single highest-leverage fix** -- it blocks ~50 mods from calling alife on the client in one place.

### 4. Restore printf for MP Debug (Priority 2)

The Log spam remover's `_g.script` silences `printf` globally. In MP debug builds, restore it:
```lua
-- After MP init:
if mp_core.is_mp_active() then
    printf = function(fmt, ...)
        log(string.format(fmt, ...))
    end
end
```

### 5. Add is_mp_client() Global Helper (Priority 1)

Many mods need `is_mp_client()` guards. Add a global helper:
```lua
-- In _g.script or mp_core.script on_game_start:
function is_mp_client()
    return mp_core and mp_core.is_client()
end

function is_mp_host()
    return mp_core and mp_core.is_host()
end
```

---

## "Acceptable for Phase 0" List

These are broken on the client but don't affect host stability or crash:

| Feature | What Breaks | Why It's OK |
|---------|-------------|-------------|
| Campfire health regen | Client HP drifts slightly | Cosmetic, no crash |
| Stealth light gem HUD | Shows stale data on client | Visual only |
| NPC relation/disguise | Per-peer relation state | Expected in co-op |
| Psy damage/rework | Not synced between players | Client-local acceptable |
| Weapon overheat tracking | Independent per-client | No crash |
| Kill statistics | Client stats ephemeral (saves blocked) | Cosmetic |
| Meat spoiling timer | Uses synced game time, works correctly | No conflict |
| Beef's NVG / NVG scopes | Per-client renderer state | No sync needed |
| Animation mods (sprint, aim, camera) | Client-local animations | No sync needed |
| Mark Switch weapon skins | Client-local visual | No sync needed |
| Tooltip/HUD mods | Client-local UI | No sync needed |
| FDDA animations | Dummy item spawn fails on client = items don't animate | Cosmetic only |
| Artefact melting radiation | Per-client radiation | Acceptable |

---

## Conflict Frequency by Type

| Conflict Type | Count | Top Offenders |
|---------------|-------|---------------|
| Entity Lifecycle (create/release) | 55 | Economy death_manager, Magazines Redux, ZCP, Dynamic Anomalies, Artefacts Reinvention |
| Callback Collision | 45 | actor_on_update (40+), npc_on_death (15+), server_entity_on_register (6) |
| SIMBOARD/Squad Manipulation | 18 | ZCP 1.4/1.5d, Bounty Squads, Night Mutants, Guards Spawner |
| A-Life Dependency | 15 | xr_conditions, ZCP game_setup, Artefacts Reinvention, Dynamic Anomalies |
| Global Table Pollution | 12 | Magazines Redux, Dynamic Despawner, _g.script, Loot Stabilizer |
| Weather/Time Override | 10 | surge_manager, psi_storm_manager, Books Pass Time, campfires, Dynamic Anomalies |
| Save System | 4 | YACS (2 versions), Sleep Balance, Cars Fixes |
| Position/Movement Override | 6 | axr_companions, lc_custom, tasks_mirage, Mutant Unstucker |

---

## Deployment Checklist

### Before ANY testing:
- [ ] Fix `flags.ret` in `mp_core.script` save blocker
- [ ] Intercept `exec_console_cmd("save")` on client
- [ ] Add `is_mp_client()` / `is_mp_host()` global helpers
- [ ] Filter source_tag in `server_entity_on_register` handler

### Before Alpha testing:
- [ ] Patch `_g.script` wrappers (alife_create, alife_release, TeleportObject) with client guards
- [ ] Guard Dynamic Despawner with `is_host()`
- [ ] Guard Dynamic Anomalies `drx_da_actor_on_update_callback` with `is_mp_client()`
- [ ] Guard Snipers Remover with `is_host()`
- [ ] Guard axr_companions entity lifecycle calls
- [ ] Guard death_manager loot generation with `is_host()`
- [ ] Guard Magazines Redux alife_create_item calls
- [ ] Guard YACS `create_emergency_save` on client

### Before Beta testing:
- [ ] Audit all 15+ npc_on_death_callback mods for client-side alife calls
- [ ] Implement RPC for client-initiated crafting/cooking/disassembly
- [ ] Guard all time/weather override calls on client
- [ ] Guard all SIMBOARD:create_squad calls on client
- [ ] Disable companion recruitment on client or proxy via RPC
- [ ] Address xr_conditions SIMBOARD nil-crash risk

### Phase 2 (post-launch):
- [ ] Implement proper item sync (inventory create/release RPC)
- [ ] Implement quest state synchronization
- [ ] Implement trader inventory sync
- [ ] Sync psy/health/radiation state between peers
- [ ] Address anonymous callback closure memory leak in PBA

---

## Appendix: Individual Findings Files

Full detailed findings with line numbers and code analysis:
- [findings_0.md](findings_0.md) -- Chunks 1-52 (Mags Redux, Dynamic Anomalies, Hideout Furniture, Emissions, YACS)
- [findings_1.md](findings_1.md) -- Chunks 53-104 (Anomaly Magazines Redux, ATHI, Autolooter, Stealth, FDDA, PBA)
- [findings_2.md](findings_2.md) -- Chunks 105-156 (Artefacts Reinvention, Alife fixes, AI Rework, Arti Recipes)
- [findings_3.md](findings_3.md) -- Chunks 157-208 (Dynamic Despawner, Economy, Close Quarter Combat, Companions, Cooking)
- [findings_4.md](findings_4.md) -- Chunks 209-260 (UI/axr_companions, Snipers Remover, Radiation Areas, Sleep, Psy)
- [findings_5.md](findings_5.md) -- Chunks 261-312 (ZCP 1.4, Vehicles, YACS no quit, Recruitable Companions, Kill Tracker)
- [findings_6.md](findings_6.md) -- Chunks 313-358 (Warfare Patch, ZCP 1.5d, Guards Spawner, Wildkins itms_manager)
