# Audit Findings - Chunk 5

**Audited:** 51 mods, base directory `modpack_addons/`
**Date:** 2026-04-15
**Scope:** All 8 conflict types checked against MP code callbacks and engine API.

---

## CRITICAL CONFLICTS

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: sim_squad_scripted.script
CONFLICT TYPE: Callback Collisions + SIMBOARD/Squad + Entity Lifecycle
SEVERITY: CRITICAL
DETAILS: sim_squad_scripted:on_register() calls SendScriptCallback("server_entity_on_register", self, "sim_squad_scripted") and on_unregister() calls SendScriptCallback("server_entity_on_unregister", self, "sim_squad_scripted"). Calls SIMBOARD:assign_squad_to_smart(self, nil) and mutates SIMBOARD.squads[self.id] at lines 417, 472, 1019-1020, 1380. smr_pop.script calls alife_create(section, smart) (line 1177), alife_release(npc) (line 1120), alife_release_id(squad.id) (lines 1122, 1320), and alife_create(mrs, smart) (line 1343). sim_board.script create_squad() (line 131) calls alife_create(...) internally (line 139). game_setup.script registers actor_on_update (line 559), calls alife_release(se_obj) (lines 408, 432) and squad:remove_squad() (line 476).
OUR IMPACT: (1) Our server_entity_on_register handler on the client fires for every sim-squad and smart-terrain ZCP creates -- corrupts client ID-mapping table with host-only entities. (2) alife_create/alife_release from smr_pop run client-side with suppressed A-Life -- silently fail or produce orphaned server objects never cleaned from entity registry. (3) game_setup.actor_on_update calls squad:remove_squad() on the client, attempting to release server objects the client does not own. (4) SIMBOARD:assign_squad_to_smart mutations desynchronise smart terrain population counts between host and client.
FIX: Stub out or early-return from smr_pop.smr_handle_spawn, all smr_pop spawn/release calls, and game_setup.actor_on_update squad-removal block on the client with is_mp_client() guards. Guard our server_entity_on_register listener to ignore "sim_squad_scripted" and "se_smart_terrain" source tags on the client. Wrap the entire ZCP smr_pop spawn pipeline with a host-only guard.

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: smart_terrain.script
CONFLICT TYPE: Callback Collisions + SIMBOARD/Squad
SEVERITY: CRITICAL
DETAILS: se_smart_terrain:on_register() calls SendScriptCallback("server_entity_on_register", self, "se_smart_terrain") (line 142). se_smart_terrain:on_unregister() calls SendScriptCallback("server_entity_on_unregister", self, "se_smart_terrain") (line 184). SIMBOARD:init_smart(self) called on register (line 169), SIMBOARD:unregister_smart(self) on unregister (line 183). se_smart_terrain:try_respawn() calls SIMBOARD:assign_squad_to_smart(squad, self.id) (line 1472).
OUR IMPACT: Every smart terrain that comes online fires our server_entity_on_register callback on the client, triggering spawn-interception/ID-mapping logic for objects that should only be tracked by the host. SIMBOARD:init_smart/unregister_smart run on both client and host -- with suppressed A-Life the SIMBOARD smart registry on the client diverges from the host, causing lookup failures when our code calls SIMBOARD:get_smart_by_name() or SIMBOARD:assign_squad_to_smart() for sync operations.
FIX: In our server_entity_on_register handler, gate the ID-mapping logic by checking for source_tag == "sim_squad_scripted" or "se_smart_terrain" on the client. Those entities are managed exclusively by the host.

