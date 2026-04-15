# Audit Findings - Chunk 3

**Base directory:** Stalker_GAMMA/G.A.M.M.A/modpack_addons/
**Mods scanned:** 51 mods (Books Pass Time through Lottery Rebalance)
**Date:** 2026-04-15

---

## Summary Table

| Mod | File(s) | Conflict Types | Severity |
|-----|---------|---------------|----------|
| G.A.M.M.A. Books Pass Time | Wait.script | Weather/Time, Entity Lifecycle | HIGH |
| G.A.M.M.A. Bounty Squad Kill | sim_squad_bounty.script | Callback Collision, SIMBOARD/Squad | MEDIUM |
| G.A.M.M.A. Bounty Squads Rework | sim_squad_bounty.script | Callback Collision, SIMBOARD/Squad, Entity Lifecycle | HIGH |
| G.A.M.M.A. Camera reanimation fixes | camera_reanim_project.script | Callback Collision (2x) | LOW |
| G.A.M.M.A. Close Quarter Combat | quickdraw.script | Callback Collision, Entity Lifecycle | HIGH |
| G.A.M.M.A. Close Quarter Combat | grok_bo.script | Global Table Pollution | MEDIUM |
| G.A.M.M.A. Companions Rework | grok_get_companions.script | A-Life Dependency | LOW |
| G.A.M.M.A. Cooking Overhaul | campfire_placeable.script | Entity Lifecycle, Weather/Time | HIGH |
| G.A.M.M.A. Cooking Overhaul | bind_campfire.script | Callback Collision, Save System, SIMBOARD | HIGH |
| G.A.M.M.A. Crooks Identification UI Fix | factionID_hud_mcm.script | Callback Collision (2x) | LOW |
| G.A.M.M.A. Disguise does not remove patches | gameplay_disguise.script | Callback Collision (3x) | MEDIUM |
| G.A.M.M.A. Dynamic Despawner | grok_dynamic_despawner.script | Callback Collision, Entity Lifecycle | CRITICAL |
| G.A.M.M.A. Economy | TB_RF_Receiver_Packages.script | Callback Collision, Entity Lifecycle | HIGH |
| G.A.M.M.A. Economy | game_statistics.script | Callback Collision | MEDIUM |
| G.A.M.M.A. Economy | death_manager.script | Entity Lifecycle | HIGH |
| G.A.M.M.A. Economy | target_prior.script | SIMBOARD/Squad | MEDIUM |
| G.A.M.M.A. Economy | xrs_rnd_npc_loadout.script | Entity Lifecycle | MEDIUM |
| G.A.M.M.A. Economy | despawn_monolith_grenades.script | Entity Lifecycle | MEDIUM |
| G.A.M.M.A. Economy | wpo_loot.script | Entity Lifecycle | MEDIUM |
| G.A.M.M.A. FDDA Rework | enhanced_animations.script | Callback Collision, Entity Lifecycle | MEDIUM |
| G.A.M.M.A. Free Zoom v3 | Free_ZoomV2_mcm.script | Callback Collision (2x) | LOW |
| G.A.M.M.A. January PDA crash fix | ui_pda_npc_tab.script | Callback Collision | LOW |
| G.A.M.M.A. Keybinds fixes | bas_nvg_scopes.script | Callback Collision (2x) | LOW |
| G.A.M.M.A. Keybinds fixes | zz_ui_inventory_better_stats_bars.script | Callback Collision | LOW |
| G.A.M.M.A. Keybinds fixes | ui_addon_companion_quick_menu.script | Callback Collision | LOW |
| G.A.M.M.A. Killing Friends Reduces Goodwill | grok_killing_friends_reduces_goodwill.script | Callback Collision | MEDIUM |
| G.A.M.M.A. Light Sources Spawner | bind_light_furniture.script | A-Life Dependency | MEDIUM |
| G.A.M.M.A. Lottery Rebalance | dialogs_mlr.script | Entity Lifecycle, SIMBOARD/Squad, Position/Movement | HIGH |

