# Audit Findings - Chunk 2

Audited 52 mods from the STALKER GAMMA modpack_addons directory. 24 contained Lua scripts; 28 are asset-only and confirmed clean. Findings are listed below in order of severity.

---

## CRITICAL SEVERITY

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: zz_item_artefact.script
CONFLICT TYPE: Callback Collisions + Entity Lifecycle Interference
SEVERITY: CRITICAL
DETAILS: Overrides se_artefact.se_artefact.on_register and on_unregister directly on the SE class, then manually fires SendScriptCallback(server_entity_on_register) and SendScriptCallback(server_entity_on_unregister) from inside those overrides. Registers server_entity_on_unregister callback listener to clean local cond_t table. Registers actor_on_update listener entity_unregister_plan_b() that iterates cond_t and calls alife_object() every 10 seconds. Extensively calls alife_create_item, alife_release, alife_create for artefact container break/assemble and loot patching.
OUR IMPACT: The entity_unregister_plan_b actor_on_update listener runs on the client against suppressed A-Life: alife_object() returns nil for all IDs, wiping cond_t entirely on first run and resetting all artefact conditions. The alife_release/alife_create_item calls on the client for container swap/break actions bypass our ID-mapping table, creating ghost entities. SE class method override may conflict if our code also hooks the SE class method directly.
FIX: (1) Guard entity_unregister_plan_b with if is_client then return end. (2) Gate all alife_create_item/alife_release calls in item-action functions to host-only via RPC. (3) Verify our MP hook on server_entity_on_register chains correctly after the class-level override.
---

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: perk_based_artefacts.script
CONFLICT TYPE: Entity Lifecycle Interference + A-Life Dependency
SEVERITY: CRITICAL
DETAILS: Calls sim:release(sim:object(monster_id)) (raw alife():release()) directly to instantly delete monsters killed by artefact procs (Lucifer claw effect). Calls alife_create_item to spawn meat drops, IED explosion objects, and artefact fusion results (alife_release_id, alife_create_item). Registers multiple actor_on_update callbacks via RegisterScriptCallback and a custom register_callback helper with anonymous closures. The actor_on_update handler runs every 100ms processing belt artefact effects, degradation, and sanity checks.
OUR IMPACT: The sim:release() call on monster death bypasses our monster_on_death_callback broadcast entirely: the SE object is gone before the client processes the death, causing client-side desync (monster still visible on client). Multiple alife_create_item/alife_release_id calls for artefact crafting on the client fire against suppressed A-Life, creating items with IDs unknown to the host ID mapping table. Anonymous register_callback closures cannot be unregistered, leaking memory across level transitions.
FIX: (1) Gate sim:release() Lucifer-kill path to host only; on client send RPC. (2) Gate all artefact crafting alife_create/alife_release to host only, replicate via sync message. (3) Replace anonymous closure actor_on_update registrations with named functions.
---

---
MOD: G.A.M.M.A. Alife fixes
FILE: alife_storage_manager.script
CONFLICT TYPE: Entity Lifecycle Interference + A-Life Dependency
SEVERITY: CRITICAL
DETAILS: The on_after_load_state() migration path (triggered by actor_on_first_update on GAME_VERSION mismatch) iterates the entire A-Life object table (for i=1,65534 do sim:object(i)...), calls alife_release(se_obj) on old-section detectors, then alife_create_item(sec, se_parent) to recreate them. CALifeStorageManager_before_save is a direct engine callback called on every save that marshals the entire m_data table to a .scoc file on disk.
OUR IMPACT: If a client save has a different GAME_VERSION than the host (new player joining), the migration fires on the client. It iterates 65,534 A-Life slots (all nil on suppressed client), then attempts alife_release/alife_create_item on stale references, likely causing a nil dereference crash. CALifeStorageManager_before_save is a direct engine hook that our on_before_save_input block does not intercept; on level transitions the engine triggers this directly, causing the client to write a .scoc save file that may corrupt the host save state if paths overlap.
FIX: (1) Add if mp_is_client then return end at the top of on_after_load_state(). (2) Suppress or redirect CALifeStorageManager_before_save on client to a client-specific shadow path that cannot affect server saves.
---