---
MOD: G.A.M.M.A. Vehicles in Darkscape
FILE: grok_vehicles_spawner.script
CONFLICT TYPE: Entity Lifecycle + Global Table Pollution
SEVERITY: CRITICAL
DETAILS: actor_on_first_update() calls alife():create(v[1], vector():set(v[2],v[3],v[4]), v[5], v[6]) directly for all entries in four vehicle tables (vtbl_darkscape, vtbl_zaton, vtbl_jupiter, vtbl_cnpp) -- 25+ vehicles spawned via direct alife():create() calls (lines 51, 58, 65, 72). Spawn state tracked via unlocalled globals: grok_vehicle_spawned, grok_vehicle_spawned_zaton, grok_vehicle_spawned_jupiter, grok_vehicle_spawned_cnpp. The four position tables are also unguarded globals.
OUR IMPACT: (1) alife():create() is the direct engine call (bypasses alife_create wrapper) and runs on the client during actor_on_first_update with suppressed A-Life -- produces engine error or silent skip, vehicles exist on host but absent from client entity registry, vehicle ID mapping fails. (2) If client executes the spawn, 25+ duplicate vehicle entities are created per client joining, corrupting world state. (3) Unscoped globals vulnerable to collision with any other script setting same-named globals.
FIX: Wrap actor_on_first_update vehicle-spawn block with is_mp_client guard. Host spawns vehicles once; clients receive them via entity sync. Convert position tables and spawn-flag globals to local.

---
MOD: G.A.M.M.A. YACS no quit
FILE: ish_campfire_saving.script
CONFLICT TYPE: Save System + Callback Collisions
SEVERITY: CRITICAL
DETAILS: Registers on_before_save_input (line 28) and sets flags.ret = true to block saves when away from a campfire. Registers on_key_release (line 33) and intercepts F5/Shift+F5 (line 194), calling create_emergency_save() which executes exec_console_cmd("save ...") directly. Both hooks run unconditionally. get_friendly_bases() (line 83) iterates SIMBOARD.smarts_by_names to find safe zones on every save attempt.
OUR IMPACT: Our on_before_save_input handler sets flags.ret_value = false (different field than YACS flags.ret). Depending on engine evaluation order, saves may be partially blocked or YACS block may override ours. Critically: create_emergency_save() calls exec_console_cmd("save ...") on Shift+F5, completely bypassing our save block on the client. Our on_key_press F5-tooltip also fires on the same key -- both handlers compete. SIMBOARD.smarts_by_names may be empty on the client (suppressed A-Life), causing is_within_friendly_base() to always return false.
FIX: On the client, wrap on_before_save_input to immediately set flags.ret = true and return (skip campfire/SIMBOARD logic). Disable create_emergency_save on the client. Ensure our on_before_save_input fires last to override any partial YACS state.

---