**No conflicts found in:** Burer Fix, Burnt Fuzz Balance, Combat and Balance_separator, Crafting Tools Weight Reduce, Dark Signal Audio Lite, Deer Hunter as 338 Federal, Desman Horror Overhaul fixes, Difficulty Presets Rebalance, Disable WPO Overheat, Disabled (DO NOT ACTIVATE)_separator, DNPCAV Crash Fix, Economy and Craft_separator, Economy no BAS injection, End of List_separator, Enhanced Recoil, Exo Balance, Expert toolkits tier 5, Fast Transfer fix, Fast Travel Limiter Rebalance, Footsteps, Guns easier cleaning, Guns Have No Condition, HUD_separator, Hands Legs Models Swap, Heavy Metal Magazines, Helmets need armor repair kits, Icons, Icons Cr3pis Ammo, Icons replacer and fixes, Inspect on double tap F disabler, Items Parts Fixes.

---

## Detailed Findings

---
MOD: G.A.M.M.A. Books Pass Time
FILE: Wait.script
CONFLICT TYPE: Weather/Time
SEVERITY: HIGH
DETAILS: When the player uses a book/journal/cards item from inventory, level.change_game_time(0, 0, minutes) is called directly (60-180 in-game minutes depending on item). Also calls alife_release_id(id) on the consumed item object.
OUR IMPACT: level.change_game_time is an environment-sync call we exclusively own on the client. If a client calls this independently it desyncs game time from the host canonical clock. Our level.set_game_time / level.change_game_time sync pipeline will fight the locally-advanced time.
FIX: Wrap level.change_game_time in a host-only guard. On the client, send a time-advance request to the host via the sync channel and let the host broadcast the new canonical time. Gate alife_release_id behind host-authority.
---

---
MOD: G.A.M.M.A. Bounty Squad Kill
FILE: sim_squad_bounty.script
CONFLICT TYPE: Callback Collision, Entity Lifecycle (commented out)
SEVERITY: MEDIUM
DETAILS: Registers npc_on_death_callback (bounty_npc_death) and server_entity_on_unregister (bounty_unregister). The try_spawn() function body is entirely commented out so no actual squad creation occurs. The death callback reads SIMBOARD.smarts_by_names to verify bounty target but only on death, not on update.
OUR IMPACT: npc_on_death_callback slot collision. server_entity_on_unregister fires on all entity unregistrations; bounty_unregister only removes from internal table so low risk. SIMBOARD read on death event may nil-crash on client if A-Life suppressed.
FIX: Wrap SIMBOARD access in IsHoster() guard. Death/unregister callbacks are acceptable but should check IsHoster() before acting on SIMBOARD data.

---
MOD: G.A.M.M.A. Bounty Squads Rework
FILE: sim_squad_bounty.script
CONFLICT TYPE: SIMBOARD/Squad, Entity Lifecycle, Callback Collision
SEVERITY: HIGH
DETAILS: try_spawn() iterates SIMBOARD.smarts_by_names, calls sim_board.get_sim_board():create_squad(smart, squad_name), sets sq.force_online = true. attack() calls person:force_set_goodwill(-3000, db.actor). collect_actor_information() reads SIMBOARD.smarts (nil-crash risk on suppressed-A-Life client). Registers npc_on_death_callback and server_entity_on_unregister.
OUR IMPACT: create_squad() on client = nil crash (SIMBOARD nil). Even on host, created squads are not tracked in MP entity registry. Goodwill writes are local-only. SIMBOARD.smarts nil crash on client.
FIX: Gate try_spawn(), attack(), collect_actor_information() behind IsHoster(). All squad creation must be host-only. Consider suppressing bounty system entirely on clients.

---
MOD: G.A.M.M.A. Camera reanimation fixes
FILE: camera_reanim_project.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers actor_on_update (crouch/lean camera effectors) and on_key_press (fire-mode animation trigger). All logic is purely local camera/animation state with no A-Life, SIMBOARD, weather, or save interaction.
OUR IMPACT: actor_on_update and on_key_press slots are used but purely cosmetic. No desync risk.
FIX: None required. Safe to run on all peers.

