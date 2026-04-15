# Audit Findings - Chunk 4

All .script files in the 52 listed mods were read directly. Mods containing only gamedata/configs (no scripts) are noted at the end. 18 conflict entries follow.

---

## CRITICAL Conflicts

---
MOD: G.A.M.M.A. Radiation Dynamic Areas
FILE: gamma_dynamic_radiation_areas_from_arzsi.script
CONFLICT TYPE: Entity Lifecycle + Global Table Pollution
SEVERITY: CRITICAL
DETAILS: On on_game_load, if a save flag is not set, calls alife():create(anomaly_type, position, level_vertex_id, game_vertex_id) in a loop for every smart terrain on every map to spawn dynamic radiation zone anomaly entities. Also writes unguarded globals to _G: ENABLE_DYNAMIC_RADIATION_ZONES = true and ENABLE_DYNAMIC_RADIATION_ZONES_NPP = true.
OUR IMPACT: alife():create() on a client generates an entity with a local ID that has no host counterpart, corrupting our bidirectional ID mapping table and inserting a ghost entity into the client registry. Fires on on_game_load before MP state is stable. The global flag writes could be read by other scripts on the host, causing logic divergence between peers.
FIX: Wrap spawn_radiation_fields_at_new_game() and all alife():create() calls in an is_host() guard. On clients skip entity creation entirely -- the host already spawned the zones and they arrive via our server_entity_on_register sync. Demote ENABLE_DYNAMIC_RADIATION_ZONES globals to local variables.

---
MOD: G.A.M.M.A. Miracle Machine Remake
FILE: release_restr_in_x16.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: CRITICAL
DETAILS: On on_game_load, iterates all 65534 alife IDs looking for yan_attack_zombies_space_restrictor and calls alife_release(sobj, true) to permanently delete it once per save.
OUR IMPACT: alife_release on a client operates on suppressed A-Life. The restrictor does not exist in the client local view; the call silently fails or crashes. The full 1-65534 scan is expensive at load time, stalling the MP handshake window. Even on success it does not notify the host, leaving the restrictor alive server-side.
FIX: Gate the entire on_game_load body behind is_host(). Clients do not manage world restrictors.

---
MOD: G.A.M.M.A. Snipers Remover
FILE: grok_sniper_remover.script
CONFLICT TYPE: Callback Collisions + Entity Lifecycle
SEVERITY: CRITICAL
DETAILS: Registers actor_on_update. Every ~80 real-seconds iterates db.OnlineStalkers, finds NPCs whose section contains "sniper" (excluding "isg"/"hall"), and calls alife():release(se) to permanently delete them.
OUR IMPACT: Direct collision with our actor_on_update callback. On a client, alife():release() is called while A-Life is suppressed -- may null-deref or leave a dangling entry in our ID mapping table. On the host, fires unilaterally without notifying clients: clients still have the sniper in db.OnlineStalkers while the server entity is gone, causing desync.
FIX: Guard all alife():release() calls with is_host(). When releasing on the host, let our existing server_entity_on_unregister broadcast path notify clients to clean up their local state.

---
MOD: G.A.M.M.A. Rostok Mutant Arena Remover
FILE: z_ph_door_bar_arena_remover.script
CONFLICT TYPE: Entity Lifecycle + Global Table Pollution
SEVERITY: CRITICAL
DETAILS: On actor_on_first_update, iterates all 65534 alife IDs and calls alife_release_id(id) on any object named bar_arena_door, bar_arena_door_2, or bar_arena_door_3. Also monkey-patches ph_door.try_to_open_door and ph_door.try_to_close_door as unconditional global overwrites with no MP awareness.
OUR IMPACT: alife_release_id() on a client with suppressed A-Life silently fails or crashes. The host entity is untouched, producing a persistent desync for the door objects. The global monkey-patches replace shared engine-facing functions without MP awareness -- NPC door-use logic on the host that influences movement simulation will behave differently than on clients.
FIX: Gate alife_release_id calls with is_host(). Review ph_door patches to confirm they only affect local physics collision and not NPC pathfinding state that is synced.