## HIGH CONFLICTS

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: smr_loot.script
CONFLICT TYPE: Callback Collisions + Entity Lifecycle
SEVERITY: HIGH
DETAILS: Registers npc_on_death_callback twice -- once conditionally on first update (line 411) and once unconditionally in on_game_start (line 442). Inside the callback calls alife_create_item(i, box) (line 225), with mag variants (line 273), and alife_create_item lines 341-342 -- creating loot items on corpse server-objects.
OUR IMPACT: Our MP code broadcasts death events via npc_on_death_callback from the host. On the client this callback also fires, attempting alife_create_item with suppressed A-Life -- silently fails, no loot drops on client-side corpses. If client A-Life is partially active, items are created client-side only, breaking loot sync. Double-registration risks the callback firing twice on the same death event.
FIX: Add is_mp_client guard at the top of npc_on_death_callback in smr_loot.script. Loot item creation must happen on the host only.

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: bind_anomaly_field.script
CONFLICT TYPE: Callback Collisions + Entity Lifecycle
SEVERITY: HIGH
DETAILS: Registers actor_on_update (line 543) for anomaly pulsing. Calls alife_create(section, vector():set(...), info.lvl_id, info.gm_id) at line 189 to spawn dynamic anomaly fields during actor_on_first_update.
OUR IMPACT: actor_on_update collision with our main MP update loop -- both fire every game update tick. The alife_create anomaly field spawn runs on every connected client; anomaly fields are double-spawned (once per client plus the host), creating phantom anomaly entities our ID mapping does not account for.
FIX: Guard the alife_create anomaly spawn with a host-only check. Confirm actor_on_update does not mutate any shared state also read by our update loop.

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: game_setup.script
CONFLICT TYPE: Callback Collisions + Entity Lifecycle + SIMBOARD/Squad
SEVERITY: HIGH
DETAILS: Registers actor_on_update (line 559). The update function (line 456) iterates SIMBOARD.squads and calls squad:remove_squad() on army squads at the actor level (line 476). Calls alife_release(se_obj) (lines 408, 432) and alife_create_item(section, {...}) (lines 249, 265) during world item setup in actor_on_first_update.
OUR IMPACT: squad:remove_squad() on the client attempts to release a server object the client does not own. alife_create_item during item setup silently fails on clients -- client world has no initial stash items, desyncing from host. actor_on_update adds a callback on top of our MP update loop.
FIX: Wrap the actor_on_update squad-removal block and actor_on_first_update item-spawn blocks with is_mp_client guards. Only the host should manage world item seeding and squad culling.

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: bind_awr.script
CONFLICT TYPE: Callback Collisions
SEVERITY: HIGH
DETAILS: Registers npc_on_death_callback (line 277). The callback (line 212) checks if victim is a workshop mechanic and calls OnDeath(victim) to toggle workshop lamps and send an actor_menu news item.
OUR IMPACT: Our MP code broadcasts NPC death events via npc_on_death_callback from the host. This callback also fires on the client. OnDeath(victim) uses level.object_by_id(id) to interact with workshop lamp objects -- which may not exist on the client with suppressed A-Life, causing nil-dereference errors. The news message appears for all players on every mechanic death rather than only the killing player.
FIX: Add is_mp_client guard at the top of npc_on_death_callback, or scope mechanic death events to the killing player only via host-side processing.

---
MOD: G_FLAT's Individualy Recruitable Companions
FILE: stalker_cloning_utility.script
CONFLICT TYPE: Entity Lifecycle + SIMBOARD/Squad
SEVERITY: HIGH
DETAILS: clone_stalker() calls alife_create(squad_section, pos, lvid, gvid) (line 14), squad:add_squad_member(sec, pos, lvid, gvid) (line 46), SIMBOARD:setup_squad_and_group(se_obj) (line 48), alife_release(se_item) (line 76) to clear inventory, and alife_create_item(sec, se_clone, {...}) (line 88) to duplicate inventory items. individually_recruitable_companions.script calls alife_release(npc) (lines 21, 45) to delete the original NPC.
OUR IMPACT: If a client recruits a companion, alife_create, alife_release, SIMBOARD:setup_squad_and_group, and alife_create_item all execute with suppressed A-Life -- squad creation and NPC release fail or produce orphaned entities. Our entity registry retains the original NPC ID (host never received the release); the clone will not exist in our ID mapping. Both players see different companion states.
FIX: Proxy companion recruitment through the host: client sends an RPC; host executes clone-and-release, confirms success, notifies client. Block direct execution of clone_stalker/alife_release(npc) on the client side.

---
MOD: Garbage Transition Point in Rostok CLOSER
FILE: lc_custom.script
CONFLICT TYPE: Entity Lifecycle + SIMBOARD/Squad + Position/Movement
SEVERITY: HIGH
DETAILS: actor_on_first_update() calls alife():create(sec, pos, vid, gid) (line 24) to spawn level-changer objects, then calls TeleportObject(se.id, pos, vid, gid) (line 31) to reposition them if out of place. TeleportObject wraps alife():teleport_object(...). Both run on every client. Uses SIMBOARD.smarts_by_names[v.smart].m_game_vertex_id (lines 23, 30, 66) to look up vertex IDs.
OUR IMPACT: alife():create() is the direct engine call (bypasses alife_create wrapper) and runs on the client with suppressed A-Life. Silent failure means transition points do not exist for clients; partial execution creates duplicate level-changer entities per client. TeleportObject -> alife():teleport_object() is our tracked position-sync API -- if it fires on the client it overrides host-authoritative position sync, corrupting location data. SIMBOARD.smarts_by_names lookup will return nil on client with suppressed A-Life, causing nil-dereference on the .m_game_vertex_id field access.
FIX: Wrap actor_on_first_update entirely with a host-only guard. Level-changer entities are persistent world objects -- host creates them once, clients receive them through entity sync. Add nil-check guard on SIMBOARD.smarts_by_names lookup.