---
MOD: G.A.M.M.A. Close Quarter Combat
FILE: quickdraw.script
CONFLICT TYPE: Entity Lifecycle (raw engine calls), Callback Collision
SEVERITY: HIGH
DETAILS: Registers actor_on_update and on_key_press. hit_key() calls raw alife():create(knife_name, pos, lvid, gvid, actor_id) and alife():release(alife_object(anm:id())). hit_animation() also calls alife():release(alife_object(anm:id())). These bypass the alife_create/alife_release wrappers and the MP intercept layer entirely, so created/released entities are never added to or removed from the MP ID-mapping registry.
OUR IMPACT: Knife animation objects created/destroyed without MP tracking. On host: orphaned server objects not in ID map. On client: alife() calls will crash or silently fail if A-Life is suppressed.
FIX: Replace raw alife():create() and alife():release() with alife_create() and alife_release() wrappers, then gate calls behind IsHoster().

---
MOD: G.A.M.M.A. Close Quarter Combat
FILE: grok_bo.script
CONFLICT TYPE: Global Table Pollution, A-Life Dependency (PBA nullification)
SEVERITY: MEDIUM
DETAILS: Declares ~12 globals without local keyword: custom_bone_value, custom_bone_ap, custom_bone_hf, custom_bone_dmg, invincible_npcs_sections, ini_capture, ini_bones, ini_damage, Bone_IDs, stalker_damage, hp_rounds, snipers, integrated_silencer. Monkeypatches three perk_based_artefacts callbacks to no-ops: perk_based_artefacts.npc_on_death_callback, npc_on_hit_callback, npc_on_before_hit.
OUR IMPACT: Global namespace pollution may collide with MP globals. PBA callback nullification means artefact death/hit effects are silently disabled for all players loading this script. If MP code relies on PBA callbacks, those will be dead.
FIX: Localize all globals with local keyword. Evaluate whether PBA nullification is intentional or a bug; if intentional, document it. Do not nullify PBA callbacks unless replacement logic is provided.

---
MOD: G.A.M.M.A. Companions Rework
FILE: grok_get_companions.script
CONFLICT TYPE: None (utility function only)
SEVERITY: LOW
DETAILS: Single exported function is_actor_stronger(actor, npc) comparing HP values. No callbacks registered, no A-Life calls, no SIMBOARD access, no globals polluted.
OUR IMPACT: Nil NPC argument would crash but that is a caller issue. No MP conflict.
FIX: None required.

---
MOD: G.A.M.M.A. Cooking Overhaul
FILE: campfire_placeable.script
CONFLICT TYPE: Entity Lifecycle, Weather/Time
SEVERITY: HIGH
DETAILS: actor_on_first_update performs a full world scan (loop i=1 to 65534) and calls alife_release(se_obj) on old campfire objects. Also calls alife_create(ph_sec, pos, lvid, gvid), alife_create("campfire", ...), alife_create_item(itm_to_spawn, db.actor), and alife_release(obj) for campfire placement/removal. Two call sites of level.change_game_time(0, 0, minutes) for sleep/wait mechanics.
OUR IMPACT: Full-world alife_release scan on first update will desync entity registry if run on client. Time changes will desync game clock between peers. Any campfire spawned on client will not be in host entity map.
FIX: Gate world-scan alife_release loop, all alife_create/alife_release calls, and level.change_game_time behind IsHoster(). Campfire spawning must be host-authoritative with client notification.

---
MOD: G.A.M.M.A. Cooking Overhaul
FILE: bind_campfire.script
CONFLICT TYPE: Save System, Callback Collision, SIMBOARD/Squad
SEVERITY: HIGH
DETAILS: Registers actor_on_update. Conditionally registers on_before_save_input with flags.ret = true to block saves during campfire mode. This directly conflicts with our MP save-blocking which uses flags.ret_value = false. Also reads SIMBOARD.smarts_by_names to find campfire-compatible areas.
OUR IMPACT: flags.ret = true vs flags.ret_value = false semantic conflict means the save-block logic may behave incorrectly or unpredictably in MP context. SIMBOARD.smarts_by_names read on client = nil crash. actor_on_update slot used.
FIX: Align save blocking to use flags.ret_value = false to match MP convention. Gate SIMBOARD.smarts_by_names access behind IsHoster() or nil-check. Evaluate whether campfire mode save blocking is needed in MP at all.