---
MOD: G.A.M.M.A. Agroprom Underground Remake
FILE: agroprom_drugkit_spawner_gamma.script
CONFLICT TYPE: Entity Lifecycle Interference + A-Life Dependency
SEVERITY: CRITICAL
DETAILS: On actor_on_first_update, checks info portion agroprom_underground_drugkit_spawned. If absent, calls alife_create_item(itm_drugkit, {vector():set(110.3,-2.26,-21.6), 8952, 3727}) to spawn a drugkit at a hardcoded world position using hardcoded A-Life vertex IDs, then grants the info portion.
OUR IMPACT: On the client, A-Life is suppressed so alife_create_item with a world-position vector calls alife():create() against the suppressed server: either silently fails or crashes. If the client save does not have the info portion, every joining client attempts to spawn this item independently, resulting in duplicate world items on the host or a client crash. The hardcoded vertex IDs (8952, 3727) may not be valid from the client perspective.
FIX: Guard the entire actor_on_first_update body with if is_client then return end. Synchronize the info portion from host to client on join so the client already has the flag.
---

---
MOD: Dark Valley Lamp Remover (better FPS at Bandit Base)
FILE: dark_valley_lamp_remover.script
CONFLICT TYPE: Entity Lifecycle Interference + A-Life Dependency
SEVERITY: CRITICAL
DETAILS: On actor_on_first_update, iterates IDs 1-65534, finds lamp objects (clsid.hlamp_s) on the Dark Valley level, and calls alife_release_id(id) on each non-placeable lamp. Guarded by info portion dark_valley_lamp_despawned so it only runs once per save.
OUR IMPACT: On the client, level.object_by_id(id) may return objects that differ from server-side state (A-Life suppressed). Calling alife_release_id(id) on the client calls against the suppressed alife. If this fires on the client before the info portion is synced from the host, the client attempts to release lamp IDs the host already released, potentially producing a double-release that corrupts the entity registry on the host.
FIX: Guard the loop with if is_client then return end. The host exclusively manages lamp removal; clients learn of removed entities via server_entity_on_unregister broadcast.
---


## HIGH SEVERITY