---
MOD: G.A.M.M.A. Weapon Pack
FILE: close_combat_weapons_launchers.script
CONFLICT TYPE: Callback Collisions
SEVERITY: HIGH
DETAILS: Registers npc_on_death_callback (line 154). The callback (line 68) removes the dead NPC's ID from a local npc_with_launcher tracking table. Also registers npc_on_choose_weapon which modifies flags.gun_id per-NPC.
OUR IMPACT: Our npc_on_death_callback is the host-authoritative death broadcast. This callback also fires on the client. While the table cleanup is low-risk, npc_on_choose_weapon running on both host and client means weapon override logic is applied independently on each machine -- if NPC weapon assignments are replicated, clients and host may see different active weapons for the same NPC.
FIX: Add is_mp_client guard in npc_on_death_callback. Consider limiting npc_on_choose_weapon to the host since weapon assignments should be authoritative from the server.

---
MOD: Ishmaeel's Kill Tracker
FILE: ish_kill_tracker.script
CONFLICT TYPE: Callback Collisions
SEVERITY: HIGH
DETAILS: Registers both npc_on_death_callback (line 5) and monster_on_death_callback (line 7) -- two of our seven tracked MP callbacks. The callbacks call level.map_add_object_spot_ser(victim:id(), "deadbody_location") to add a map marker via the server-object ID.
OUR IMPACT: Our MP code uses npc_on_death_callback and monster_on_death_callback for death event broadcasting. Both callbacks fire on the client as well as the host. On the client level.map_add_object_spot_ser may attempt to modify server-object map spots that the client's suppressed A-Life cannot track correctly. Kill tracker fires on every instance -- markers appear for all clients for kills they did not make. Ordering dependency with our broadcast callbacks: if kill tracker fires before our MP broadcast, victim death is logged before the network message dispatches.
FIX: Wrap add_dot with is_mp_client guard -- map markers should only be added for the local killing player. Ensure our death broadcast callback is registered first so it fires before the tracker.

---

## MEDIUM CONFLICTS

---
MOD: G.A.M.M.A. Vices are free
FILE: xr_conditions.script
CONFLICT TYPE: SIMBOARD/Squad + A-Life Dependency
SEVERITY: MEDIUM
DETAILS: Contains ~15 direct reads from SIMBOARD.smarts_by_names[...], SIMBOARD.smarts[smart.id].squads, and two calls to SIMBOARD:get_smart_by_name(...) (lines 264, 273, 429, 444, 609, 760, 836, 1234, 1568, 1644, 1655, 1670, 1753, 1762, and others). These are condition-check functions invoked by NPC logic/dialogue/task scripts.
OUR IMPACT: These are read-only SIMBOARD accesses -- no state mutations -- so direct corruption risk is low. However with client A-Life suppressed, SIMBOARD.smarts may be empty or stale on the client, causing condition checks to return false for quests or NPC dialogue that depend on smart terrain population data. Quest condition evaluations will differ between host and client, potentially breaking shared task states.
FIX: MEDIUM priority -- no immediate crash risk. Document that ZCP/SIMBOARD-dependent condition checks in xr_conditions may produce incorrect results on clients. If faction-territory quests are shared in MP, forward condition evaluation to the host.

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: sim_board.script
CONFLICT TYPE: SIMBOARD/Squad + Entity Lifecycle
SEVERITY: MEDIUM
DETAILS: Defines simulation_board:create_squad() (line 131) which calls alife_create(...) (line 139). get_sim_board() initialises _G.SIMBOARD (line 390). clear() sets _G.SIMBOARD = nil (line 444). assign_squad_to_smart (line 240) mutates self.smarts[old_smart_id].population. This is the foundational SIMBOARD class that all ZCP population code extends.
OUR IMPACT: create_squad reachable from multiple code paths (smart terrain, smr_pop, civil war) means any client-side trigger reaches alife_create with suppressed A-Life. clear() setting _G.SIMBOARD = nil globally during level transitions on the client wipes the SIMBOARD reference our sync code may be holding, causing nil-dereference in our SIMBOARD:assign_squad_to_smart() and SIMBOARD:get_smart_by_name() calls.
FIX: Ensure clear() is not called on the client during MP sessions. Wrap create_squad with a host-only guard to prevent client-side squad creation through any code path.