---
MOD: G.A.M.M.A. Crook's Identification UI Fix
FILE: factionID_hud_mcm.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers actor_on_update (100ms throttled HUD faction display) and npc_on_death_callback (HUD update on NPC death). Purely cosmetic UI logic, no A-Life, no SIMBOARD, no weather changes, no save interaction.
OUR IMPACT: actor_on_update and npc_on_death_callback slots used. No desync risk. HUD will only reflect local peer state.
FIX: None required for functionality. Accept that HUD may show stale faction data for remote players on client.

---
MOD: G.A.M.M.A. Disguise does not remove patches
FILE: gameplay_disguise.script
CONFLICT TYPE: Callback Collision
SEVERITY: MEDIUM
DETAILS: Registers actor_on_update (2-second throttled suspicion monitoring), npc_on_death_callback (npcs_memory table cleanup), and on_key_press (one-shot, immediately unregisters itself after firing). Disguise logic modifies NPC relations which are local-only in GAMMA.
OUR IMPACT: actor_on_update, npc_on_death_callback, and on_key_press slots used. Relation changes from disguise will not propagate to other peers - each client manages its own NPC relation state. Desync in NPC behavior toward different players is expected.
FIX: Accept relation desync as a known limitation. No crashes expected. Consider documenting that disguise mechanics are per-peer.

---
MOD: G.A.M.M.A. Dynamic Despawner
FILE: grok_dynamic_despawner.script
CONFLICT TYPE: Entity Lifecycle, Global Table Pollution, Callback Collision
SEVERITY: CRITICAL
DETAILS: Registers actor_on_update, npc_on_update, monster_on_update. Every ~43 seconds, iterates online NPCs and calls alife_release(se_item) on arbitrary NPCs exceeding a threshold. All state variables are undeclared globals: online_npcs, trigger, trigger2, trigger3, delay, delay2, delay3, grok_delay, grok_delay2, grok_delay3, nrows, check_tasks, enabled, npc_threshold. The despawner will run on every peer independently, causing duplicate/conflicting alife_release calls for the same entities.
OUR IMPACT: Multiple clients each independently releasing the same NPC = double-free corruption of A-Life state. Entity registry desyncs immediately. Global variable pollution pollutes the shared Lua state. This mod WILL cause crashes and entity corruption in MP without host-gating.
FIX: MUST gate entire despawn logic behind IsHoster(). Localize all globals. Consider disabling this mod entirely in MP environments as its behavior is fundamentally incompatible with multi-peer A-Life management.

---
MOD: G.A.M.M.A. Economy
FILE: TB_RF_Receiver_Packages.script
CONFLICT TYPE: Entity Lifecycle, Callback Collision
SEVERITY: HIGH
DETAILS: Registers actor_on_update. Calls alife_create(abadguy, abadguyVec, tb_target_lvid, tb_target_gvid) to spawn a hostile NPC at a calculated position, alife_create_item(section, db.actor) for reward items, and alife_release(item) for cleanup. The RF package delivery system spawns real A-Life entities as quest triggers.
OUR IMPACT: NPC spawns and releases on client bypass MP entity registry. Spawned hostiles will not be tracked in host ID map. If both host and client trigger the same package delivery, duplicate NPCs will be spawned.
FIX: Gate alife_create and alife_release calls behind IsHoster(). Implement a client-to-host RPC for triggering package deliveries so only host performs entity operations.

---
MOD: G.A.M.M.A. Economy
FILE: game_statistics.script
CONFLICT TYPE: Callback Collision
SEVERITY: MEDIUM
DETAILS: Registers npc_on_death_callback for kill statistics tracking (faction kill counts, reputation). Statistics are stored in-memory and serialized to save. Blocked saves on clients mean statistics will not persist between sessions for client peers.
OUR IMPACT: npc_on_death_callback slot used. Each peer independently tracks kill stats. Client stats are lost on disconnect since saves are blocked. Statistics diverge between peers.
FIX: Accept stat desync as a known limitation. npc_on_death_callback usage is harmless for host. For clients, stats are ephemeral. No crash risk.