---
MOD: G.A.M.M.A. UI
FILE: axr_companions.script
CONFLICT TYPE: Entity Lifecycle + Position/Movement + SIMBOARD/Squad + Callback Collisions
SEVERITY: CRITICAL
DETAILS: Four distinct conflict vectors. (1) alife_create(sq_sec, smart.position, ...) in setup_companion_task() spawns a full NPC squad server-side. (2) sim:teleport_object(k.id, gvid, lvid, pos) in unstuck() is called every 30s via TimeEvent to teleport stuck companion NPCs. (3) SIMBOARD:setup_squad_and_group(se_obj) and SIMBOARD.smarts_by_names writes in setup_companion_task(). (4) Registers server_entity_on_unregister -- direct callback collision with our unregistration tracker.
OUR IMPACT: alife_create on a client creates a ghost entity not tracked by the host, corrupting ID mapping. teleport_object on a client moves a locally-invalid entity; our position sync produces a desync conflict. SIMBOARD:setup_squad_and_group on a client with suppressed A-Life is a no-op at best, crash at worst. The server_entity_on_unregister handler may run before our handler clears the entity from the tracking registry.
FIX: Guard alife_create, teleport_object, and SIMBOARD:setup_squad_and_group calls with is_host(). Disable the companion_unstuck TimeEvent on clients. Ensure callback ordering so our server_entity_on_unregister handler runs after axr_companions clears its companion_squads table.

---

## HIGH Conflicts

---
MOD: G.A.M.M.A. UI
FILE: item_cooking.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: HIGH
DETAILS: In UICook:Cook(), calls alife_release(se_obj) on ingredient items and alife_create_item(meal.sec, db.actor) to spawn the cooked result. Both are unconditional with no host/client check.
OUR IMPACT: On a client, alife_release removes ingredients from the local view only; the host still has them. The spawned cooked meal is a client-only ghost item invisible to the host and other players. Inventory is permanently desynced.
FIX: Cooking must be host-authoritative. Client sends a cook-request packet; host validates inventory, performs alife_release/alife_create_item, and syncs the result back.

---
MOD: G.A.M.M.A. Quests Rebalance
FILE: xr_effects.script
CONFLICT TYPE: Entity Lifecycle + Weather/Time + SIMBOARD/Squad
SEVERITY: HIGH
DETAILS: Large script (~3000+ lines). Confirmed conflicts: (1) Numerous alife_create() and alife_create_item() calls for quest item spawning at hardcoded world positions. (2) alife_release() and alife_release_id() for quest cleanup. (3) level.set_weather(p[1], true/false) and level.set_weather_fx() calls. (4) SIMBOARD.smarts_by_names[] lookups, SIMBOARD:start_sim(), and SIMBOARD:stop_sim() calls.
OUR IMPACT: Quest-triggered entity spawns on a client produce ghost objects not tracked by the host. level.set_weather on a client is overwritten by our host weather sync but causes visible glitches. SIMBOARD:start_sim()/stop_sim() on a client with suppressed A-Life is undefined. Item rewards via alife_create_item cause permanent inventory desync.
FIX: Gate all alife_create* and alife_release* calls with is_host(). Item rewards should be RPC-based. Remove level.set_weather calls on clients. Gate SIMBOARD:start_sim()/stop_sim() with is_host().

---
MOD: G.A.M.M.A. Rare Stashes Balance
FILE: treasure_manager.script + grok_stashes_on_corpses.script
CONFLICT TYPE: Entity Lifecycle + Callback Collisions
SEVERITY: HIGH
DETAILS: create_random_stash() calls set_random_stash() which spawns items inside inventory boxes using alife_create_item. Triggered on npc_on_use (corpse looting) and at game load. grok_stashes_on_corpses.script also registers server_entity_on_unregister to clean up _used_corpses.
OUR IMPACT: alife_create_item on a client generates ghost stash contents not tracked by the host. The server_entity_on_unregister callback collision may cause our tracking handler to process corpse cleanup events out of order.
FIX: Gate alife_create_item in set_random_stash with is_host(). The server_entity_on_unregister handler in grok_stashes_on_corpses.script is a pure local-table cleanup (_used_corpses[id] = nil) and is safe to run on both peers unchanged.

---
MOD: G.A.M.M.A. Starter items are not broken
FILE: itms_manager.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: HIGH
DETAILS: actor_on_first_update calls alife_release(obj) for items in the release category and alife_create_item for bolts. Fires unconditionally at session start.
OUR IMPACT: alife_release on actor-inventory items on a client operates on suppressed A-Life. Items exist on the host but are deleted from the client local view, creating inventory desync before MP state is stable.
FIX: Gate all alife_release and alife_create_item calls in actor_on_first_update with is_host(). Item management at session start should be host-only with inventory sync following.

---
MOD: G.A.M.M.A. Starting Loadouts
FILE: grok_remove_knife_ammo_on_start.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: HIGH
DETAILS: On actor_on_first_update, fires two timed calls (0.25s apart) to alife_release_id(obj:id()) for knife ammo items in the actor inventory. Runs unconditionally at session start.
OUR IMPACT: alife_release_id on a client with suppressed A-Life fails silently or corrupts state. Fires before MP state is stable.
FIX: Gate both remove_knife_ammo_1 and remove_knife_ammo_2 with is_host().