---
MOD: G_FLAT's and Grok's Hunting Kit Rework
FILE: ui_mutant_loot.script
CONFLICT TYPE: Entity Lifecycle + Callback Collisions
SEVERITY: MEDIUM
DETAILS: Replaces the global ui_mutant_loot.loot_mutant function. Calls alife_create_item(sec, npc, item_prop_table) at lines 153 and 172 (hunting kit loot), and lines 418 and 436 (loot into actor inventory). Registers monster_on_actor_use_callback (line 250) and monster_on_loot_init (line 251).
OUR IMPACT: alife_create_item during mutant looting fires on the client with suppressed A-Life -- silently fails, no mutant part drops from hunting kit use on clients. monster_on_actor_use_callback registered alongside our monster_on_death_callback -- two competing callbacks modifying the same corpse loot state can cause ordering issues.
FIX: Wrap alife_create_item loot calls with host-authority checks or forward loot requests to the host. Treat all item creation as host-authoritative and sync resulting items to clients.

---
MOD: Momopate's Loot Stabilizer
FILE: momopate_savescummer_v2.script
CONFLICT TYPE: Global Table Pollution
SEVERITY: MEDIUM
DETAILS: Monkey-patches global functions by direct assignment at module load time: death_manager.set_weapon_drop_condition, ui_mutant_loot.loot_mutant, ui_mutant_loot.UIMutantLoot:Loot replaced with wrappers that call math.randomseed(npc:id()). Also conditionally patches zzzz_arti_jamming_repairs.weapon_eval_parts and zzzz_arti_jamming_repairs.custom_disassembly_weapon (lines 261, 274).
OUR IMPACT: math.randomseed is a global RNG state mutation -- runs on both host and client. If host and client independently seed RNG from the same npc:id() values at different times, their RNG states diverge from our MP code operations that may use math.random. The deterministic loot goal of Loot Stabilizer becomes counterproductive in MP where multiple machines seed independently from the same IDs.
FIX: RNG seeding in MP must be done on the host only, with the seed or resulting loot table transmitted to clients. Wrap all math.randomseed calls in the patched functions with not is_mp_client() guards.

---
MOD: Log spam remover
FILE: _g.script
CONFLICT TYPE: Global Table Pollution
SEVERITY: MEDIUM
DETAILS: Full replacement of _g.script -- the core utility library. Redefines printf as a no-op (lines 612-615: formats string but does nothing with the output). Defines global alife_create (line 2031), alife_release (line 2156), TeleportObject (line 513), alife_release_id (line 2207) wrappers. TeleportObject calls alife():teleport_object(id, gvid, lvid, pos) directly (line 519).
OUR IMPACT: (1) printf is silenced globally -- all our MP diagnostic logging via printf(...) is swallowed, making desync debugging impossible. (2) All mods in this chunk calling alife_create/alife_release/TeleportObject use this version of the wrapper -- if our MP client-mode guard is not present in these wrappers, every call from any mod hits the suppressed A-Life endpoint on the client without protection. (3) TeleportObject calls alife():teleport_object() directly -- our tracked position-sync API is exposed to any mod calling TeleportObject on the client.
FIX: Add client-mode guards into this _g.script's alife_create, alife_release, and TeleportObject wrappers -- if is_mp_client() is true, no-op or forward to a host RPC. Restore printf to log to file in MP debug builds.