---
MOD: Darkasleif's Cars Fixes
FILE: LevelChangeCars.script
CONFLICT TYPE: Save Hook Field Mismatch
SEVERITY: HIGH
DETAILS: Registers on_before_save_input callback. Handler sets flags.ret = true when actor is in a car (InCar == true) to block the save. Our MP mod's on_before_save_input handler sets flags.ret_value = false to block client saves.
OUR IMPACT: flags.ret and flags.ret_value are separate fields in the flags object. Our block and this mod's block do not interfere with each other mechanically, but if both fire simultaneously the flags table contains both fields, which may confuse engine-side save logic depending on which field the engine reads. On a client in a car, neither block takes effect correctly because suppressed A-Life means the engine may not reach the Lua save hook at all; the client may still attempt a partial save that corrupts the host save file if the path overlaps.
FIX: Normalize all on_before_save_input hooks to use flags.ret_value. Audit which field the engine actually reads and document it. Guard the InCar check on client with if is_client then return end so the client never attempts the save block path.
---

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: grok_artefacts_random_spawner.script
CONFLICT TYPE: A-Life Dependency + Callback Collision
SEVERITY: HIGH
DETAILS: Registers actor_on_update for grok_artefact_spawner(). On a timer, calls bind_anomaly_zone.force_spawn_artefacts() and drx_da_main.spawn_artefacts_on_level() which create SE objects via alife():create(). In set_delay(), calls sim:actor().m_game_vertex_id directly: local actor_level = sim:level_name(gg:vertex(sim:actor().m_game_vertex_id):level_id()) — sim:actor() returns nil on suppressed A-Life.
OUR IMPACT: On the client, sim:actor() is nil. The nil dereference on .m_game_vertex_id crashes the entire actor_on_update chain for this callback. Even if guarded, alife():create() calls for artefact spawning on the client produce entities not in our ID mapping table, and the spawns happen independently on each connected client producing duplicate artefacts in anomaly zones.
FIX: (1) Guard grok_artefact_spawner with if is_client then return end at the top. (2) Gate all force_spawn_artefacts / spawn_artefacts_on_level calls to host only. Clients receive artefact presence via normal server_entity_on_register broadcast.
---

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: exo_loot.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Monkey-patches death_manager.spawn_cosmetics by storing the original and replacing it: SpawnCosmetics = death_manager.spawn_cosmetics; function death_manager.spawn_cosmetics(npc, ...) SpawnCosmetics(...) spawn_gear(npc, outfit_section) end. The spawn_gear function calls alife_create_item("exo_power_supply_military", npc) and alife_create_item("exo_power_supply", npc) conditionally based on outfit section.
OUR IMPACT: This patch fires on npc death. On the client, death_manager.spawn_cosmetics may be called via our monster_on_death_callback / npc_on_death_callback chain. alife_create_item on the client creates items not tracked in our ID mapping table. The monkey-patch also breaks if our MP code or another mod replaces death_manager.spawn_cosmetics after this mod loads, silently discarding either this patch or the later one.
FIX: Gate the alife_create_item calls inside spawn_gear with if is_client then return end. Convert to a proper npc_on_death_callback RegisterScriptCallback listener rather than a monkey-patch to avoid chain breakage.
---

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: dialogs_agr_u.script
CONFLICT TYPE: A-Life Dependency + Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Quest-complete dialogue calls alife_release(se_obj) to remove a stalker SE object. Quest-accept dialogue calls alife_create_item("af_blood", npc). Calls simulation_objects.is_on_the_same_level(alife():actor(), se_obj) — alife():actor() returns nil on suppressed client. Also reads SIMBOARD.smarts_by_names["val_smart_terrain_7_4"] directly.
OUR IMPACT: alife():actor() nil dereference crashes the is_on_the_same_level call on the client. alife_release and alife_create_item in dialogue handlers on the client operate against suppressed A-Life, either failing silently or producing unmapped entities. SIMBOARD.smarts_by_names may be an empty table on the client if SIMBOARD is not populated, causing a nil index crash at the smarts lookup.
FIX: (1) Guard dialogue logic that calls alife():actor() or SIMBOARD with if is_client then return end or nil-check wrappers. (2) Gate alife_release / alife_create_item dialogue paths to host only; replicate outcome to client via RPC.
---

---
MOD: G.A.M.M.A. Arti Recipes Overhaul
FILE: zzzz_arti_jamming_repairs.script
CONFLICT TYPE: Entity Lifecycle Interference + Raw A-Life Register Pattern
SEVERITY: HIGH
DETAILS: Uses the raw two-step SE creation pattern: local se_result = alife_create(...) followed by alife():register(se_result). Also calls alife_release(se_obj) directly and alife_release_id(self.new_con[i].id). The raw alife():register() call fires server_entity_on_register directly from the SE registration path before the entity is entered into our MP ID mapping table.
OUR IMPACT: Our server_entity_on_register callback receives an entity that is not yet in our ID mapping table. Any attempt by our callback to look up the entity by ID finds nothing, and the entity becomes a ghost — visible on the host, unknown to clients. alife_release / alife_release_id calls on the client against suppressed A-Life either crash or silently fail, leaving the host with orphaned SE objects that the client believes are gone.
FIX: Replace all raw alife_create + alife():register() pairs with alife_create_item or wrap them in a host-only RPC so the host performs registration and propagates the new ID to clients. Gate all alife_release / alife_release_id calls to host only.
---