---
MOD: G.A.M.M.A. Short Psi Storms
FILE: psi_storm_manager.script
CONFLICT TYPE: Weather/Time + SIMBOARD/Squad
SEVERITY: HIGH
DETAILS: CPsiStormManager:start() calls level.set_time_factor(surge_time_factor) with a hardcoded value of 10. skip_psi_storm() and finish() both call level.set_time_factor(self.game_time_factor) to restore it. start() also calls level.set_weather_fx(). kill_objects_at_pos() reads SIMBOARD.smarts[] for surge-safe cover detection.
OUR IMPACT: level.set_time_factor on a client overwrites our synced time factor. If the psi storm fires at a different time on the client vs. host, the cached game_time_factor will be wrong when restored, permanently desyncing the time rate. SIMBOARD reads stale data on clients.
FIX: Gate level.set_time_factor calls with is_host(). Time factor changes on clients must only come from our MP sync. Weather FX calls can remain as cosmetic-only.

---
MOD: G.A.M.M.A. Sleep Balance
FILE: ui_sleep_dialog.script
CONFLICT TYPE: Weather/Time + Save System
SEVERITY: HIGH
DETAILS: dream_callback() calls level.change_game_time(0, hours, 0) to advance game time by sleep duration. dream_callback2() calls exec_console_cmd("save ...") -- a sleep autosave that bypasses our on_before_save_input block by using the console directly.
OUR IMPACT: level.change_game_time on a client diverges from the host authoritative clock. Our MP time sync overwrites it next tick but causes a visible time-jump glitch. The console save call directly bypasses our save-block mechanism -- clients will create save files violating the MP invariant.
FIX: Gate level.change_game_time with is_host(). Wrap the exec_console_cmd save call in an is_host() check. On clients, sleep is visual/audio only with time sync received from the host post-sleep.

---

## MEDIUM Conflicts

---
MOD: G.A.M.M.A. NPC Loot Claim Remade
FILE: grok_loot_claim.script
CONFLICT TYPE: Callback Collisions
SEVERITY: MEDIUM
DETAILS: Registers npc_on_death_callback, monster_on_death_callback, and on_before_key_press. Death callbacks populate claimed[v_id] = k_id (maps corpse ID to killer NPC ID). The key-press handler ray-picks on USE to block looting of claimed bodies using level.object_by_id(claimed[id]).
OUR IMPACT: Direct collision with our npc_on_death_callback and monster_on_death_callback death-event broadcast. On a client, death events arrive from our network broadcast rather than the raw engine callback -- timing differs and claimed[] may be populated before the broadcast arrives or vice versa, causing loot-block logic to fire incorrectly.
FIX: The claimed[] table must be network-replicated. Host populates claimed[] on death and broadcasts the owner ID to all clients. On clients, npc_on_death_callback should only be driven by our MP broadcast, not the raw engine event.

---
MOD: G.A.M.M.A. Mutant Unstucker Remade
FILE: grok_mutant_unstucker.script
CONFLICT TYPE: Callback Collisions + Global Table Pollution
SEVERITY: MEDIUM
DETAILS: Registers monster_on_update. Every ~72.5 seconds compares a mutant position against a cached position and calls st:set_npc_position(post_pos) to nudge it if stuck. Declares module-level globals to _G: online_npcs_pos_x, online_npcs_pos_y, online_npcs_pos_z, trigger3, delay3.
OUR IMPACT: set_npc_position is a local game-object call -- it moves the mutant on the client without notifying the host. Our force_set_position sync from the host overwrites it next tick but produces visible jitter. The _G globals could collide with any other script using identical names.
FIX: Gate teleport_dodge() with is_host() or disable the monster_on_update callback entirely on clients (monsters are server-authoritative). Localize the position tracking tables and timer variables.

---
MOD: G.A.M.M.A. Medications Balance
FILE: zzz_player_injuries.script
CONFLICT TYPE: Callback Collisions
SEVERITY: MEDIUM
DETAILS: Registers actor_on_update (heavy per-tick health/limb calculation loop reading db.actor.health and applying timed heal ticks) and on_key_press (HUD toggle keybind).
OUR IMPACT: Direct collision with our actor_on_update and on_key_press callbacks. Actor health is locally simulated on the client and may diverge from the host-authoritative health. The injury system applies local healing/damage ticks not synchronized with the host. The on_key_press HUD toggle collision is cosmetic only.
FIX: Actor health/injury simulation must be host-authoritative. On the client the actor_on_update health tracking should read synced values. The HUD toggle via on_key_press is safe as-is.