---
MOD: G.A.M.M.A. Economy
FILE: death_manager.script
CONFLICT TYPE: Entity Lifecycle, Callback Collision
SEVERITY: HIGH
DETAILS: create_release_item() triggered on every NPC death via npc_on_death_callback. Makes extensive calls to alife_create_item(), alife_create(), alife_release(), and alife_release_id() for loot generation and corpse management. This runs on every peer that has the death callback active.
OUR IMPACT: Every client independently generates loot via alife_create_item on NPC death = duplicate loot items. alife_release calls on client can free entities owned by host. High risk of entity registry corruption and item duplication across peers.
FIX: Gate all alife_create_item, alife_create, alife_release, alife_release_id calls in death_manager behind IsHoster(). Loot generation must be host-authoritative.

---
MOD: G.A.M.M.A. Economy
FILE: target_prior.script
CONFLICT TYPE: SIMBOARD/Squad, A-Life Dependency
SEVERITY: MEDIUM
DETAILS: Monkeypatches sim_board.simulation_board:get_squad_target(squad). The replacement reads SIMBOARD.smarts[target.id].population and .squads tables. On a suppressed-A-Life client where SIMBOARD is nil or empty, this will nil-crash when any squad AI needs a target.
OUR IMPACT: Any squad target evaluation on client = nil crash. Since this patches a core simulation_board method, the crash would propagate to any AI using the patched method.
FIX: Add nil-check guards: if not SIMBOARD or not SIMBOARD.smarts or not SIMBOARD.smarts[target.id] then return nil end before accessing population/squads. Alternatively gate entire monkeypatch behind IsHoster() and restore vanilla method on clients.

---
MOD: G.A.M.M.A. Economy
FILE: xrs_rnd_npc_loadout.script
CONFLICT TYPE: Entity Lifecycle, Callback Collision
SEVERITY: MEDIUM
DETAILS: Registers se_stalker_on_spawn callback. When an NPC spawns, calls alife_create_item(section, se_npc) multiple times to add randomized gear to the NPC loadout. Fires during server entity registration phase.
OUR IMPACT: se_stalker_on_spawn fires on the peer that owns the A-Life simulation. On client with suppressed A-Life, this callback may not fire at all, or may fire inconsistently. If it fires on both peers, duplicate items are created for each NPC spawn.
FIX: Gate alife_create_item calls behind IsHoster() inside the se_stalker_on_spawn callback. Loadout randomization should only occur on the host.

---
MOD: G.A.M.M.A. Economy
FILE: despawn_monolith_grenades.script
CONFLICT TYPE: Entity Lifecycle, A-Life Dependency
SEVERITY: MEDIUM
DETAILS: Monkeypatches trader_autoinject.update to inject grenade despawn logic. Calls alife_release(item) on grenade items found in trader inventory. Runs as part of the trader update loop.
OUR IMPACT: alife_release on client bypasses MP entity registry. If both peers monkeypatch trader_autoinject.update, the function is double-wrapped and may execute despawn logic twice. Grenades released on client may still exist on host.
FIX: Gate alife_release calls inside the monkeypatched update behind IsHoster(). Ensure the monkeypatch is applied only once (check if already patched before wrapping).

---
MOD: G.A.M.M.A. Economy
FILE: wpo_loot.script
CONFLICT TYPE: Entity Lifecycle
SEVERITY: MEDIUM
DETAILS: Contains alife_release_id(item:id()) for loot cleanup operations. Part of the wider loot processing system.
OUR IMPACT: alife_release_id on client can free entities from the server A-Life without notifying host MP entity registry. Entity becomes orphaned in the ID map.
FIX: Gate alife_release_id behind IsHoster().

---
MOD: G.A.M.M.A. FDDA Rework
FILE: enhanced_animations.script
CONFLICT TYPE: Entity Lifecycle, Callback Collision
SEVERITY: MEDIUM
DETAILS: Dynamically registers and unregisters actor_on_update. On animation start calls alife_create_item("items_anm_dummy", db.actor) to create a dummy item used for animation state tracking. On animation end calls alife_release(db.actor:object("items_anm_dummy")) to clean it up. This create/release cycle happens for every first-person animation sequence.
OUR IMPACT: Dummy items created on client are not tracked in host entity registry. If animations run on both peers simultaneously (same actor), duplicate dummy items are created. The release on end may target wrong entity if IDs diverge between peers.
FIX: Gate alife_create_item and alife_release behind IsHoster(), or use a purely local (non-A-Life) animation state flag instead of creating a server entity.