---
MOD: G.A.M.M.A. AI Rework
FILE: xr_conditions.script
CONFLICT TYPE: A-Life Dependency + SIMBOARD Direct Access
SEVERITY: HIGH
DETAILS: Massive script (~3000+ lines) with dozens of direct SIMBOARD.smarts_by_names[name], SIMBOARD.smarts[smart.id].squads, and SIMBOARD:get_smart_by_name() accesses used as condition checks for quest logic, spawn logic, and squad counts. Calls alife():actor(), alife():object_by_id(), and alife():has_info() throughout. Pattern example at line ~1644: local smart = SIMBOARD:get_smart_by_name("jup_b41") followed immediately by for k,v in pairs(SIMBOARD.smarts[smart.id].squads) with no nil guard on smart.
OUR IMPACT: On a suppressed client, SIMBOARD may not be populated (squads and smarts tables empty or nil). alife():actor() returns nil. Any of the nil dereferences in the dozens of SIMBOARD accesses will crash the condition-check call stack, breaking quest triggers, dialogue conditions, and spawn checks globally. Because xr_conditions is referenced by nearly every quest script, a crash here breaks all quest state machine transitions.
FIX: Add nil guards (if not smart then return false end) to all SIMBOARD lookups. Guard all alife():actor() calls with local actor_se = alife():actor(); if not actor_se then return false end. Consider adding a top-of-file is_client short-circuit for condition functions that require A-Life data.
---

---
MOD: G.A.M.M.A. Better Quick Release System
FILE: item_backpack.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: actor_on_item_use handler calls alife_create("inv_backpack", actor:position(), actor:level_vertex_id(), actor:game_vertex_id()) then alife_release(backpack) to convert the backpack item into a world stash. actor_on_item_take_from_box calls alife_release(se_obj) to remove the stash and alife_create_item(section, db.actor) to return the backpack. UICreateStash:OnAccept also calls alife_create followed by alife_release_id.
OUR IMPACT: On the client, all alife_create / alife_release calls operate against suppressed A-Life. The stash SE object created on the client is not in our ID mapping table, so the host never learns about it. The client sees a map marker for a stash the host does not have. alife_release on an object the host still has causes desync; the reverse also applies. The entire backpack-to-stash and stash-to-backpack flow is broken in MP without host-only gating.
FIX: Gate the entire item-use stash creation and stash-retrieval paths to host only. On client, send an RPC to the host to perform the alife_create / alife_release operations; the host responds with the new entity ID which the client uses to display the map marker.
---


## MEDIUM SEVERITY

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: zz_item_artefact.script (actor_on_update sub-finding)
CONFLICT TYPE: Callback Collision (actor_on_update overhead)
SEVERITY: MEDIUM
DETAILS: entity_unregister_plan_b is registered as actor_on_update and runs every 10 seconds on all clients. On a non-suppressed host this is benign, but the iteration over cond_t calling alife_object(id) on every stored ID creates a steady polling load. Separately from the CRITICAL finding above, this is an additional actor_on_update listener that competes with our own actor_on_update listener for frame time.
OUR IMPACT: Our actor_on_update listener's execution time budget is shared with this listener. On clients (after the CRITICAL fix gates it away) this is a no-op, but on the host it adds per-frame overhead proportional to the size of cond_t (potentially hundreds of artefacts).
FIX: Replace the 10-second poll with an event-driven cleanup: hook server_entity_on_unregister to remove the ID from cond_t directly, eliminating the periodic scan.
---

---
MOD: Demonized FDDA New Time Events
FILE: demonized_time_events.script
CONFLICT TYPE: Duplicate Global Definition (shared function namespace collision)
SEVERITY: MEDIUM
DETAILS: Defines CreateTimeEvent, RemoveTimeEvent, ResetTimeEvent, ProcessEventQueue in _G. Registers actor_on_update for its own process_queue() using a local ev_queue table. G.A.M.M.A. Arti Recipes Overhaul ships its own demonized_time_events.script (an optimized binary-insert version) that defines the same globals with a different local ev_queue. Whichever loads last wins the global symbols. Events enqueued before the second load are in the first module's local ev_queue and will never be processed by the winning module's process_queue.
OUR IMPACT: Depending on load order, one module's ev_queue becomes orphaned. Any timed events registered by mods that load before the second demonized_time_events (including potentially our own) may silently never fire. Both modules register actor_on_update separately, so the losing module's process_queue still runs but on an ev_queue that nobody writes to — wasted CPU per frame.
FIX: Consolidate to a single canonical demonized_time_events script (prefer the optimized Arti Recipes Overhaul version). Remove the duplicate from FDDA New Time Events. Document which version is authoritative and add a version guard at the top of the file.
---

