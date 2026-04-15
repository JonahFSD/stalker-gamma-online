
content = """# Audit Findings - Chunk 6

Scanned mods: Pre-0.9.3.1 Saves Fix, Pre-0.9.4 Saves Fix, R3zy's Detectors Enhanced Shaders Patch, Raven's Tooltips on the Side, Razfarg's Scroll Fix, Realistic Magazines_separator, Redotix99's Walking Reanimation, Retrogue's Additional Weapons, Roadside's Lens Flares, SaloEater's Double Click to Use Tools, SaloEater's Remember HFE's Stove Slot, SaloEater's Replace Shows Parts Health, SaloEater's Use Package Only Once, SaloEater's Voiced Actor Gamma Patch, Serious Tasks QoL Pack, Serious Workshop optimization, Shaders cumulative pack for GAMMA, SilverBlack's Gas Mask Sounds, Simpington's Cocaine Animation for GAMMA, SixSloth's & Veerserif's Hideout Furnitures 2.2.1 GAMMA patch, Slugler's & Andtheherois's No old ammo in wheel, Solarint's New Piano Songs, Suppressors do not Increase Jam Probability, Teamson & Oleh's Bullet and Grenade Impact Sounds, Teepo's Speed Fix, Teivaz Gunslinger Knives Quick Melee, Teivaz's Gunslinger Exo Animations Port, Tiskar's colored upgrade kit icons, Tiskar's repair threshold Icon replacers, Tiskar's weapon part color clarity fix, Trabopap's Field Strip Shows Parts Health, Turn this on if you stutter, Unlimited Stashes Weight, Veerserif's Hideout Furniture Craft and Trade, Warfare Patch, Wildkins's Ammo Parts on Hover, Wildkins's DAO Svarog Patch, Yet Another Knife Reanimation - lizzardman, ZCP 1.5d, ilrathCXV's Meat Spoiling Timer in Tooltips, xcvb's Guards Spawner

Skipped (not mod folders): artefacts_values.xlsx, gamma_ammo_weapon_table.xlsx, good_weapons.txt, to_mipmap.txt, toolkits_chance.xlsx

No-conflict mods (no scripts or no conflicting patterns): Pre-0.9.4 Saves Fix, R3zy's Detectors Enhanced Shaders Patch, Raven's Tooltips on the Side, Razfarg's Scroll Fix, Realistic Magazines_separator, Redotix99's Walking Reanimation, Retrogue's Additional Weapons, Roadside's Lens Flares, SaloEater's Double Click to Use Tools, SaloEater's Remember HFE's Stove Slot, SaloEater's Replace Shows Parts Health, SaloEater's Use Package Only Once, SaloEater's Voiced Actor Gamma Patch, SilverBlack's Gas Mask Sounds, Simpington's Cocaine Animation for GAMMA, SixSloth's & Veerserif's Hideout Furnitures 2.2.1 GAMMA patch, Slugler's & Andtheherois's No old ammo in wheel, Solarint's New Piano Songs, Suppressors do not Increase Jam Probability, Teamson & Oleh's Bullet and Grenade Impact Sounds, Tiskar's colored upgrade kit icons, Tiskar's repair threshold Icon replacers, Tiskar's weapon part color clarity fix, Trabopap's Field Strip Shows Parts Health, Turn this on if you stutter, Unlimited Stashes Weight, Veerserif's Hideout Furniture Craft and Trade (configs only, no scripts), Wildkins's DAO Svarog Patch, Yet Another Knife Reanimation - lizzardman (on_key_press commented out), Serious Workshop optimization, Teepo's Speed Fix

---

## CONFIRMED CONFLICTS

---
MOD: Warfare Patch
FILE: sim_squad_scripted.script
CONFLICT TYPE: Callback Collision / SIMBOARD/Squad
SEVERITY: CRITICAL
DETAILS: Full replacement of sim_squad_scripted.script. The class fires SendScriptCallback("server_entity_on_register", self, "sim_squad_scripted") inside on_register() (line 1020) and SendScriptCallback("server_entity_on_unregister", self, "sim_squad_scripted") inside on_unregister() (line 1029). Extensively manipulates SIMBOARD.squads, SIMBOARD:assign_squad_to_smart(), and SIMBOARD:setup_squad_and_group() throughout squad lifecycle methods.
OUR IMPACT: Our MP code hooks server_entity_on_register to build the bidirectional ID mapping table (client) and entity tracking registry (host). This mod replaces the class that fires those callbacks. If the mod version diverges structurally from vanilla, the callback firing order or argument signature could change, silently breaking our ID mapping. Heavy SIMBOARD usage means squad state manipulation runs on clients where A-Life is suppressed.
FIX: Diff this sim_squad_scripted.script against vanilla Anomaly to confirm SendScriptCallback call sites are structurally identical. Add a defensive type-check on the "sim_squad_scripted" argument in our server_entity_on_register handler. On the client, confirm SIMBOARD:assign_squad_to_smart is safe to call with suppressed A-Life.

---
MOD: ZCP 1.5d
FILE: sim_squad_scripted.script
CONFLICT TYPE: Callback Collision / SIMBOARD/Squad
SEVERITY: CRITICAL
DETAILS: Full replacement of sim_squad_scripted.script, structurally near-identical to the Warfare Patch version. SendScriptCallback("server_entity_on_register", self, "sim_squad_scripted") at line 1021; SendScriptCallback("server_entity_on_unregister", self, "sim_squad_scripted") at line 1030. ZCP's sim_board.script overrides simulation_board:create_squad() to inject smr_civil_war.setup_civil_war_squad() on every squad spawn, which directly accesses SIMBOARD.squads and runs on the client.
OUR IMPACT: Same as Warfare Patch: replaces the class that fires our critical callbacks. Additionally, the civil war squad-setup injection in create_squad() runs on clients where A-Life is suppressed, potentially corrupting SIMBOARD state.
FIX: Diff against vanilla. Add defensive type-check in our handler. Gate smr_civil_war.setup_civil_war_squad() behind an MP host-only check inside simulation_board:create_squad().

---
MOD: ZCP 1.5d
FILE: smart_terrain.script
CONFLICT TYPE: Callback Collision / SIMBOARD/Squad
SEVERITY: CRITICAL
DETAILS: Full replacement of smart_terrain.script. SendScriptCallback("server_entity_on_register", self, "se_smart_terrain") at line 142 and SendScriptCallback("server_entity_on_unregister", self, "se_smart_terrain") at line 184. Heavy SIMBOARD:init_smart(), SIMBOARD:unregister_smart(), and SIMBOARD:assign_squad_to_smart() usage throughout smart terrain registration lifecycle.
OUR IMPACT: Our server_entity_on_register handler receives both smart terrain and squad registrations. If this replacement changes the callback argument type string or registration order, our entity tracking registry could silently misclassify entities. On the client, SIMBOARD smart registration paths run against a suppressed A-Life instance.
FIX: Confirm SendScriptCallback call signatures match vanilla. Add type-check guard in our server_entity_on_register handler distinguishing "se_smart_terrain" from "sim_squad_scripted". Gate SIMBOARD smart registration behind an MP-client check.

---
MOD: ZCP 1.5d
FILE: game_setup.script
CONFLICT TYPE: Entity Lifecycle / A-Life Dependency / SIMBOARD/Squad / Position/Movement
SEVERITY: CRITICAL
DETAILS: Registers actor_on_update (line 553). The actor_on_update handler (line 452) iterates SIMBOARD.squads and calls squad:remove_squad() during first-visit Cordon logic. The actor_on_first_update handler calls three one-time world-cleanup functions: bar_medic_remove_stuff() and darkscape_remove_physics_objects() iterate all 65534 A-Life IDs via alife():object(i) and call alife():release(se) on specific physics objects; freedom_medic_fix() additionally calls alife():teleport_object(i, 2165, 315401, vector():set(...)) to reposition an NPC (line 353). All three are guarded by a one-time alife_storage_manager flag stored in save state.
OUR IMPACT: (1) actor_on_update collision: SIMBOARD squad iteration on the client with suppressed A-Life produces nil squads and potential errors. squad:remove_squad() on the client fires server_entity_on_unregister, triggering our host-side despawn broadcast from the wrong machine. (2) alife():release() calls in actor_on_first_update fire on the client against suppressed A-Life. (3) alife():teleport_object() on the client conflicts with our position sync ownership. (4) The one-time guard flag is in save state which is blocked on the client, so this setup code may re-run every session load on the client.
FIX: Wrap all three actor_on_first_update cleanup functions with an MP host-only guard. Wrap the SIMBOARD squad iteration in actor_on_update with an if-not-client guard. Block alife():teleport_object() on the client.

---
MOD: ZCP 1.5d
FILE: smr_loot.script
CONFLICT TYPE: Callback Collision / A-Life Dependency
SEVERITY: HIGH
DETAILS: Registers npc_on_death_callback at line 459 (always) and conditionally re-registers at line 428. The callback (line 410) calls try_spawn() which spawns loot items into the dead NPC inventory via alife_create_item / SIMBOARD:create_squad calls depending on ZCP loot config.
OUR IMPACT: Our MP code registers npc_on_death_callback on the host to broadcast death events. ZCP registration is additive. However, try_spawn() loot logic will run on clients that receive the death-event replication, causing each client to independently attempt A-Life item spawns against suppressed A-Life. This produces silent spawn failures on the client, breaking loot drops in MP.
FIX: Wrap the try_spawn() call inside npc_on_death_callback with an MP host-only guard. Loot spawning must only execute on the host; results broadcast to clients via the item sync path.

---
MOD: ZCP 1.5d
FILE: smr_pop.script
CONFLICT TYPE: SIMBOARD/Squad / Entity Lifecycle
SEVERITY: HIGH
DETAILS: smr_handle_spawn() (called from smart_terrain.se_smart_terrain:try_respawn()) makes multiple SIMBOARD:create_squad() calls to override vanilla spawn behavior. An actor_on_first_update handler conditionally calls alife_release_id() on story objects (Sid the trader, forest forester) if ZCP's "none population" preset is active (lines 78-85).
OUR IMPACT: SIMBOARD:create_squad() calls (which internally call alife_create()) will be triggered on the client whenever smart terrain tries to respawn. The alife_release_id() calls in actor_on_first_update will fire on the client, interacting with suppressed A-Life. Story objects could be unilaterally released on the client before host establishes world state.
FIX: Gate smr_handle_spawn behind an MP host-only check. Gate please_die_sid() similarly.

---
MOD: ZCP 1.5d
FILE: bind_awr.script
CONFLICT TYPE: Callback Collision
SEVERITY: MEDIUM
DETAILS: Registers npc_on_death_callback at line 277. The handler (line 212) checks if the dead NPC is a workshop mechanic and triggers a PDA notification message with the killer name. References alife() at line 233 to retrieve actor character name.
OUR IMPACT: Additive callback collision. The alife() read is generally safe on the client. PDA notification (actor_menu.set_item_news) will fire on both host and client, potentially showing duplicate death notifications.
FIX: Wrap the PDA notification with a host-only guard to prevent duplicate messages, or confirm the notification is idempotent.

---
MOD: xcvb's Guards Spawner
FILE: guards_spawner.script
CONFLICT TYPE: Callback Collision / SIMBOARD/Squad / Global Table Pollution
SEVERITY: HIGH
DETAILS: Registers actor_on_update (line 296), server_entity_on_unregister (line 297), and on_key_press (line 300). The spawn_guard() function calls SIMBOARD:create_squad(smart, squad_section) (line 147) to spawn guard squads. The server_entity_on_unregister handler (line 165) iterates guarded_smarts to remove despawned squads. Debug on_key_press commands: DIK_M triggers spawn_guard() directly, DIK_K deletes all guards. guarded_smarts is declared as a module-level global (guarded_smarts = {} at line 104, no local keyword).
OUR IMPACT: (1) actor_on_update: spawn logic runs on the client, calling SIMBOARD:create_squad() against suppressed A-Life. (2) server_entity_on_unregister: if client independently fires remove_squad(), it could corrupt the guarded_smarts tracking table. (3) Debug DIK_M command can trigger squad spawning on a client. (4) Global guarded_smarts pollutes the Lua namespace and can be clobbered by other scripts.
FIX: Wrap spawn_guard() in actor_on_update with MP host-only guard. Wrap DIK_M debug command with host-only guard. Change guarded_smarts = {} to local guarded_smarts = {} and expose as a module field (emission_guard_patch.script already accesses it as guards_spawner.guarded_smarts, so the module-field pattern works).

---
MOD: xcvb's Guards Spawner
FILE: emission_guard_patch.script
CONFLICT TYPE: A-Life Dependency
SEVERITY: LOW
DETAILS: Registers actor_on_first_update. The handler iterates all 65534 A-Life IDs to fix scripted_target type coercion for existing guard squads. Also registers squad_on_update which accesses guards_spawner.guarded_smarts.
OUR IMPACT: Full 65534-slot A-Life iteration on the client is wasted (all IDs return nil with suppressed A-Life), causing a brief unnecessary performance spike on session load. squad_on_update on the client is a safe no-op against an empty guarded_smarts table.
FIX: Wrap the actor_on_first_update iteration with an MP host-only guard to skip on clients.

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: tasks_mirage.script
CONFLICT TYPE: Callback Collision / Position/Movement / SIMBOARD/Squad
SEVERITY: HIGH
DETAILS: Registers npc_on_death_callback, monster_on_death_callback, and actor_on_update (lines 332-335). The actor_on_update handler plays anomaly particles and sounds when explosion_planned is true -- purely visual. The teleport() function (line 179) calls db.actor:set_actor_position(SIMBOARD:get_smart_by_name(iron_forest_smart).position) to warp the player to a smart terrain position during task stage transitions. Multiple SIMBOARD:get_smart_by_name() calls throughout for read-only location lookups.
OUR IMPACT: actor_on_update is additive and lightweight -- safe. Death callbacks are additive and task-specific -- safe. Critical issue: set_actor_position() on the client fights our position sync system which owns authoritative actor position. SIMBOARD:get_smart_by_name() reads are safe on the client.
FIX: Wrap db.actor:set_actor_position() inside teleport() with a check that the caller is the authoritative position owner. Route actor teleports through the MP position sync system rather than direct engine call.

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: tasks_the_living_fire.script
CONFLICT TYPE: Weather/Time
SEVERITY: MEDIUM
DETAILS: Calls level.set_weather_fx("fx_blowout_day") at line 281 inside a CreateTimeEvent triggered during task stage 23 of "The Living Fire" quest.
OUR IMPACT: Our MP code handles weather sync on the client. This mod triggers a weather FX unilaterally on the host -- it is not intercepted by our sync system. The host sees the blowout day FX; clients see normal weather. Desync.
FIX: Intercept level.set_weather_fx calls and broadcast them to all clients via the MP environment sync channel, or monkey-patch level.set_weather_fx globally to route through MP broadcast when called on the host.

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: new_tasks_addon_tasks_utils.script
CONFLICT TYPE: Position/Movement
SEVERITY: MEDIUM
DETAILS: hide_through_teleport(id) function (line 145) uses a CreateTimeEvent to call obj:force_set_position(pos, false) on a dead NPC body -- sinking it 40 units below terrain to hide the corpse.
OUR IMPACT: force_set_position on the host is not replicated to clients. Clients see the corpse in its original surface position; host has it below the map. Visual desync for corpse positions.
FIX: Broadcast body-sink force_set_position calls via the MP position sync channel, or suppress on the client (host owns positional authority).

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: tasks_baba_yaga.script
CONFLICT TYPE: Callback Collision / SIMBOARD/Squad
SEVERITY: MEDIUM
DETAILS: Registers monster_on_death_callback (line 124). Uses SIMBOARD:get_smart_by_name(jelly_smart_terrain).id as task location (line 78) -- read-only lookup.
OUR IMPACT: Additive collision. Monster death triggers task stage advancement. If the callback fires on both host and client, task completion could execute twice.
FIX: Wrap task state modifications inside the monster_on_death_callback with a host-only guard.

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: tasks_house_of_horrors.script
CONFLICT TYPE: Callback Collision / SIMBOARD/Squad
SEVERITY: MEDIUM
DETAILS: Registers monster_on_death_callback (line 152). Uses SIMBOARD:get_smart_by_name(outpost_smart_terrain).id for task location (line 123) -- read-only.
OUR IMPACT: Same pattern as Baba Yaga -- duplicate task completion risk on host and client.
FIX: Wrap task state modifications in the callback with a host-only guard.

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: tasks_brain_game.script
CONFLICT TYPE: Callback Collision
SEVERITY: MEDIUM
DETAILS: Registers monster_on_death_callback (line 83) for task stage tracking.
OUR IMPACT: Additive collision. Task completion could fire on host and client simultaneously.
FIX: Host-only guard on task state modifications.

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: tasks_gambling_with_life.script
CONFLICT TYPE: Callback Collision
SEVERITY: MEDIUM
DETAILS: Registers monster_on_death_callback (line 72) for task tracking.
OUR IMPACT: Additive collision. Duplicate task completion risk.
FIX: Host-only guard on task state modifications.

---
MOD: Pre-0.9.3.1 Saves Fix
FILE: tasks_vengence_amplified.script
CONFLICT TYPE: Callback Collision
SEVERITY: MEDIUM
DETAILS: Registers monster_on_death_callback (line 57) for task tracking.
OUR IMPACT: Additive collision. Duplicate task completion risk.
FIX: Host-only guard on task state modifications.

---
MOD: Serious Tasks QoL Pack
FILE: nta_utils.script
CONFLICT TYPE: Position/Movement
SEVERITY: MEDIUM
DETAILS: Contains hide_through_teleport(id) / force_set_position(pos, false) at line 155 -- identical function to Pre-0.9.3.1 Saves Fix new_tasks_addon_tasks_utils.script. This is the QoL Pack's updated/renamed version of the same utility.
OUR IMPACT: Identical to Pre-0.9.3.1 Saves Fix entry -- corpse body-sink position desync between host and clients. Both mods ship a version of this file; only the active one (determined by load order) needs patching.
FIX: Broadcast body-sink position calls via MP sync, or suppress on client. Identify which version takes load order priority and apply fix there.

---
MOD: Serious Tasks QoL Pack
FILE: tasks_guide.script
CONFLICT TYPE: Callback Collision / SIMBOARD/Squad
SEVERITY: MEDIUM
DETAILS: Registers server_entity_on_unregister (line 286) and actor_on_update (line 278, conditionally registered from actor_on_first_update). The server_entity_on_unregister handler checks if the unregistering entity is the current guide squad and clears guide task state (removes map spots, disables info portions). The actor_on_update handler runs a lightweight timer check.
OUR IMPACT: server_entity_on_unregister additive collision with our host-side despawn broadcast. The clear() call will run on clients when we fire the despawn broadcast, removing PDA map spots and info portions independently on the client -- may produce incorrect task state. actor_on_update collision is lightweight and safe.
FIX: Wrap the clear() call inside squad_on_unregister with a guard ensuring it only executes on the machine that owns guide task state (host). Verify the squad argument our despawn broadcast passes is compatible with the .id field check this handler expects.

---
MOD: Shaders cumulative pack for GAMMA
FILE: item_device.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers on_key_press (line 422) for NVG key handling and server_entity_on_unregister (line 419) for device condition state cleanup when devices unregister.
OUR IMPACT: on_key_press additive collision with our F5 tooltip handler -- both coexist safely. server_entity_on_unregister additive collision with our despawn handler -- device condition cleanup operates on a local mdata table, safe on both host and client.
FIX: No action needed.

---
MOD: Shaders cumulative pack for GAMMA
FILE: ssfx_weapons_dof.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers actor_on_update (line 527) for weapon depth-of-field shader updates, and on_key_press (line 514, conditional) for ADS zoom handling.
OUR IMPACT: Additive collisions. DOF handler is purely visual -- reads weapon zoom state and issues engine shader commands. No entity state, no A-Life interaction.
FIX: No action needed.

---
MOD: Shaders cumulative pack for GAMMA
FILE: z_beefs_nvgs.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers actor_on_update (dynamically at lines 310 and 527) and on_key_press (line 640) for NVG state tracking and brightness controls.
OUR IMPACT: Additive collisions. NVG updates are purely local renderer operations. Shader state is per-client and does not need synchronization.
FIX: No action needed.

---
MOD: Teivaz Gunslinger Knives Quick Melee
FILE: quickdraw.script
CONFLICT TYPE: Callback Collision / Entity Lifecycle
SEVERITY: HIGH
DETAILS: Registers on_key_press (line 9) and actor_on_update (line 10). On kCUSTOM24 key press, hit_key() calls alife():release(alife_object(anm:id())) to release an animation helper item from slot 14 (lines 128, 166), and calls alife():create(knife_name, db.actor:position(), ..., db.actor:id()) to spawn an animation helper item into the actor inventory (line 138). These are direct alife() lifecycle calls triggered by real-time player key input.
OUR IMPACT: on_key_press additive collision with our F5 tooltip handler -- safe. Critical: alife():create() and alife():release() on the client are triggered by the client player pressing the melee key. With suppressed client A-Life, alife():create() will fail, breaking the quick melee animation entirely for the client player. The animation helper entity would not exist in the host entity registry, producing a ghost entity if the call somehow succeeded.
FIX: On the client, route alife():create() for animation helper items through the MP item-spawn request channel so the host creates the entity and syncs it back. Alternatively, if the animation helper item is purely cosmetic (lives only for the animation duration in slot 14), implement a client-local ephemeral spawn that bypasses the A-Life registry.

---
MOD: Teivaz's Gunslinger Exo Animations Port
FILE: enhanced_animations.script
CONFLICT TYPE: Callback Collision
SEVERITY: LOW
DETAILS: Registers on_key_press (line 40, one-time version-check tooltip) and dynamically registers actor_on_update during animation playback (line 88), unregistering it when animation starts (line 130). The actor_on_update handler monitors weapon slot state to detect when the actor slot is clear for animation startup.
OUR IMPACT: on_key_press additive collision -- version check fires once, benign. actor_on_update is dynamically registered only during active animation setup (very short window). No entity lifecycle calls, no A-Life interaction.
FIX: No action needed. Pure animation state machine.

---
MOD: Wildkins's Ammo Parts on Hover
FILE: itms_manager.script
CONFLICT TYPE: Entity Lifecycle / A-Life Dependency
SEVERITY: HIGH
DETAILS: Full replacement of the base Anomaly itms_manager.script with ammo parts tooltip additions. The file retains all original item-processing logic including ItemProcessor:Create_Item() (line 1254), which calls alife():create(section, pos, lvi, gvi, pid) (lines 1340, 1342) when spawning items from disassembly, crafting, or loot processing. These are triggered by player inventory interactions.
OUR IMPACT: Any client-initiated item creation (disassembly, crafting) will call alife():create() against the client's suppressed A-Life. On the client these calls will silently fail or crash, meaning crafting and disassembly are non-functional for the client player. This is a core gameplay mechanic, not cosmetic.
FIX: Within ItemProcessor:Create_Item(), conditionally route alife():create() calls through the MP item-spawn request channel when running on a client. The client sends a spawn request to the host; the host creates the entity via A-Life and syncs it back. This is a substantial integration task given itms_manager's breadth.

---
MOD: ilrathCXV's Meat Spoiling Timer in Tooltips
FILE: meat_spoiling.script
CONFLICT TYPE: Callback Collision / A-Life Dependency
SEVERITY: LOW
DETAILS: Registers actor_on_update (line 183). The handler (line 38) tracks elapsed game time and calls tick_expiration() once per in-game second to update meat item spoilage in the player inventory. Uses alife_object() read-only to check if a meat item parent is a placeable_fridge.
OUR IMPACT: actor_on_update additive collision -- safe. Meat spoiling is per-player-inventory local state with no required network sync. The alife_object() read for fridge detection is safe on the client. Game time is synchronized via our level.set_game_time() sync, so spoilage rates are consistent across host and client.
FIX: No action needed.

---

## SUMMARY TABLE

| MOD | FILE | CONFLICT TYPE | SEVERITY |
|-----|------|---------------|----------|
| Warfare Patch | sim_squad_scripted.script | Callback Collision / SIMBOARD | CRITICAL |
| ZCP 1.5d | sim_squad_scripted.script | Callback Collision / SIMBOARD | CRITICAL |
| ZCP 1.5d | smart_terrain.script | Callback Collision / SIMBOARD | CRITICAL |
| ZCP 1.5d | game_setup.script | Entity Lifecycle / A-Life / SIMBOARD / Position | CRITICAL |
| ZCP 1.5d | smr_loot.script | Callback Collision / A-Life | HIGH |
| ZCP 1.5d | smr_pop.script | SIMBOARD / Entity Lifecycle | HIGH |
| ZCP 1.5d | bind_awr.script | Callback Collision | MEDIUM |
| xcvb's Guards Spawner | guards_spawner.script | Callback Collision / SIMBOARD / Global Pollution | HIGH |
| xcvb's Guards Spawner | emission_guard_patch.script | A-Life Dependency | LOW |
| Pre-0.9.3.1 Saves Fix | tasks_mirage.script | Callback Collision / Position/Movement | HIGH |
| Pre-0.9.3.1 Saves Fix | tasks_the_living_fire.script | Weather/Time | MEDIUM |
| Pre-0.9.3.1 Saves Fix | new_tasks_addon_tasks_utils.script | Position/Movement | MEDIUM |
| Pre-0.9.3.1 Saves Fix | tasks_baba_yaga.script | Callback Collision / SIMBOARD | MEDIUM |
| Pre-0.9.3.1 Saves Fix | tasks_house_of_horrors.script | Callback Collision / SIMBOARD | MEDIUM |
| Pre-0.9.3.1 Saves Fix | tasks_brain_game.script | Callback Collision | MEDIUM |
| Pre-0.9.3.1 Saves Fix | tasks_gambling_with_life.script | Callback Collision | MEDIUM |
| Pre-0.9.3.1 Saves Fix | tasks_vengence_amplified.script | Callback Collision | MEDIUM |
| Serious Tasks QoL Pack | nta_utils.script | Position/Movement | MEDIUM |
| Serious Tasks QoL Pack | tasks_guide.script | Callback Collision / SIMBOARD | MEDIUM |
| Teivaz Gunslinger Knives Quick Melee | quickdraw.script | Callback Collision / Entity Lifecycle | HIGH |
| Wildkins's Ammo Parts on Hover | itms_manager.script | Entity Lifecycle / A-Life Dependency | HIGH |
| Shaders cumulative pack for GAMMA | item_device.script | Callback Collision | LOW |
| Shaders cumulative pack for GAMMA | ssfx_weapons_dof.script | Callback Collision | LOW |
| Shaders cumulative pack for GAMMA | z_beefs_nvgs.script | Callback Collision | LOW |
| Teivaz's Gunslinger Exo Animations Port | enhanced_animations.script | Callback Collision | LOW |
| ilrathCXV's Meat Spoiling Timer in Tooltips | meat_spoiling.script | Callback Collision / A-Life Dependency | LOW |
"""

with open('C:/Users/jonah/Documents/GitHub/stalker-gamma-online/gamma-mp/audit_results/findings_6.md', 'w', encoding='utf-8') as f:
    f.write(content)
print("Written successfully, size:", len(content))