---
MOD: G.A.M.M.A. Voiced Actor
FILE: ui_addon_companion_quick_menu.script
CONFLICT TYPE: Callback Collisions
SEVERITY: MEDIUM
DETAILS: Registers on_key_press (line 2). The handler (line 6) checks for kCUSTOM18 bind and plays a voiced actor line via AGDD_voiced_actor.actor_speak(...).
OUR IMPACT: Our MP code uses on_key_press for the F5 quicksave-blocked tooltip. Both handlers fire on every key press. If key-bind assignments overlap, or if the sound playback system queries game objects unavailable on client, nil-dereference errors can occur. Ordering is non-deterministic based on registration order.
FIX: LOW operational risk given different key binds. Ensure our on_key_press registration happens after this mod's to guarantee our F5 tooltip fires reliably. Add db.actor validity guard in the voiced actor handler to prevent nil-dereference on client.

---

## LOW CONFLICTS

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: smr_pop.script
CONFLICT TYPE: A-Life Dependency + SIMBOARD/Squad
SEVERITY: LOW
DETAILS: smr_handle_spawn() (called by smart_terrain.try_respawn() and simulation_board.fill_start_position()) calls SIMBOARD:create_squad(smart, squad_section) extensively (lines 1196-1238) and has post-spawn mutation loops calling alife_release and alife_create to re-populate squads (lines ~1290-1405). Entry point is an A-Life simulation tick -- should not fire with suppressed A-Life.
OUR IMPACT: LOW because A-Life suppression should prevent try_respawn from firing on clients. However there is a race window at session join before set_mp_client_mode(true) is called, during which A-Life may tick once and trigger these spawns.
FIX: Ensure alife():set_mp_client_mode(true) is called as early as possible on client join before the first A-Life update tick. Add is_mp_client guard inside smr_handle_spawn as belt-and-suspenders protection.

---
MOD: G_FLAT's Individualy Recruitable Companions
FILE: individually_recruitable_companions.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: LOW
DETAILS: become_actor_companion_individually and become_paid_actor_companion_individually_and_register call alife_release(npc) (lines 21, 45) to remove the original NPC, then use CreateTimeEvent to wait for the clone dialog. Player-initiated via dialogue.
OUR IMPACT: If a client opens the recruitment dialog, alife_release(npc) fires with suppressed A-Life -- release fails silently, original NPC remains, CreateTimeEvent loops indefinitely. LOW because clients would not normally initiate companion recruitment without host coordination.
FIX: Disable companion recruitment dialogs for clients, or proxy via RPC to host as described in the HIGH severity finding for stalker_cloning_utility.script.

---
MOD: G.A.M.M.A. Weapon Pack
FILE: trader_autoinject.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: LOW
DETAILS: Calls alife_create_item(k, npc) (line 199) to inject weapons into trader inventories during a trader interaction callback.
OUR IMPACT: alife_create_item fires on the client with suppressed A-Life, silently failing. Trader inventory appears different between host and client. LOW because trader interactions are typically single-player in co-op.
FIX: Wrap alife_create_item with a host-only guard or trigger trader inventory seeding from the host on session start.

---
MOD: No BNVG FDDA Redone Patch
FILE: item_device.script
CONFLICT TYPE: Callback Collisions
SEVERITY: LOW
DETAILS: Registers on_key_press (line 425) and on_key_release (line 426). Handler (line 238) handles NVG toggle and device use keys.
OUR IMPACT: Our MP code uses on_key_press for the F5 save-blocked tooltip. Both handlers fire. NVG key presses are local UI -- no shared state mutations. Low risk unless device queries reference game objects unavailable on client.
FIX: Ensure db.actor validity check at the top of the device key handler. No structural conflict with our callback usage.

