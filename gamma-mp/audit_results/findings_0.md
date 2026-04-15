# Audit Findings - Chunk 0

---
MOD: 207- Mags Redux (Disable G.A.M.M.A. Unjam Reload) - RavenAscendant
FILE: magazines.script
CONFLICT TYPE: Callback Collisions
SEVERITY: HIGH
DETAILS: Registers server_entity_on_unregister (se_item_on_unregister) and actor_on_update. The se_item_on_unregister callback fires on every entity unregister event and clears the mod internal magazine data table for that entity ID.
OUR IMPACT: Our server_entity_on_unregister fires on the host to broadcast despawn and update _tracked_entities. Mags Redux handler fires alongside it (additive). On the CLIENT with A-Life suppressed, server entity events may not fire at all, leaving stale magazine data tables that accumulate over the session.
FIX: Confirm se_item_on_unregister only reads/writes the mod own mag_data table and never calls alife() directly. Wrap callback registration behind is_mp_client() guard on the client.

---
MOD: 207- Mags Redux (Disable G.A.M.M.A. Unjam Reload) - RavenAscendant
FILE: magazine_binder.script
CONFLICT TYPE: Callback Collisions
SEVERITY: HIGH
DETAILS: Registers a second independent server_entity_on_unregister callback (se_item_on_unregister) -- separate from the one in magazines.script. Both magazines.script and magazine_binder.script independently hook server_entity_on_unregister, meaning the callback fires twice from Mags Redux alone on every entity unregister event.
OUR IMPACT: Two concurrent Mags Redux cleanup callbacks alongside our own handler on every unregister event. On the client with A-Life suppressed unregister events may not fire at all, leaving mag data stale.
FIX: Audit both se_item_on_unregister implementations to confirm neither calls alife():release() or writes to globally shared state. Add is_mp_client() guards around callback registration.

---
MOD: 207- Mags Redux (Disable G.A.M.M.A. Unjam Reload) - RavenAscendant
FILE: magazines_loot.script
CONFLICT TYPE: Callback Collisions + Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Registers npc_on_death_callback (as npc_on_death). Inside the callback, calls alife_create_item(to_create, npc) to spawn magazine items on the dead NPC body. alife_create_item is a wrapper around alife():create().
OUR IMPACT: Our npc_on_death_callback fires on the host to broadcast the death event. Mags Redux death callback also fires and creates new entities (magazines) on the NPC body. These spawned entities will NOT be in _tracked_entities -- clients will never receive a spawn broadcast for those items. Looting those magazines on a client will desync inventory state.
FIX: On the host, route magazine item creation in npc_on_death through the MP entity tracking path. Suppress loot spawning on clients and rely on host broadcast.

---
MOD: 207- Mags Redux (Disable G.A.M.M.A. Unjam Reload) - RavenAscendant
FILE: actor_stash_patch.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Calls alife_create("inv_backpack", ...) in two places -- one when the actor drops/stores items and once on actor death -- creating a backpack stash entity in the world.
OUR IMPACT: Backpack entities created here are not in _tracked_entities. On the host they exist in the world but will never be broadcast to clients. On the client with A-Life suppressed, alife_create may silently fail or produce a local ghost entity invisible to the host.
FIX: Route backpack spawning through the MP entity creation path. Add is_mp_client() guard to prevent the client from calling alife_create directly.

---
MOD: 207- Mags Redux (Disable G.A.M.M.A. Unjam Reload) - RavenAscendant
FILE: wep_binder.script
CONFLICT TYPE: Callback Collisions
SEVERITY: LOW
DETAILS: The entire file is commented out. The previously flagged server_entity_on_register hook is fully disabled -- all code is in block comments. No active callbacks or function registrations exist.
OUR IMPACT: None. The file is inert.
FIX: No action required.

---
MOD: 234- Dynamic Anomalies Overhaul - Demonized
FILE: drx_da_main.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: CRITICAL
DETAILS: Calls alife():create(anom_type, pos, lvid, gvid) directly (line 1221) to spawn dynamic anomaly zone objects. Also calls alife():release(obj, true) in multiple locations (lines 762, 884, 921, 1211, 3410, 3447) to despawn anomalies and clean up old ones. These are raw alife() calls, not wrappers.
OUR IMPACT: Dynamic anomaly entities spawned via alife():create() bypass _tracked_entities entirely. On the HOST, anomalies exist server-side but clients will never receive a spawn broadcast. On the CLIENT, calling alife():create() when A-Life is suppressed will crash or create orphan entities. The alife():release() calls for anomaly despawn similarly bypass our untracking and broadcast path.
FIX: CRITICAL for client. Wrap all alife():create() and alife():release() calls with guard: if not is_mp_client() then ... end. For full MP support, route anomaly lifecycle through the MP entity create/destroy broadcast system so clients receive anomaly state.