---
MOD: G.A.M.M.A. Free Zoom v3
FILE: Free_ZoomV2_mcm.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers actor_on_update (HUD FOV adjustment) and on_key_press (zoom toggle). All logic modifies local camera FOV state only. No A-Life, no SIMBOARD, no weather, no save interaction.
OUR IMPACT: actor_on_update and on_key_press slots used. Purely cosmetic/local, no desync risk.
FIX: None required. Safe on all peers.

---
MOD: G.A.M.M.A. January PDA crash fix
FILE: ui_pda_npc_tab.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Dynamically registers actor_on_update only while the PDA NPC tab is open, unregisters on close. All logic is UI/display only - renders NPC relation data from existing game state. No A-Life operations, no SIMBOARD writes, no weather changes.
OUR IMPACT: actor_on_update slot used only when PDA open. NPC relation display will reflect local peer state only. No crash risk.
FIX: None required. Accept that NPC relation display may differ between peers.

---
MOD: G.A.M.M.A. Keybinds fixes
FILE: bas_nvg_scopes.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers actor_on_update (scope switching logic) and on_key_press (NVG/scope keybind handling). Purely local input and inventory state. No A-Life, no SIMBOARD, no weather interaction.
OUR IMPACT: actor_on_update and on_key_press slots used. Equipment switching is local-only; inventory state may diverge between peers if not synced by MP layer.
FIX: None required from this mod directly. Accept inventory desync as a broader MP challenge.

---
MOD: G.A.M.M.A. Keybinds fixes
FILE: zz_ui_inventory_better_stats_bars.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers on_key_press for inventory UI keybind. Purely local UI state, no A-Life or world state changes.
OUR IMPACT: on_key_press slot used. No desync risk.
FIX: None required.

---
MOD: G.A.M.M.A. Keybinds fixes
FILE: ui_addon_companion_quick_menu.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers on_key_press for companion quick-menu toggle. UI-only, no A-Life calls. Companion commands issued through this menu may trigger underlying companion AI which could have separate MP implications, but this file itself is clean.
OUR IMPACT: on_key_press slot used. No direct MP conflict from this file.
FIX: None required from this file. Companion command handling in downstream scripts should be evaluated separately.

---
MOD: G.A.M.M.A. Killing Friends Reduces Goodwill
FILE: grok_killing_friends_reduces_goodwill.script
CONFLICT TYPE: Callback Collision, Global Table Pollution
SEVERITY: MEDIUM
DETAILS: Registers npc_on_death_callback (relation_kill_check) and npc_on_before_hit (aggression tracking). relation_kill_check calls game_relations.change_factions_community_num and game_statistics.increment_reputation(-300) from any peer on NPC death. Global aggressive_npcs table declared without local keyword.
OUR IMPACT: npc_on_death_callback and npc_on_before_hit slots used. Faction goodwill and reputation changes are local-only - each peer maintains independent relation state. Reputation changes on client are not persisted (save blocked). aggressive_npcs global pollutes shared namespace.
FIX: Localize aggressive_npcs with local keyword. Consider gating reputation/goodwill changes behind IsHoster() to ensure only one authoritative change occurs per kill event.

---
MOD: G.A.M.M.A. Light Sources Spawner
FILE: bind_light_furniture.script
CONFLICT TYPE: A-Life Dependency
SEVERITY: MEDIUM
DETAILS: Full placeable_light_wrapper object binder using hf_obj_manager for persistent lamp state (is_on flag, fuel condition). hf_obj_manager data is not synchronized between peers - each peer maintains its own lamp state. Note: grok_spawn_lights.script is empty (1 byte), so no standalone spawn logic exists.
OUR IMPACT: Lamp on/off state and fuel level will diverge between peers. A lamp turned on by the host will remain off on clients and vice versa. No crash risk, but visual and gameplay state desync for all portable light sources.
FIX: Implement hf_obj_manager state sync for lamp on/off and fuel condition via the MP sync layer. Until then, document that portable lights are per-peer cosmetic only.