---
MOD: G.A.M.M.A. ZCP 1.4 Balanced Spawns
FILE: tasks_fetch.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: LOW
DETAILS: Calls alife_create_item(break_arty, db.actor) (line 143), alife_create_item(break_con, db.actor) (line 144), alife_create_item(sec, db.actor, {uses = remain}) (line 243), and alife_create_item(cont, db.actor) (line 314) to give quest items to the player during fetch-task completion callbacks.
OUR IMPACT: Quest item delivery alife_create_item on the client with suppressed A-Life silently fails -- quest items do not appear in the client inventory when tasks complete.
FIX: Task completion item delivery should be proxied through the host. Add host-only guards around alife_create_item quest item grants.

---

## MODS WITH NO SCRIPT CONFLICTS

The following mods from this chunk contain no .script files, or contain only scripts with no conflicts across all 8 checked types:

- G.A.M.M.A. Vehicles Edits -- config-only (.ltx vehicle physics edits, no scripts)
- G.A.M.M.A. Weathers -- config-only (weather .ltx files, no scripts)
- G.A.M.M.A. Vices are free / bind_awr.script -- npc_on_death_callback is defined but its RegisterScriptCallback line is commented out
- G.A.M.M.A. Wepl Hit Effects Rework -- local UI hit effects only, no alife/SIMBOARD/death callbacks
- G.A.M.M.A. X10 spawn rebalance -- z_sr_psy_antenna_no_sound_mute.script: trivial antenna sound suppression, no conflicts
- G.A.M.M.A. Voiced Actor / AGDD_voiced_actor.script -- voice playback only; on_key_release for grenade callouts, no state mutations
- G.A.M.M.A. Weapon Pack (remaining scripts: ads_reloads, animation_common, aol_anim_transitions, aol_sprint_cancel, binoc_pistol_knife, m1a1_autoinject, shotgun_unjam_fix, uni_anim_ammo, uni_anim_core, uni_anim_detectors, unjam_motion_mark, weapon_cover_tilt_*, wpn_thompson_mcm) -- animation and UI callbacks only
- G_FLAT's Gavrilenko Tasks Fix -- task data fixes, no alife/callbacks
- G_FLAT's Indirect Parts Favoriter -- UI inventory callbacks only
- G_FLAT's Inventory Anti-Closing -- UI event hook only
- G_FLAT's More Measurement Task Maps -- map UI, no alife
- G_FLAT's Msv Above Radiation Icon -- HUD icon display only
- G_FLAT's Remember Belt Items -- own save/load state only, not save-blocking
- G_FLAT's Status Icons Always Shown -- HUD display only
- G_FLAT's Unusable Parts Handler -- item condition UI only
- Grizzy's Guns Inertia -- no scripts found
- Grok's and Bert's Casings Falling Sounds / grok_casings_sounds.script -- sound effect hooks only
- Grok's and Darkasleif's Armor Exchange -- dialog/trade UI only, no alife/SIMBOARD
- Grulag's Halved Stalkers Population at Hubs -- config-only (.ltx smart terrain population caps, no scripts)
- Grulag's In-game G.A.M.M.A. Manual / grok_gamma_manual_on_startup.script -- UI display only
- Jaku's Improved Shaders v1.2 -- no scripts
- Kute's Free Zoom Rewrite -- zoom UI and MCM; on_key_release for zoom toggle, no state mutations
- LSZ AI Tweaks -- config-only (.ltx AI behaviour tweaks, no scripts)
- LVutner's Shader Corner Shadow Fix -- no scripts
- Lizzardman's Field Strip Colors / tpa_patch_repairs.script -- condition colour display only
- Mags Buyable at Traders -- no scripts
- Maid's and Grok's BaS Dynamic Zoom Enabler -- no scripts
- Meatchunk's prefetcher -- no scripts
- Momopate's Barrel Condition Effects Display / zzzz_arti_jamming_repairs.script -- weapon condition hooks; monkey-patched but no alife/death callbacks
- Momopate's Detailed Weapon Stats -- HUD stat display only
- Momopate's Improved Pulses / pulse_vortex_consistency_fix.script -- anomaly pulse data fix, no alife calls
- No Tinnitus Sound Effects -- no scripts
- No Weapon Jam Chance at Full Condition -- no scripts
- Norfair's Saiga12 Textures Improvements -- modxml_saiga_fixes_*.script: modxml injectors only, no callbacks
- Nullpath's KSG23 -- no scripts
- Oleh's Bolt Impact Sounds -- no scripts
- Oleh's Extended MovementSFX -- sound effect hooks; on_key_press/on_key_release for freelook state, no state mutations affecting shared world
- Oleh's Miscellaneous Sound Improvements -- sound callbacks only
- Oleh's Weapons Sounds Tweaks and Fixes -- sound effect hooks only
- Optional Modern UI font -- no scripts
- Particles Cinematic VFX 3.5 -- no scripts
- Pre-0.9 Saves Fix -- no conflicting scripts found