---
MOD: G.A.M.M.A. Psy rework
FILE: arszi_psy.script
CONFLICT TYPE: Callback Collisions
SEVERITY: MEDIUM
DETAILS: Registers actor_on_update for psy-health management (decrements psy_table.actor_psy_health over time based on game.get_game_time() diffs, manages PPE visual effects). Exports psy_table as shared state used by other scripts including grok_psy_fields_in_the_north.
OUR IMPACT: Collision with our actor_on_update. Psy damage is not synchronized between players. If host and client have different psy states they diverge. Since psy_table is shared with grok_psy_fields_in_the_north.script, any desync here multiplies.
FIX: Psy damage application should be host-authoritative. Host broadcasts psy damage packets; client actor_on_update becomes read-only/visual only.

---
MOD: G.A.M.M.A. Psy Fields in the North
FILE: grok_psy_fields_in_the_north.script
CONFLICT TYPE: Callback Collisions
SEVERITY: MEDIUM
DETAILS: Registers actor_on_update. Every 2 seconds when psy_damage == 1, directly writes psy_table.actor_psy_health = psy_table.actor_psy_health - 999 via arszi_psy.save_state() manipulation -- effectively an instant psy-kill. Tightly coupled to arszi_psy state.
OUR IMPACT: Collision with our actor_on_update. The psy barrier write is a direct mutation of non-synced client state. If this fires on the client but not the host due to zone detection mismatch, the client hits psy death while the host is unaffected.
FIX: Gate the psy_table.actor_psy_health write with is_host(). Sounds and visual effects (level.add_pp_effector) can remain on the client.

---

## LOW Conflicts

---
MOD: G.A.M.M.A. Skill System Balance
FILE: haru_skills.script
CONFLICT TYPE: Entity Lifecycle + Callback Collisions
SEVERITY: LOW
DETAILS: In NPC loot iteration callbacks, calls alife_release(item) to remove certain rare drops and alife_create_item(sec, npc, ...) to spawn scavenging bonus items. Also registers actor_on_update for stat display updates (read-only, no simulation writes).
OUR IMPACT: alife_release and alife_create_item in loot callbacks on a client will silently fail or corrupt state. Loot modification is tied to NPC death which is host-authoritative. The actor_on_update collision is negligible.
FIX: Gate all alife_release and alife_create_item calls in loot callbacks with is_host(). The actor_on_update stat tracking can remain on the client.

---

## Mods With No .script Files (Configs Only)

The following mods contain only gamedata/configs entries. No Lua scripts found; no conflicts:

- G.A.M.M.A. MCM values - Rename to keep your personal changes
- G.A.M.M.A. NPC Spawns
- G.A.M.M.A. Mutants Overhaul
- G.A.M.M.A. Starting Locations
- G.A.M.M.A. No Copyrighted Music
- G.A.M.M.A. No Masks Textures
- G.A.M.M.A. No trade with random stalkers
- G.A.M.M.A. Optimised World Models
- G.A.M.M.A. Outfits Balances
- G.A.M.M.A. Soundscape Overhaul
- G.A.M.M.A. Soundtrack

## Mods Scanned With No Conflicts Found