---
MOD: Asnen's and Grok's Better Cigarettes Animations
FILE: enhanced_animations.script
CONFLICT TYPE: Entity Lifecycle Interference (Minor)
SEVERITY: MEDIUM
DETAILS: Calls alife_create_item("items_anm_dummy", db.actor) to spawn an invisible animation dummy item on the actor when an item-use animation begins. Calls alife_release(db.actor:object("items_anm_dummy")) when the animation ends or is interrupted. Dynamically registers and unregisters actor_on_update during animations.
OUR IMPACT: On the client, alife_create_item creates a dummy item not tracked in our ID mapping. When alife_release is called, the host has no record of this item, causing a mismatch. The dynamic actor_on_update registration / unregistration pattern is safe (named function, not anonymous closure) and does not conflict with our listener. The dummy item desync is cosmetic but may accumulate ghost entries in the host entity registry over time.
FIX: Gate alife_create_item and alife_release for the animation dummy to host only. On the client, use a purely client-side flag (local variable) to track animation state instead of a real SE item.
---

---
MOD: G.A.M.M.A. Actor Damage Balancer
FILE: momopate_pba_tweaks.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: MEDIUM
DETAILS: Contains the same Lucifer artefact kill-proc pattern as perk_based_artefacts.script: local sim = alife(); sim:release(sim:object(monster_id)) to instantly delete a monster, followed by alife_create_item(monster_meat, {...}) to spawn loot. This is a duplicate or fork of the perk_based_artefacts logic running in a separate script.
OUR IMPACT: Same as perk_based_artefacts CRITICAL finding but applies here as well: sim:release() on the client bypasses monster_on_death_callback, causing client-side desync. alife_create_item for loot on the client creates unmapped items. Because this is a separate script from perk_based_artefacts, both may fire for the same event if both are loaded, double-spawning loot.
FIX: Gate sim:release() and alife_create_item to host only. Verify this script and perk_based_artefacts.script are not both handling the same Lucifer event to prevent double-spawns.
---

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: grok_artefacts_melter_charge.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: MEDIUM
DETAILS: When an artefact is dragged onto a melter kit in the inventory UI, calls alife_release(obj_2) to destroy one of the combined artefacts. The release fires immediately in the drag handler.
OUR IMPACT: On the client, alife_release on the dragged artefact calls against suppressed A-Life. The client's inventory reflects the item as gone, but the host still has the SE object. The host and client artefact inventories diverge. Subsequent alife_object(id) lookups for that ID return the object on the host but nil on the client.
FIX: Gate alife_release in the melter drag handler to host only. Send an RPC from client to host to perform the release; the host confirms and sends back the updated inventory state.
---

---
MOD: G.A.M.M.A. Arti Recipes Overhaul
FILE: custom_functor_autoinject.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: MEDIUM
DETAILS: In a custom functor dispatch handler, calls alife_create_item(obj:section(), db.actor) to give the actor a crafted item. This fires as part of a crafting/recipe completion flow.
OUR IMPACT: On the client, alife_create_item creates an item not in our ID mapping table. The item appears in the client inventory but the host has no record of it, causing inventory desync. On save/load, the item may disappear from the client save because the host save does not contain it.
FIX: Gate alife_create_item in crafting completion handlers to host only. Client sends a craft-complete RPC; host creates the item and broadcasts the new entity ID so the client inventory updates correctly.
---

---
MOD: G.A.M.M.A. Arti Recipes Overhaul
FILE: workshop_autoinject.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: MEDIUM
DETAILS: Workshop recipe craft handler calls alife_release(obj) to consume an ingredient item when a recipe completes.
OUR IMPACT: On the client, alife_release against suppressed A-Life fails silently. The ingredient item remains in the host inventory while disappearing from the client inventory, causing permanent desync. If the client reconnects and their save is loaded, the host will have the item and the client will not, producing a duplicate.
FIX: Gate alife_release in workshop craft consumption to host only. Use an RPC for client-initiated crafts.
---