---

## Summary Table

| Mod | File | Type | Severity |
|-----|------|------|----------|
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | sim_squad_scripted.script | Callback Collision + SIMBOARD + Entity Lifecycle | CRITICAL |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | smart_terrain.script | Callback Collision + SIMBOARD | CRITICAL |
| G.A.M.M.A. Vehicles in Darkscape | grok_vehicles_spawner.script | Entity Lifecycle + Global Pollution | CRITICAL |
| G.A.M.M.A. YACS no quit | ish_campfire_saving.script | Save System + Callback Collision | CRITICAL |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | smr_loot.script | Callback Collision + Entity Lifecycle | HIGH |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | bind_anomaly_field.script | Callback Collision + Entity Lifecycle | HIGH |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | game_setup.script | Callback Collision + Entity Lifecycle + SIMBOARD | HIGH |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | bind_awr.script | Callback Collision | HIGH |
| G_FLAT's Individualy Recruitable Companions | stalker_cloning_utility.script | Entity Lifecycle + SIMBOARD | HIGH |
| Garbage Transition Point in Rostok CLOSER | lc_custom.script | Entity Lifecycle + SIMBOARD + Position/Movement | HIGH |
| G.A.M.M.A. Weapon Pack | close_combat_weapons_launchers.script | Callback Collision | HIGH |
| Ishmaeel's Kill Tracker | ish_kill_tracker.script | Callback Collision | HIGH |
| G.A.M.M.A. Vices are free | xr_conditions.script | SIMBOARD + A-Life Dependency | MEDIUM |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | sim_board.script | SIMBOARD + Entity Lifecycle | MEDIUM |
| G_FLAT's and Grok's Hunting Kit Rework | ui_mutant_loot.script | Entity Lifecycle + Callback Collision | MEDIUM |
| Momopate's Loot Stabilizer | momopate_savescummer_v2.script | Global Table Pollution | MEDIUM |
| G.A.M.M.A. YACS no quit | ish_campfire_saving.script (SIMBOARD read) | A-Life Dependency | MEDIUM |
| Log spam remover | _g.script | Global Table Pollution | MEDIUM |
| G.A.M.M.A. Voiced Actor | ui_addon_companion_quick_menu.script | Callback Collision | MEDIUM |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | smr_pop.script | A-Life Dependency + SIMBOARD | LOW |
| G_FLAT's Individualy Recruitable Companions | individually_recruitable_companions.script | Entity Lifecycle | LOW |
| G.A.M.M.A. Weapon Pack | trader_autoinject.script | Entity Lifecycle | LOW |
| No BNVG FDDA Redone Patch | item_device.script | Callback Collision | LOW |
| G.A.M.M.A. ZCP 1.4 Balanced Spawns | tasks_fetch.script | Entity Lifecycle | LOW |