- G.A.M.M.A. MP7 Replacer EFT position -- aaa_rax_icon_override.script: icon override only
- G.A.M.M.A. Minimalist HUD -- ui_sidhud_mcm.script registers actor_on_update for display refresh only; no simulation writes, no alife calls
- G.A.M.M.A. NPC Loadouts -- configs + meta.ini only; no scripts
- G.A.M.M.A. NPC Loot Claim Remade -- npc_loot_claim.script is a one-line stub; conflicts are in grok_loot_claim.script documented above
- G.A.M.M.A. NPCs Faster Reactions -- no scripts found
- G.A.M.M.A. NPCs cannot see through foliage - Tosox Version -- no scripts found
- G.A.M.M.A. New Main Menu -- no scripts found
- G.A.M.M.A. No harmonica -- sr_camp.script, xr_campfire_point.script: campfire logic patching, no alife or MP-relevant calls
- G.A.M.M.A. No NPC Friendly Fire -- grok_no_npc_friendly_fire.script: faction relation patch only
- G.A.M.M.A. Not so instant tooltip -- instant_tooltip.script: tooltip delay MCM only
- G.A.M.M.A. P90 One Handed -- no scripts found
- G.A.M.M.A. Part Type Fixer -- parts_match_item.script: static item compatibility table, no runtime calls
- G.A.M.M.A. Postprocess Effects -- no scripts found
- G.A.M.M.A. Quick Action Wheel Balance -- haru_quick_action_wheel_mcm.script: MCM config read/write only
- G.A.M.M.A. Radiation Effects Overhaul -- grok_progressive_rad_damages.script registers actor_on_update for local health damage (no alife calls); AGDD_voiced_actor.script registers npc_on_death_callback/monster_on_death_callback/actor_on_update for audio and combat-intensity tracking only -- no simulation writes, no alife calls, purely cosmetic
- G.A.M.M.A. Reliable Animation Settings -- animation system scripts; no alife or MP-relevant calls
- G.A.M.M.A. Repair Kit Renaming -- no scripts found
- G.A.M.M.A. Scopes radius fixes -- scopeRadii.script: scope config override only
- G.A.M.M.A. Silenced Shots Audio AI Comments -- no scripts found
- G.A.M.M.A. Sin and Mutants are Allies -- grok_sin_allied_to_mutants.script: faction relation set; no alife calls
- G.A.M.M.A. Stealth Crash Fix -- visual_memory_manager.script: NPC visibility overrides; no alife or MP-relevant calls
- G.A.M.M.A. Tutorials -- MCM tutorial flag scripts only
- G.A.M.M.A. UI (remaining scripts) -- alticons.script, grok_dof_with_UI.script, item_repair_override.script, ui_inventory.script, ui_minimap_counter.script, ui_options.script, utils_ui.script, utils_ui_icon_rotation_fix_mcm.script: UI rendering/configuration; no additional conflicts beyond axr_companions.script and item_cooking.script documented above
- G.A.M.M.A. UMP Position -- no scripts found
- G.A.M.M.A. Unjam Reload on the same key -- arti_jamming.script registers actor_on_update (jam state machine, local weapon state only), on_key_press (unjam keybind), and calls alife_release_id for part swapping (actor-inventory local, LOW risk); remaining scripts have no alife/MP-relevant calls

---

## Summary Table

| Mod | File | Conflict Type | Severity |
|-----|------|--------------|----------|
| G.A.M.M.A. Radiation Dynamic Areas | gamma_dynamic_radiation_areas_from_arzsi.script | Entity Lifecycle + Global Table | CRITICAL |
| G.A.M.M.A. Miracle Machine Remake | release_restr_in_x16.script | Entity Lifecycle | CRITICAL |
| G.A.M.M.A. Snipers Remover | grok_sniper_remover.script | Callback Collisions + Entity Lifecycle | CRITICAL |
| G.A.M.M.A. Rostok Mutant Arena Remover | z_ph_door_bar_arena_remover.script | Entity Lifecycle + Global Table | CRITICAL |
| G.A.M.M.A. UI | axr_companions.script | Entity Lifecycle + Position/Movement + SIMBOARD + Callback Collision | CRITICAL |
| G.A.M.M.A. UI | item_cooking.script | Entity Lifecycle | HIGH |
| G.A.M.M.A. Quests Rebalance | xr_effects.script | Entity Lifecycle + Weather/Time + SIMBOARD | HIGH |
| G.A.M.M.A. Rare Stashes Balance | treasure_manager.script + grok_stashes_on_corpses.script | Entity Lifecycle + Callback Collision | HIGH |
| G.A.M.M.A. Starter items are not broken | itms_manager.script | Entity Lifecycle | HIGH |
| G.A.M.M.A. Starting Loadouts | grok_remove_knife_ammo_on_start.script | Entity Lifecycle | HIGH |
| G.A.M.M.A. Short Psi Storms | psi_storm_manager.script | Weather/Time + SIMBOARD | HIGH |
| G.A.M.M.A. Sleep Balance | ui_sleep_dialog.script | Weather/Time + Save System bypass | HIGH |
| G.A.M.M.A. NPC Loot Claim Remade | grok_loot_claim.script | Callback Collisions | MEDIUM |
| G.A.M.M.A. Mutant Unstucker Remade | grok_mutant_unstucker.script | Callback Collisions + Global Table | MEDIUM |
| G.A.M.M.A. Medications Balance | zzz_player_injuries.script | Callback Collisions | MEDIUM |
| G.A.M.M.A. Psy rework | arszi_psy.script | Callback Collisions | MEDIUM |
| G.A.M.M.A. Psy Fields in the North | grok_psy_fields_in_the_north.script | Callback Collisions | MEDIUM |
| G.A.M.M.A. Skill System Balance | haru_skills.script | Entity Lifecycle + Callback Collisions | LOW |