---
MOD: G.A.M.M.A. Lottery Rebalance
FILE: dialogs_mlr.script
CONFLICT TYPE: Entity Lifecycle (raw engine call), Position/Movement, SIMBOARD/Squad
SEVERITY: HIGH
DETAILS: spawn_1_11_af_medusa_kmb() calls raw alife():create("af_medusa", vector():set(-249.45,...), 12990, 386) bypassing all wrappers. Four guide teleport functions call db.actor:set_actor_position(hardcoded_vector, lvid, gvid) directly. merc_pri_grifon_mlr_task_target() reads SIMBOARD.smarts_by_names["pri_b304_monsters_smart_terrain"] with no nil check. Also uses alife_create_item(v, db.actor) and alife_create("af_ball", ...).
OUR IMPACT: Raw alife():create() bypass MP intercept layer - entity not added to ID map. set_actor_position bypasses MP position-sync pipeline - teleporting actor on client will immediately be corrected by host position authority, or cause position authority conflict. SIMBOARD.smarts_by_names nil-crash on client when guide dialog is triggered.
FIX: Replace raw alife():create() with alife_create() wrapper. Replace db.actor:set_actor_position() with MP-aware teleport RPC. Add nil-check before SIMBOARD.smarts_by_names access. Gate entity creation behind IsHoster().

---

## Conflict Type Index

### 1. Callback Collisions
Mods registering callbacks that compete for shared slots:
- actor_on_update: Camera reanimation fixes, Close Quarter Combat (quickdraw), Cooking Overhaul (bind_campfire + campfire_placeable), Crooks ID Fix, Disguise patches, Dynamic Despawner, Economy (TB_RF_Receiver_Packages), FDDA Rework, Free Zoom v3, January PDA fix, Keybinds fixes (bas_nvg_scopes), Keybinds fixes (stats bars), Keybinds fixes (companion menu)
- npc_on_death_callback: Bounty Squad Kill, Bounty Squads Rework, Crooks ID Fix, Disguise patches, Dynamic Despawner, Economy (game_statistics + death_manager), Killing Friends Reduces Goodwill
- on_key_press: Camera reanimation, Close Quarter Combat (quickdraw), Disguise patches, Free Zoom v3, Keybinds fixes (all three)
- npc_on_update / monster_on_update: Dynamic Despawner
- npc_on_before_hit: Killing Friends Reduces Goodwill
- server_entity_on_unregister: Bounty Squad Kill, Bounty Squads Rework
- se_stalker_on_spawn: Economy (xrs_rnd_npc_loadout)
- on_before_save_input: Cooking Overhaul (bind_campfire) - FLAGS CONFLICT

### 2. Entity Lifecycle (alife create/release)
Mods calling alife_create/alife_release/alife_release_id or raw alife():create()/alife():release():
- CRITICAL - raw alife(): Close Quarter Combat (quickdraw), Lottery Rebalance (dialogs_mlr)
- HIGH - Cooking Overhaul (campfire_placeable, full world scan release), Economy (TB_RF_Receiver_Packages), Economy (death_manager)
- MEDIUM - Books Pass Time (alife_release_id), FDDA Rework, Economy (xrs_rnd_npc_loadout), Economy (despawn_monolith_grenades), Economy (wpo_loot), Dynamic Despawner

### 3. Position/Movement
- Lottery Rebalance (dialogs_mlr): db.actor:set_actor_position() - 4 guide teleport functions

### 4. Weather/Time
- Books Pass Time (Wait.script): level.change_game_time - 60-180 min skips
- Cooking Overhaul (campfire_placeable): level.change_game_time - 2 call sites

### 5. Save System
- Cooking Overhaul (bind_campfire): flags.ret = true CONFLICTS with our flags.ret_value = false

### 6. SIMBOARD/Squad
- Bounty Squads Rework: create_squad(), SIMBOARD.smarts iteration - FULLY ACTIVE
- Bounty Squad Kill: SIMBOARD.smarts_by_names read on death callback
- Economy (target_prior): sim_board.simulation_board:get_squad_target() monkeypatch reading SIMBOARD.smarts
- Lottery Rebalance: SIMBOARD.smarts_by_names with no nil-check

### 7. Global Table Pollution
- Dynamic Despawner: ~14 undeclared globals (online_npcs, trigger, trigger2, trigger3, delay, etc.)
- Close Quarter Combat (grok_bo): ~13 undeclared globals
- Killing Friends Reduces Goodwill: aggressive_npcs undeclared global