---
MOD: G.A.M.M.A. Arti Recipes Overhaul
FILE: trader_autoinject.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: MEDIUM
DETAILS: trader_on_restock callback calls alife_create_item(k, npc) to inject items into a trader's inventory on restock. Fires whenever a trader restocks, which can happen on level load or timed intervals.
OUR IMPACT: On the client, alife_create_item against suppressed A-Life silently fails, so trader inventories on the client are missing the injected items. If the client interacts with a trader, their visible stock differs from the host's stock, causing trade desyncs (client can buy items the host trader does not have).
FIX: Gate trader_on_restock alife_create_item calls to host only. Trader inventory state is authoritative on the host; clients receive stock data via normal NPC inventory sync.
---


## LOW SEVERITY

---
MOD: G.A.M.M.A. AI Rework
FILE: schemes_ai_gamma.script
CONFLICT TYPE: RNG Pollution
SEVERITY: LOW
DETAILS: Calls math.randomseed(os.time()) at module scope (line ~74), seeding the global Lua RNG with wall-clock time when the script is first loaded. Saves and loads dumb_table, table_npc, swicth_table2 to m_data (actor save state).
OUR IMPACT: math.randomseed at module scope causes the host and each client to seed the RNG independently at their respective load times. Any subsequent math.random() calls (in any script, not just this one) will diverge between host and clients. This is low severity because most gameplay-critical randomness in GAMMA uses independent seeds or is host-authoritative, but it can cause subtle divergence in AI behaviour checks. The m_data saves are client-local and do not conflict with host save state.
FIX: Remove the module-scope math.randomseed call. If deterministic AI behaviour is needed, seed with a value derived from the host game seed rather than os.time().
---

---
MOD: G.A.M.M.A. Artefacts Reinvention
FILE: perk_based_artefacts.script (anonymous closure sub-finding)
CONFLICT TYPE: Memory Leak (anonymous callback closures)
SEVERITY: LOW
DETAILS: Uses a custom register_callback helper with anonymous function closures to register actor_on_update handlers for belt artefact effects. Because the closures have no name, they cannot be passed to UnregisterScriptCallback. They accumulate across level transitions.
OUR IMPACT: On long play sessions with multiple level transitions, unregistered actor_on_update closures accumulate in the callback table. Each closure holds a reference to its upvalue environment, preventing garbage collection. This is a memory leak that grows proportionally with the number of level transitions. In MP sessions (which may have longer continuous play than SP), this could contribute to memory pressure and eventual crash.
FIX: Replace all anonymous closure registrations with named module-level functions that can be properly unregistered on level transition cleanup callbacks (actor_on_before_death or actor_on_exit_level).
---

---
MOD: G.A.M.M.A. Binoculars Rework
FILE: bas_nvg_scopes.script
CONFLICT TYPE: Callback Collision (minor)
SEVERITY: LOW
DETAILS: Dynamically registers and unregisters actor_on_update (bas_actor_on_update, named function) when scoping in/out with NV-capable weapons. The listener fires every 500ms and only calls do_check() which manipulates post-process effectors — purely visual, no A-Life or save state writes.
OUR IMPACT: The named dynamic registration pattern is safe and correctly cleaned up. The only MP consideration is that post-process effectors are local to each client's renderer, so there is no sync concern. No conflict with our actor_on_update listener.
FIX: No action required. Confirm post-process effector IDs (8020) do not collide with any effector IDs used by our MP code.
---

---
MOD: Flueno's Safer Artifact Melting
FILE: safer_af_crafting_mcm.script
CONFLICT TYPE: A-Life Dependency (minor)
SEVERITY: LOW
DETAILS: actor_on_update listener throttled to 1000ms. Reads db.actor:get_artefact_count() and calls db.actor:change_radiation() to apply radiation during artefact melting. All operations are local actor-state reads and writes with no A-Life or network calls.
OUR IMPACT: db.actor:change_radiation() is a local call that modifies only the client actor's radiation level. In MP this means each client's radiation state during artefact melting is independent, which is acceptable for a client-side gameplay mechanic. No conflict with our callbacks.
FIX: No action required. Document that artefact melting radiation is client-local and does not sync to other players.
---