---
MOD: 234- Dynamic Anomalies Overhaul - Demonized
FILE: drx_da_main.script
CONFLICT TYPE: Weather/Time Override
SEVERITY: HIGH
DETAILS: Calls level.change_game_time(0, change_hours, change_minutes) (line 2911) when the player is hit by a Flash anomaly (anomalies_hit_functions.zone_mine_flash). Time jump is random: 3-8 hours plus 1-59 minutes.
OUR IMPACT: Our MP code syncs game time from host to all clients. If the Flash anomaly triggers a time jump on the HOST, the host time advances without clients being notified of the exact delta. If triggered on the CLIENT, it directly conflicts with our time sync by advancing client time independently.
FIX: On the host, broadcast the time-change delta to clients after the anomaly fires. On the client, disable zone_mine_flash time-change by checking is_mp_client() and relying on host sync.

---
MOD: 234- Dynamic Anomalies Overhaul - Demonized
FILE: drx_da_main.script
CONFLICT TYPE: A-Life Dependency
SEVERITY: HIGH
DETAILS: Registers actor_on_update callback (drx_da_actor_on_update_callback) which drives the entire dynamic anomaly update loop on a 100ms timer. This loop iterates SIMBOARD.smarts_by_names in multiple locations, calls alife():release() for old anomalies, and calls alife():create() for new anomaly spawns.
OUR IMPACT: On the CLIENT where A-Life is suppressed, this update loop still runs every 100ms. Every call to alife():create() or alife():release() inside will fail silently or crash. SIMBOARD data may be stale or unavailable. This creates a persistent error condition on every client update tick.
FIX: Guard the entire drx_da_actor_on_update_callback body with: if is_mp_client() then return end. Anomaly state must be received from the host via sync, not generated locally.

---
MOD: 245- Hideout Furniture 1.2.0 - Aoldri
FILE: placeable_furniture.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Calls alife_create(world_obj, place_coordinates, ...) (line 50) when the player places furniture, and alife():release(alife():object(place_obj_id), true) (line 214) when confirming placement to consume the held inventory item. Also registers actor_on_update for placement preview loop.
OUR IMPACT: Furniture spawned via alife_create is not in _tracked_entities. On the host, placed furniture will not be broadcast to clients -- clients see nothing. The alife():release() call for the consumed item also bypasses our untracking and despawn broadcast. On the client with A-Life suppressed, both calls fail.
FIX: Intercept alife_create in the placement path, register the returned entity with _tracked_entities, and broadcast a spawn packet to clients. Add is_mp_client() guard to prevent clients from calling placement directly.

---
MOD: 245- Hideout Furniture 1.2.0 - Aoldri
FILE: bind_workshop_furniture.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Calls alife_create("workshop_stash", pos, ...) (line 31) to create a hidden stash container when a workshop furniture object is bound to the game world.
OUR IMPACT: Workshop stash entities are not tracked in _tracked_entities. Clients will not receive the entity and any interaction with workshop stash will desync. alife_create on the client with A-Life suppressed will fail.
FIX: Route workshop stash creation through MP entity tracking. Guard client calls with is_mp_client().

---
MOD: 245- Hideout Furniture 1.2.0 - Aoldri
FILE: hf_monkeypatches.script
CONFLICT TYPE: Global Table Pollution
SEVERITY: MEDIUM
DETAILS: Monkey-patches ui_inventory.UIInventory:LMode_TakeAll() by completely replacing the method on the class table. The replacement adds stash removal logic and calls alife_release and alife_create_item inside. The original function is not chained -- it is captured in a remove_stash closure but the TakeAll replacement is a full override.
OUR IMPACT: If our MP code or another mod also patches UIInventory:LMode_TakeAll, the last-loaded patch wins and earlier ones are silently dropped. The alife_release call inside also runs entity release outside our tracking path.
FIX: Confirm load order. Use a chained patch pattern (save old function reference, always call it, then add new behavior) rather than full replacement.