### 8. A-Life Dependency
- Bounty Squads Rework: SIMBOARD nil-crash on client in collect_actor_information()
- Close Quarter Combat (grok_bo): PBA callback nullification affects all peers
- Economy (target_prior): SIMBOARD nil-crash on client in monkeypatched get_squad_target
- Economy (despawn_monolith_grenades): double-wrapped monkeypatch risk
- Light Sources Spawner: hf_obj_manager state not synced between peers
- Lottery Rebalance: SIMBOARD.smarts_by_names nil-crash in task target function

---

## Priority Fix Order

### P0 - Must Fix Before Any MP Testing
1. **G.A.M.M.A. Dynamic Despawner** - Will cause immediate entity registry corruption and crashes. Gate ALL logic behind IsHoster() or disable mod entirely for MP.
2. **G.A.M.M.A. Cooking Overhaul (bind_campfire)** - flags.ret vs flags.ret_value save-block conflict will break the MP save-suppression system. Fix flags field name immediately.
3. **G.A.M.M.A. Close Quarter Combat (quickdraw)** - Raw alife():create/release bypass MP intercept. Replace with wrapper calls + IsHoster() gate.
4. **G.A.M.M.A. Lottery Rebalance** - Raw alife():create(), set_actor_position() bypassing MP pipeline, SIMBOARD nil-crash. Three distinct P0-class issues in one file.

### P1 - Fix Before Public Release
5. **G.A.M.M.A. Bounty Squads Rework** - create_squad() on client = guaranteed nil crash. Gate behind IsHoster().
6. **G.A.M.M.A. Cooking Overhaul (campfire_placeable)** - World-scan alife_release loop + time changes. Gate behind IsHoster().
7. **G.A.M.M.A. Economy (death_manager)** - Duplicate loot generation on every NPC death across all peers. Gate behind IsHoster().
8. **G.A.M.M.A. Economy (TB_RF_Receiver_Packages)** - NPC spawns on client. Gate behind IsHoster().
9. **G.A.M.M.A. Economy (target_prior)** - SIMBOARD nil-crash in monkeypatched squad AI. Add nil-guards.
10. **G.A.M.M.A. Books Pass Time** - Time skip desync. Gate level.change_game_time behind IsHoster() + sync to clients.

### P2 - Fix for Stable MP Experience
11. **G.A.M.M.A. Economy (xrs_rnd_npc_loadout)** - Duplicate items on NPC spawn. Gate behind IsHoster().
12. **G.A.M.M.A. Economy (despawn_monolith_grenades)** - Double-release risk. Gate + dedup monkeypatch.
13. **G.A.M.M.A. Economy (wpo_loot)** - alife_release_id on client. Gate behind IsHoster().
14. **G.A.M.M.A. FDDA Rework** - Dummy item create/release cycle. Gate or replace with local flag.
15. **G.A.M.M.A. Close Quarter Combat (grok_bo)** - Localize globals, document PBA nullification.
16. **G.A.M.M.A. Killing Friends Reduces Goodwill** - Localize globals, consider IsHoster() for reputation changes.
17. **G.A.M.M.A. Bounty Squad Kill** - Add nil-check for SIMBOARD in death callback.
18. **G.A.M.M.A. Economy (game_statistics)** - Accept stat desync, document client stats as ephemeral.

### P3 - Quality of Life / Document as Known Limitations
19. **G.A.M.M.A. Light Sources Spawner** - hf_obj_manager state desync. Document lamp state as per-peer.
20. **G.A.M.M.A. Disguise does not remove patches** - Relation desync is expected per-peer behavior.
21. **G.A.M.M.A. Keybinds fixes** - All LOW, safe on all peers.
22. **G.A.M.M.A. Free Zoom v3** - LOW, safe on all peers.
23. **G.A.M.M.A. January PDA crash fix** - LOW, safe on all peers.
24. **G.A.M.M.A. Camera reanimation fixes** - LOW, safe on all peers.
25. **G.A.M.M.A. Companions Rework** - LOW, safe on all peers.
26. **G.A.M.M.A. Crook's Identification UI Fix** - LOW, safe on all peers.