---
MOD: G.A.M.M.A. Actor Damage Balancer
FILE: grok_bleed_icon.script
CONFLICT TYPE: Callback Collision (benign)
SEVERITY: LOW
DETAILS: Registers actor_on_update. Handler reads db.actor.bleeding and updates a HUD bleed icon. Throttled internally. No A-Life calls, no save writes, no shared state modifications.
OUR IMPACT: Adds one more actor_on_update listener to the callback chain. Impact is negligible — purely a HUD update with no MP state interaction. The bleed icon is local to each client's HUD.
FIX: No action required.
---

---
MOD: Demonized More Dangerous Phantoms
FILE: more_dangerous_phantoms.script
CONFLICT TYPE: Entity Lifecycle Interference (minor)
SEVERITY: LOW
DETAILS: Wraps phantom_manager.Phantom.net_destroy to call db.actor:hit() on phantom death. db.actor:hit() is a local call. Also writes psy_table.actor_psy_health to m_data in a save_state callback.
OUR IMPACT: db.actor:hit() is local to the calling client — in MP, this means only the client who killed the phantom takes the psy hit, which is arguably correct behaviour. The m_data write is client-local. No A-Life calls, no server-entity operations. The monkey-patch on phantom_manager.Phantom.net_destroy is fragile (will break if another mod also wraps it) but does not conflict with our MP code directly.
FIX: No action required from MP perspective. Note the fragile monkey-patch for general mod compatibility tracking.
---

---
MOD: Fuji's ISG Teleport
FILE: fuji_magician.script
CONFLICT TYPE: None identified
SEVERITY: LOW
DETAILS: Pre-identified as a suspect for teleport_object usage. Actual code uses st:set_npc_position(post_pos) (NPC server-entity position setter) rather than teleport_object or force_set_position. Registers npc_on_before_hit callback (not one of our 7 registered callbacks). No alife_create, alife_release, or direct A-Life API calls found. No SE class overrides.
OUR IMPACT: st:set_npc_position on the server entity is a host-side operation by definition (SE object position). In MP this is fine as long as the call originates from the host. The npc_on_before_hit callback does not conflict with our registered callbacks.
FIX: No action required. Verify that npc_on_before_hit callbacks chain correctly in the MP framework (it is not one of our registered callbacks, so it fires independently).
---


## MODS CONFIRMED CLEAN (Asset-only or no MP-relevant script patterns)

The following 28 mods were audited and contain no Lua scripts, or contain scripts with no A-Life calls, no callback registrations overlapping our 7 callbacks, no SE class overrides, and no save-state writes that could conflict with MP operation.

- A New Day - ENB for GAMMA (asset-only: shaders, textures)
- Absolute Nature Redux 2023 (asset-only: textures)
- Alternative Hands for GAMMA (asset-only: meshes, textures)
- Better Blowout and Psi-Storm Visuals (asset-only: particles, textures)
- Better Combat Wounds and Deaths (asset-only: meshes, animations)
- Better PDA Maps 1.3 (asset-only: textures)
- Better Sleeping Bags (asset-only: ltx configs, textures)
- Bon Appetit - Food Rework (asset-only: ltx configs, textures)
- Chromatic Aberration Remover (asset-only: shader config)
- Dead Body Collision (ltx config only: physics parameters)
- Faceless GAMMA - Character Overhaul (asset-only: meshes, textures)
- Footsteps and STALKER sounds Redux (asset-only: sounds)
- G.A.M.M.A. Alife optimization (ltx config only: alife timing parameters, no scripts)
- G.A.M.M.A. Arzsi's Mutants Bleeding Fixes (script is empty by design: --- Empty on purpose ---)
- GAMMA Dead Zone (asset-only: zone configs, textures)
- GAMMA HD Models Pack (asset-only: meshes, textures)
- GAMMA Music Pack (asset-only: sounds)
- GAMMA Shader Overhaul (asset-only: shaders)
- GAMMA Tactical Flashlights (asset-only: ltx, textures)
- Haul Them All - Body Drag (ltx config only)
- HD Sunrise Mod (asset-only: textures)
- More Blowout Screenspace and Enhanced Rad Zone (asset-only: particles, textures)
- No Hand Shaking (asset-only: animation configs)
- Novice Rescuer Voice Lines (asset-only: sounds, ltx)
- Photorealistic Zone (asset-only: textures)
- Resonance -- Desolation Ambience (asset-only: sounds)
- SCAR - Anomaly Scars (asset-only: textures, particles)
- STALKER Food and Drug Animations Rework (asset-only: animations, meshes)