---
MOD: 265- NPCs Die in Emissions for Real - TheMrDemonized
FILE: surge_manager.script
CONFLICT TYPE: Entity Lifecycle Interference + A-Life Dependency
SEVERITY: HIGH
DETAILS: Overrides the base surge_manager.script entirely. In CSurgeManager:turn_to_zombie() (lines 1578, 1581), calls alife():release(se_obj) to delete a stalker and alife_create(zombie_type, pos, lvid, gvid) to spawn a zombie replacement. In CSurgeManager:explode() (line 1601), calls alife():release(se_obj). These run during emission processing driven by AddUniqueCall(main_loop).
OUR IMPACT: NPC deletion and zombie replacement during emissions bypasses MP tracking. On the host, _tracked_entities has orphan entries for deleted stalkers and no entries for new zombies. Clients see NPCs disappear without despawn events and zombies appear without spawn events. On the client with A-Life suppressed, alife():release() and alife_create() fail, breaking the entire emission kill logic.
FIX: Guard emission kill/zombify operations with is_mp_client() check. On the host after alife():release() and alife_create(), emit broadcast packets for despawn and spawn. Add new zombie entities to _tracked_entities.

---
MOD: 265- NPCs Die in Emissions for Real - TheMrDemonized
FILE: surge_manager.script
CONFLICT TYPE: Weather/Time Override
SEVERITY: MEDIUM
DETAILS: Calls level.set_time_factor(surge_time_factor) (lines 294, 366, 429) and level.set_time_factor(normal_time_factor) (lines 67, 325, 388) during emission start/end. Runs via AddUniqueCall which fires independent of A-Life suppression, meaning it runs on all clients.
OUR IMPACT: Our MP code syncs time factor via level.set_time_factor(). The surge manager independently sets the time factor on both HOST and CLIENT. On the client this directly fights our sync. On the host, time factor changes are not broadcast to clients.
FIX: Add is_mp_client() guard at the top of main_loop to suppress it on clients. On the host, broadcast the new time factor to all clients after setting it.

---
MOD: 265- NPCs Die in Emissions for Real - TheMrDemonized
FILE: zz_surge_manager_npc_die.script
CONFLICT TYPE: Global Table Pollution + Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Monkey-patches psi_storm_manager.CPsiStormManager.kill_objects_at_pos by completely replacing the method on the class table without chaining. The replacement calls sm:turn_to_zombie() and sm:explode() which internally call alife():release() and alife_create() during psi-storm processing.
OUR IMPACT: Full class method replacement -- if another mod also patches this method, the last loader wins. The alife():release() and alife_create() calls within are untracked entity lifecycle operations. On the client with A-Life suppressed this will fail or crash.
FIX: Guard A-Life calls with is_mp_client(). Use a chained monkey-patch approach (save old method, call it, then extend) to avoid clobbering other mods.

---
MOD: 203- YACS Better Campfire Saves (forces campfire saves but they are better) - Ishmaeel
FILE: ish_campfire_saving.script
CONFLICT TYPE: Save System Interference
SEVERITY: HIGH
DETAILS: Registers on_before_save_input and sets flags.ret = true to block saves when not near a lit campfire or friendly base. The GAMMA MCM dispatcher in ui_main_menu.script reads flags.ret (not flags.ret_value) at lines 171 and 334 to decide whether to block the save. Also reads SIMBOARD.smarts_by_names inside get_friendly_bases() at save-block time.
OUR IMPACT: CRITICAL field name mismatch. Our MP on_before_save_input sets flags.ret_value = false to block client saves. However the GAMMA MCM dispatcher checks flags.ret -- our save blocker uses the wrong field name and will NOT actually block saves on clients. YACS correctly sets flags.ret = true but its campfire check may ALLOW saves near a campfire, permitting clients to save when MP should block them.
FIX: Change our MP on_before_save_input to set flags.ret = true (matching the MCM dispatcher) in addition to or instead of flags.ret_value = false. Verify which field the engine natively checks for the F5 quicksave path vs the menu save path and cover both.

---
MOD: 203- YACS Better Campfire Saves (forces campfire saves but they are better) - Ishmaeel
FILE: ish_campfire_saving.script
CONFLICT TYPE: A-Life Dependency
SEVERITY: MEDIUM
DETAILS: get_friendly_bases() iterates SIMBOARD.smarts_by_names and reads smart.is_on_actor_level, smart.dist_to_actor, and smart.props. This runs inside on_before_save_input whenever a save is attempted.
OUR IMPACT: If the flag field issue above is not fixed and clients can still trigger save attempts, this SIMBOARD iteration will run on the client where SIMBOARD may be stale or nil, potentially causing nil-access errors.
FIX: Fix the flag field issue first. As a safety measure add: if is_mp_client() then flags.ret = true; return end at the top of on_before_save_input in YACS.