## SUMMARY TABLE

| MOD | FILE | SEVERITY | CONFLICT TYPE |
|-----|------|----------|---------------|
| G.A.M.M.A. Artefacts Reinvention | zz_item_artefact.script | CRITICAL | Callback Collision + Entity Lifecycle |
| G.A.M.M.A. Artefacts Reinvention | perk_based_artefacts.script | CRITICAL | Entity Lifecycle + A-Life Dependency |
| G.A.M.M.A. Alife fixes | alife_storage_manager.script | CRITICAL | Entity Lifecycle + A-Life Dependency |
| G.A.M.M.A. Agroprom Underground Remake | agroprom_drugkit_spawner_gamma.script | CRITICAL | Entity Lifecycle + A-Life Dependency |
| Dark Valley Lamp Remover | dark_valley_lamp_remover.script | CRITICAL | Entity Lifecycle + A-Life Dependency |
| Darkasleif's Cars Fixes | LevelChangeCars.script | HIGH | Save Hook Field Mismatch |
| G.A.M.M.A. Artefacts Reinvention | grok_artefacts_random_spawner.script | HIGH | A-Life Dependency + Callback Collision |
| G.A.M.M.A. Artefacts Reinvention | exo_loot.script | HIGH | Entity Lifecycle Interference |
| G.A.M.M.A. Artefacts Reinvention | dialogs_agr_u.script | HIGH | A-Life Dependency + Entity Lifecycle |
| G.A.M.M.A. Arti Recipes Overhaul | zzzz_arti_jamming_repairs.script | HIGH | Entity Lifecycle + Raw A-Life Register |
| G.A.M.M.A. AI Rework | xr_conditions.script | HIGH | A-Life Dependency + SIMBOARD Access |
| G.A.M.M.A. Better Quick Release System | item_backpack.script | HIGH | Entity Lifecycle Interference |
| G.A.M.M.A. Artefacts Reinvention | zz_item_artefact.script (actor_on_update) | MEDIUM | Callback Collision (overhead) |
| Demonized FDDA New Time Events | demonized_time_events.script | MEDIUM | Duplicate Global Definition |
| Asnen's and Grok's Better Cigarettes Animations | enhanced_animations.script | MEDIUM | Entity Lifecycle Interference |
| G.A.M.M.A. Actor Damage Balancer | momopate_pba_tweaks.script | MEDIUM | Entity Lifecycle Interference |
| G.A.M.M.A. Artefacts Reinvention | grok_artefacts_melter_charge.script | MEDIUM | Entity Lifecycle Interference |
| G.A.M.M.A. Arti Recipes Overhaul | custom_functor_autoinject.script | MEDIUM | Entity Lifecycle Interference |
| G.A.M.M.A. Arti Recipes Overhaul | workshop_autoinject.script | MEDIUM | Entity Lifecycle Interference |
| G.A.M.M.A. Arti Recipes Overhaul | trader_autoinject.script | MEDIUM | Entity Lifecycle Interference |
| G.A.M.M.A. AI Rework | schemes_ai_gamma.script | LOW | RNG Pollution |
| G.A.M.M.A. Artefacts Reinvention | perk_based_artefacts.script (closures) | LOW | Memory Leak |
| G.A.M.M.A. Binoculars Rework | bas_nvg_scopes.script | LOW | Callback Collision (benign) |
| Flueno's Safer Artifact Melting | safer_af_crafting_mcm.script | LOW | A-Life Dependency (minor) |
| G.A.M.M.A. Actor Damage Balancer | grok_bleed_icon.script | LOW | Callback Collision (benign) |
| Demonized More Dangerous Phantoms | more_dangerous_phantoms.script | LOW | Entity Lifecycle (minor) |
| Fuji's ISG Teleport | fuji_magician.script | LOW | None identified |

**Totals:** 5 CRITICAL, 7 HIGH, 8 MEDIUM, 7 LOW, 28 CLEAN