---
MOD: 225- Placeable Campfires - xcvb
FILE: campfire_placeable.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Calls alife_create(ph_sec or "ph_campfiremod", pos, ...) (line 158) to spawn the physical campfire prop, and alife_create("campfire", new_pos, ...) (line 169) to spawn the campfire entity. Also calls level.change_game_time(0, 0, game_minutes) (lines 135, 243) when preparing campfire placement.
OUR IMPACT: Both campfire entities created via alife_create are not in _tracked_entities. Clients will never receive them. The level.change_game_time() calls conflict with our time sync -- on the host these advance game time without broadcasting to clients; on the client they fight our sync directly.
FIX: Route campfire entity creation through MP tracking and broadcast to clients. Guard level.change_game_time() calls: on the host broadcast the delta after the call; on the client suppress local calls and rely on host sync.

---
MOD: 248- Night Mutants - xcvb
FILE: night_mutants.script
CONFLICT TYPE: SIMBOARD/Squad Manipulation + A-Life Dependency
SEVERITY: HIGH
DETAILS: Registers actor_on_update (as try_to_spawn) which runs every 30 seconds and calls SIMBOARD:create_squad(smart, squad_sec) (line 121) to spawn mutant squads at night. Directly accesses SIMBOARD.smarts and SIMBOARD.smarts_by_names tables. Calls alife():actor() and alife():level_name() inside the update loop. Also registers server_entity_on_unregister to track when spawned squads are deleted.
OUR IMPACT: actor_on_update runs on both host and client. On the CLIENT, SIMBOARD:create_squad() with A-Life suppressed will fail or crash. alife():actor() returns nil on the client (used in simulation_objects.is_on_the_same_level at line 222) causing a nil-deref. Spawned squads are not in _tracked_entities regardless -- clients never receive them.
FIX: Guard try_to_spawn with is_mp_client() check -- mutant spawning is host-authoritative. After SIMBOARD:create_squad() succeeds on the host, register new squad entities in _tracked_entities and broadcast to clients.

---
MOD: 211- NPC Loot Claim (NPCs will kill you if you loot what they killed) - Vintar0 & Nullblank
FILE: npc_loot_claim.script
CONFLICT TYPE: Callback Collisions + A-Life Dependency
SEVERITY: MEDIUM
DETAILS: Registers npc_on_death_callback. The handler only writes to the local loot_claims table (no alife():create/release). When the actor loots a body, the mod iterates SIMBOARD.smarts_by_names and SIMBOARD.smarts[smart.id].squads (lines 89-116) and calls simulation_objects.is_on_the_same_level(alife():actor(), smart) (line 90).
OUR IMPACT: On the HOST the death callback is benign. The SIMBOARD iteration runs on the client when the local player opens a corpse inventory. With A-Life suppressed, alife():actor() at line 90 will return nil and cause a nil-deref error when the client player tries to loot a corpse.
FIX: Add a nil-guard on alife():actor() in is_on_the_same_level. For MP add is_mp_client() logic that skips the SIMBOARD iteration, or disable loot-claim enforcement on clients entirely.

---
MOD: 156- No Exos in the South - Grokitach
FILE: grok_nes.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: In npc_on_update callback, when an NPC wearing exoskeleton-tier armor is detected in a southern zone, sets their health to 0 and schedules alife():release(alife():object(npc:id())) via a 0.15-second time event (line 289). Direct raw alife():release() call.
OUR IMPACT: alife():release() bypasses _tracked_entities untracking and the MP despawn broadcast. On the host, clients see the NPC disappear without receiving a despawn packet. On the CLIENT with A-Life suppressed, alife():release() will fail.
FIX: Guard the time event creation with is_mp_client() check. On the host after alife():release(), emit a despawn broadcast and remove from _tracked_entities.

---
MOD: 156- No Exos in the South - Grokitach
FILE: grok_no_north_faction_in_south.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: HIGH
DETAILS: Identical pattern to grok_nes.script. Calls alife():release(alife():object(npc:id())) in a time event (line 278) for NPCs from northern factions detected in southern zones.
OUR IMPACT: Same as grok_nes.script -- direct alife():release() bypasses MP tracking and despawn broadcast. Fails on client with A-Life suppressed.
FIX: Same as grok_nes.script -- guard with is_mp_client() and route through MP despawn broadcast on host.

---
MOD: 147- Streamlined Upgrades - arti
FILE: kit_binder.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: MEDIUM
DETAILS: In kit_binder:update() (fires on first update of an upgrade kit object), calls alife_create(new_sec, pos, lvid, gvid, pid) (lines 36, 38) to replace old upgrade kit item sections with new ones, then calls alife_release_id(id) to delete the original item.
OUR IMPACT: Upgrade kit conversion (old item deleted, new item spawned) runs without going through _tracked_entities. On the host, the replaced item entity will not be broadcast to clients. On the client, alife_create with A-Life suppressed will fail.
FIX: Guard alife_create and alife_release_id in kit_binder:update() with is_mp_client() check. Item swap should be host-authoritative and broadcast via MP entity system.

---
MOD: 11- Preblowout Murder - Ethylia
FILE: surge_manager.script
CONFLICT TYPE: Weather/Time Override + A-Life Dependency
SEVERITY: MEDIUM
DETAILS: Overrides the base surge_manager.script (without the NPC-kill additions of mod 265). Calls level.set_time_factor() at lines 68, 245, 325, 388. Reads SIMBOARD at line 1318. Runs via AddUniqueCall(main_loop) which fires on all clients independent of A-Life suppression. NOTE: Both mod 11 and mod 265 provide a surge_manager.script -- whichever loads last wins; they cannot coexist.
OUR IMPACT: level.set_time_factor() calls on the client fight our time sync. main_loop runs on clients with A-Life suppressed. Load order conflict with mod 265 means only one version is active -- must determine which.
FIX: Determine which surge_manager.script wins by load order. Add is_mp_client() guard at the top of main_loop in whichever version is active. On the host, broadcast time factor changes after setting them.

---
MOD: 115- Campfire slowly regens life - arti
FILE: cozy_campfire.script
CONFLICT TYPE: Callback Collisions
SEVERITY: LOW
DETAILS: Registers actor_on_update. Checks if the player is within 10 units of a lit campfire and calls db.actor:change_health(0.002) every 800ms. Does not touch A-Life, flags, or shared tables.
OUR IMPACT: Applies health regen locally on the client independent of the host, causing minor HP desync. The client HP will drift slightly from what the host tracks. Cosmetic desync only, not a crash.
FIX: LOW priority. Optionally add is_mp_client() guard or have health regen be host-driven and synced.

---
MOD: 108- Remove dropping weapons from damage - Great_Day
FILE: actor_effects.script
CONFLICT TYPE: Callback Collisions
SEVERITY: LOW
DETAILS: Registers actor_on_update. Manages bleeding, breathing, radiation HUD, blood overlay, mask effects, impact reactions, item swap animations, stamina HUD, and fog. Also registers actor_on_weapon_before_fire which sets flags.ret_value = false to block weapon firing in certain states -- this is the weapon-fire flags object, not the save-input flags.
OUR IMPACT: All effects are local to the player client. The flags.ret_value = false in actor_on_weapon_before_fire targets the weapon-fire flags object, not the save-input flags -- no conflict with our save blocker. No functional MP conflict.
FIX: No action required for Phase 0.

---
MOD: 140- Weapon Parts Overhaul - arti
FILE: arti_jamming.script
CONFLICT TYPE: Callback Collisions
SEVERITY: LOW
DETAILS: Registers actor_on_update (manages weapon overheat state, purely local) and on_key_press (sets a local debug flag d_flag = true for a configured debug key). Neither handler modifies flags on the save/key-press path, calls alife(), or writes to globally shared tables.
OUR IMPACT: The on_key_press handler fires alongside ours but handles a different key and does not consume the event or modify any flags. No functional MP conflict.
FIX: No action required for Phase 0.

---
MOD: 189- Beef NVG - theRealBeef
FILE: z_beefs_nvgs.script
CONFLICT TYPE: Callback Collisions
SEVERITY: LOW
DETAILS: Registers on_key_press (line 640) and conditionally registers/unregisters actor_on_update based on NVG state. The on_key_press handler responds exclusively to the kWPN_FUNC key binding and adjusts NVG rendering shader parameters. Does not modify flags, does not call alife().
OUR IMPACT: Our on_key_press shows a tooltip on F5 quicksave blocked (client). Beef NVG listens for kWPN_FUNC, a completely different key -- no key conflict. Both callbacks fire independently for their respective inputs.
FIX: No action required for Phase 0.

---
MOD: 205- Old to ammo to new ammo converter (less item bloat) - Great_Day
FILE: item_weapon.script
CONFLICT TYPE: Callback Collisions
SEVERITY: LOW
DETAILS: Registers actor_on_update for weapon overheat tracking (line 1039). The actor_on_update handler only calls update_overheat() reading local weapon state. The alife_create_item calls elsewhere in the file are inside actor_on_item_use and NPC inventory drag-drop callbacks, not in the update handler.
OUR IMPACT: The actor_on_update handler is local weapon state management with no MP-relevant side effects. The alife_create_item calls in item-use/conversion callbacks are a general untracked-entity gap but LOW severity for Phase 0 as they only trigger on deliberate player action.
FIX: No action required for the actor_on_update conflict. Note the item-conversion alife_create_item calls as a general untracked-entity gap for a future MP item-sync solution.
