# Audit Findings - Chunk 1

**Base directory:** Stalker_GAMMA/G.A.M.M.A/modpack_addons/
**Date:** 2026-04-15
**Note:** All .script files in all listed mod folders were read or searched. Mods with no script files or no conflicts are omitted from conflict entries. Findings ordered by severity.

---
MOD: Anomaly Magazines Redux (need to disable GAMMA unjam reload same key)
FILE: magazines.script
CONFLICT TYPE: Callback Collisions -- actor_on_update
SEVERITY: CRITICAL
DETAILS: Registers actor_on_update (line 1078). Callback body (lines 619-624) polls enhanced_animations.used_item every tick and may call do_interrupt(). The same file registers on_before_key_press (line 1070) as its on_key_press handler; that function body (line 842) intercepts the reload keybind and sets flags.ret_value = false, consuming the reload event entirely.
OUR IMPACT: Our MP actor_on_update is the main sync loop. If enhanced_animations is nil on a client (animations suppressed), the nil-index on used_item will error every tick, choking our update loop. The reload-key interception (flags.ret_value = false) fires on both host and client, blocking reloads on the client regardless of MP state.
FIX: Nil-guard enhanced_animations.used_item in the callback. Add is_client() early return to the reload-block branch of on_key_press.
---
MOD: Anomaly Magazines Redux (need to disable GAMMA unjam reload same key)
FILE: magazines.script
CONFLICT TYPE: Entity Lifecycle Interference
SEVERITY: CRITICAL
DETAILS: alife_create_item called at line 495 (spawning a se_mag into weapon parent) and line 425 (refunding ammo to actor). Both unconditional inside magazine reload logic executing on every weapon reload. alife_clone_weapon (unjam_weapon ~line 638) also invokes alife create/clone.
OUR IMPACT: On MP client A-Life is suppressed. alife_create_item on client crashes or produces ghost entities never registered in host entity tracking. Magazine items and refunded ammo will not exist on the host -- core desync vector.
FIX: Wrap all alife_create_item calls with is_host() guard. On client fire RPC to host requesting spawn. Apply same treatment to alife_clone_weapon.
---
MOD: Anomaly Magazines Redux (need to disable GAMMA unjam reload same key)
FILE: magazines_loot.script
CONFLICT TYPE: Callback Collisions -- npc_on_death_callback
SEVERITY: CRITICAL
DETAILS: Registers npc_on_death_callback (line 235) as npc_on_death. Iterates dead NPC inventory and calls alife_create_item(to_create, npc) for each magazine to spawn (lines 93-149). Fires on every machine with the callback registered.
OUR IMPACT: Our MP npc_on_death_callback broadcasts death from host. Magazines callback running on client calls alife_create_item with suppressed A-Life -- crash or ghost items invisible to other players. On host, magazines created outside entity tracking registry so clients never receive spawn packets.
FIX: Add if not is_client() then guard around alife_create_item block in npc_on_death. On client this must be a no-op for spawning.
---
MOD: Anomaly Magazines Redux (need to disable GAMMA unjam reload same key)
FILE: magazines_loot.script
CONFLICT TYPE: Global Table Pollution -- monkey-patch of death_manager.set_weapon_drop_condition
SEVERITY: CRITICAL
DETAILS: Lines 162-163 capture and unconditionally replace death_manager.set_weapon_drop_condition. Replacement calls itm:unload_magazine() and random_pop_mag() on every weapon drop on death. random_pop_mag() mutates mags_storage and calls prep_weapon with further alife interactions. Permanent replacement.
OUR IMPACT: On client, random_pop_mag mutates local-only mags_storage diverging from host. itm:unload_magazine() may crash if game object absent client-side. Replacement is permanent -- our MP shim cannot selectively disable post-load.
FIX: Add is_host() guard inside replacement body so magazine-specific logic only runs on host. Chain to SetWepCondition is safe to call regardless.
---
MOD: Anomaly Magazines Redux (need to disable GAMMA unjam reload same key)
FILE: magazines_loot.script
CONFLICT TYPE: Global Table Pollution -- monkey-patch of trader_autoinject.update
SEVERITY: HIGH
DETAILS: Lines 33-40 replace trader_autoinject.update(npc) globally. Replacement calls stock_mags(npc) which calls trader_autoinject.spawn_items(npc, to_spawn, true). Trader restocking is an A-Life event.
OUR IMPACT: On client with suppressed A-Life, trader_autoinject.spawn_items attempts to create items via alife -- crash or local-only items invisible to other players. Traders are host-authoritative in MP.
FIX: Guard stock_mags call with if not is_client() then. On client call only the original TraderAuto(npc).
---
MOD: Anomaly Magazines Redux (need to disable GAMMA unjam reload same key)
FILE: mags_patches.script
CONFLICT TYPE: Global Table Pollution -- monkey-patches item_parts.disassembly_weapon, item_weapon.unload_all_weapons, item_weapon.start_ammo_wheel, item_weapon.detach_scope, item_weapon.attach_scope
SEVERITY: HIGH
DETAILS: Lines 84-85 replace item_parts.disassembly_weapon. Lines 165-166 replace item_weapon.unload_all_weapons. Lines 526 and 862-865 replace item_weapon.start_ammo_wheel, detach_scope, attach_scope. All unconditional at load time. Disassembly and unload paths call alife_create_item indirectly (spawning parts, loose ammo).
OUR IMPACT: Any path resulting in alife_create_item or alife_release executes on both host and client. Client alife calls fail silently or crash. Replacements are permanent.
FIX: Insert is_host() guards inside each replacement body wherever alife entity creation/release is invoked. Full line-by-line review of mags_patches.script required.
---
MOD: Anomaly Magazines Redux (need to disable GAMMA unjam reload same key)
FILE: magazine_binder.script
CONFLICT TYPE: Callback Collisions -- server_entity_on_unregister
SEVERITY: MEDIUM
DETAILS: on_game_start (line 736) registers server_entity_on_unregister as se_item_on_unregister (clears mags_storage[id] and carried_mags[id]). magazines.script (line 1076) registers a second server_entity_on_unregister. Both fire concurrently on all machines. 4 total registrations (2 Mags Redux + 2 MP).
OUR IMPACT: Magazine callbacks only clear local data tables -- no entity lifecycle operations. Callback ordering not guaranteed. Our MP handler must read ID mapping before magazine cleanup nulls local tables.
FIX: No fix required for Phase 0. Document for Phase 1: ensure MP server_entity_on_unregister executes before magazine cleanup.
---
MOD: ATHI's Mags Redux Mod Madness 19.1.2025+
FILE: magazines_loot.script
CONFLICT TYPE: Callback Collisions -- npc_on_death_callback
SEVERITY: CRITICAL
DETAILS: Line 185 registers npc_on_death_callback as npc_on_death -- structurally identical to base Anomaly Magazines Redux, same alife_create_item pattern (lines 97-99). May register a second npc_on_death_callback on top of base mod registration.
OUR IMPACT: Identical to Anomaly Magazines Redux magazines_loot.script finding. Two separate npc_on_death_callback registrations both attempt alife_create_item on client with suppressed A-Life.
FIX: Same fix -- is_host() guard inside npc_on_death before alife_create_item block.
---
MOD: ATHI's Mags Redux Mod Madness 19.1.2025+
FILE: magazines_loot.script
CONFLICT TYPE: Global Table Pollution -- monkey-patch of death_manager.set_weapon_drop_condition
SEVERITY: CRITICAL
DETAILS: Lines 112-113 replace death_manager.set_weapon_drop_condition identically to base Anomaly Magazines Redux. With both mods loaded this replacement fires twice. Second load (ATHI) overwrites first replacement SetWepCondition closure -- double-patch bug. Net effect depends on load order; one extension may be silently dropped.
OUR IMPACT: Same as base Anomaly Magazines Redux. alife-touching code still runs on client. Double-patch is itself a standalone bug.
FIX: Same is_host() guard. Only one magazines_loot.script should be active or they need merging.
---
MOD: ATHI's Mags Redux Mod Madness 19.1.2025+
FILE: actor_stash_patch.script
CONFLICT TYPE: Entity Lifecycle Interference -- alife_create / alife_release / alife_release_id
SEVERITY: HIGH
DETAILS: Line 34 calls alife_create("inv_backpack", ...) to create a world stash. Line 48 calls alife_release(backpack) to remove backpack item from actor. Line 71 (UICreateStash:OnAccept) calls alife_create("inv_backpack", ...) again. Line 86 calls alife_release_id(self.id). Fires when player uses backpack item or confirms stash creation.
OUR IMPACT: On client, alife_create fails or creates local-only stash not tracked by host entity registry. alife_release on client releases entity host still owns -- host entity state corruption. Stash invisible to other players; map marker added for non-existent entity.
FIX: Wrap stash creation logic in is_host() or implement as client-to-host RPC. Host creates entity, broadcasts via server_entity_on_register, sends new ID and map marker data back to requesting client.
---
MOD: 294- Autolooter - iTheon
FILE: z_auto_looter.script
CONFLICT TYPE: Entity Lifecycle Interference -- alife():release() and alife_release()
SEVERITY: CRITICAL
DETAILS: handle_delete (lines 404-430) calls sim:release(sim:object(actor:id())) to delete NPC bodies and alife_release(v) to delete individual items when config.delete_body / delete_weapon / delete_armor / delete_misc options enabled.
OUR IMPACT: On client, alife() is suppressed. sim:release(sim:object(...)) crashes on nil or attempts to release host-owned entity -- host entity state corruption. alife_release on client has same problem. Host entity tracking registry becomes inconsistent -- entities become zombies: alive on host, ghost-deleted on client.
FIX: Wrap entire body of handle_delete in if not is_client() then. On client optionally send RPC to host requesting entity deletion.
---
MOD: 294- Autolooter - iTheon
FILE: z_auto_looter.script
CONFLICT TYPE: Callback Collisions -- on_key_press
SEVERITY: HIGH
DETAILS: Line 502 registers on_key_press as auto_looter function. On hotkey press invokes handle_delete (entity releases), handle_disassemble (calls item_parts.func_disassembly spawning parts via alife_create_item), and handle_strip (scope detach touching alife). Fires on both host and client.
OUR IMPACT: Our MP on_key_press shows F5-blocked tooltip. Auto-looter handler runs concurrently on client triggering full entity-destructive pipeline on suppressed A-Life.
FIX: Add is_client() early return at top of auto_looter, or strip entity-destructive paths behind is_host() guards.
---
MOD: 294- Autolooter - iTheon
FILE: zzzz_auto_looter_fix_by_kdvfirehawk.script
CONFLICT TYPE: Global Table Pollution -- monkey-patches item_parts.get_suitable_dtool and handle_disassemble
SEVERITY: HIGH
DETAILS: Line 40 replaces item_parts.get_suitable_dtool (global table entry). Line 123 replaces global handle_disassemble. The handle_disassemble replacement calls item_parts.func_disassembly(v, obj_d) inside CreateTimeEvent callbacks -- spawns part items via alife_create_item.
OUR IMPACT: handle_disassemble is a bare global -- any caller gets this version. CreateTimeEvent deferral makes it harder to guard at call sites. Fires alife_create_item on client.
FIX: Add is_client() guard inside handle_disassemble replacement before item_parts.func_disassembly call.
---
MOD: 45- Stealth Overhaul - xcvb
FILE: xr_danger.script
CONFLICT TYPE: Callback Collisions -- npc_on_death_callback
SEVERITY: MEDIUM
DETAILS: Line 252 registers npc_on_death_callback. Callback (lines 117-125) sets st.killer_last_known_position in db.storage[npc:id()]. Guarded by if (st) then at line 120. No alife calls.
OUR IMPACT: Fires on client too. db.storage[npc:id()] may be nil on client but guard prevents crash. Client-side stealth memory silently non-functional -- acceptable Phase 0.
FIX: No fix required for Phase 0.
---
MOD: 45- Stealth Overhaul - xcvb
FILE: xr_combat_ignore.script
CONFLICT TYPE: Callback Collisions -- npc_on_death_callback
SEVERITY: MEDIUM
DETAILS: Line 57 registers npc_on_death_callback (local function line 34). Clears safe_zone_npcs[npc:id()] -- pure table nil-set. alife() usage at lines 170/370/398 is read-only sim:object() lookup only.
OUR IMPACT: Fires on client. Table nil-set is harmless. sim:object() read is safe with suppressed A-Life (returns nil). Acceptable Phase 0.
FIX: No fix required for Phase 0.
---
MOD: 45- Stealth Overhaul - xcvb
FILE: light_gem_mcm.script
CONFLICT TYPE: Callback Collisions -- actor_on_update
SEVERITY: LOW
DETAILS: Line 14 registers actor_on_update as light_gem. Reads get_hud() and calls AddCustomStatic/GetCustomStatic for stealth light indicator -- purely visual HUD manipulation, no entity operations.
OUR IMPACT: Runs concurrently with MP actor_on_update. No entity lifecycle or save interference.
FIX: None required for Phase 0.
---
MOD: 409- Mark Switch - party50 & meowie
FILE: z_mark_switch.script
CONFLICT TYPE: Callback Collisions -- actor_on_update and server_entity_on_unregister
SEVERITY: LOW
DETAILS: Line 185 registers actor_on_update -- calls update_shader(wpn, info), visual only. Line 186 registers server_entity_on_unregister -- clears current_marks[obj.id], pure local table nil-set.
OUR IMPACT: actor_on_update is HUD/visual only. server_entity_on_unregister does not interfere with our ID mapping cleanup.
FIX: None required for Phase 0.
---
MOD: 41- LowerSprintAnimaiton - Skieppy
FILE: lower_weapon_sprint.script
CONFLICT TYPE: Callback Collisions -- actor_on_update, on_key_press
SEVERITY: LOW
DETAILS: Line 336 registers actor_on_update (calls wpn:switch_state(), level.press_action() -- local animation only). Line 364 registers on_key_press (sets local booleans -- no entity ops).
OUR IMPACT: All operations client-local. No entity or save-system impact.
FIX: None required for Phase 0.
---
MOD: 65- Fluid Aim - Skieppy
FILE: fluid_aim.script
CONFLICT TYPE: Callback Collisions -- actor_on_update, on_key_press
SEVERITY: LOW
DETAILS: Line 179 registers actor_on_update (reads key states, calls wpn:switch_state()/level.press_action() -- local aim/anim handling). Line 177 registers on_key_press (sets local booleans).
OUR IMPACT: Player-view-only. No entity lifecycle or save interference.
FIX: None required for Phase 0.
---
MOD: 423- Mossberg 590 Reanimation - SoulCrystal
FILE: uni_anim_detectors.script
CONFLICT TYPE: Callback Collisions -- on_key_press
SEVERITY: LOW
DETAILS: Line 197 registers on_key_press (function line 45). Handles detector quick-hide on PDA/NVG key -- sets local force_quick flag. No entity lifecycle.
OUR IMPACT: No entity lifecycle or save interference. Client-safe.
FIX: None required for Phase 0.
---
MOD: 393- Disassembly Item Tweaks - Asshall
FILE: zzz_dit.script
CONFLICT TYPE: Callback Collisions -- on_key_press
SEVERITY: LOW
DETAILS: Line 129 registers on_key_press. Callback (lines 104-110) sets boolean flags d_flag and b_flag for modifier keys. No entity operations.
OUR IMPACT: No conflict. Flags gate inventory UI actions which are client-local.
FIX: None required for Phase 0.
---
MOD: 447- FDDA Redone - lizzardman
FILE: liz_fdda_redone_consumables.script
CONFLICT TYPE: Entity Lifecycle Interference -- alife_release / alife_create_item
SEVERITY: MEDIUM
DETAILS: Line 46 calls alife_release(obj_dummy) on first update to clean up leftover items_anm_dummy. Line 180 calls alife_create_item("items_anm_dummy", db.actor) during item-use animation start. Throwaway entities suppress vanilla item-use sound.
OUR IMPACT: On client, alife_create_item fails or creates local-only dummy entity. alife_release fails silently or errors. Animation system stalls (item flagged in-use but dummy never spawns so consume trigger never fires). Error spam in client logs.
FIX: Add if not is_client() then guard around both alife_create_item and alife_release calls. On client suppress FDDA animations or implement local-only dummy bypass not touching A-Life.
---
MOD: 447- FDDA Redone - lizzardman
FILE: liz_fdda_redone_consumables.script
CONFLICT TYPE: Global Table Pollution -- monkey-patches itms_manager.actor_on_item_before_use and ui_inventory.UIInventory.ParseInventory
SEVERITY: MEDIUM
DETAILS: Lines 136-139 replace itms_manager.actor_on_item_before_use with chained wrapper that sets flags.ret_value = false to delay item use for FDDA animation. Lines 142-154 replace ui_inventory.UIInventory.ParseInventory to filter items_anm_dummy from display.
OUR IMPACT: On client where alife_create_item for dummy fails, item use is blocked (flag set false) but animation stalls -- player stuck unable to use items. ParseInventory patch is read-only and safe. actor_on_item_before_use patch is the dangerous one.
FIX: In modifiedAOIBU add if is_client() then return end before the FDDA animation branch, or ensure dummy entity path is client-safe.
---
MOD: 52- Perk-Based Artefacts - Demonized
FILE: zz_treasure_manager_pba_less_artys.script
CONFLICT TYPE: Entity Lifecycle Interference -- alife_release_id
SEVERITY: MEDIUM
DETAILS: Line 66 calls alife_release_id(k) inside clean_artys when a stash box is opened. Randomly removes artefacts by probability roll. Triggered via physic_object_on_use_callback registered on actor_on_first_update (line 110). Both host and client can open stashes.
OUR IMPACT: On client, alife_release_id with suppressed A-Life fails silently or errors. If host and client both run clean_artys with different random seeds, different items removed -- stash-content desync. Client alife_release_id may generate spurious server_entity_on_unregister events interfering with entity tracking registry.
FIX: Add if is_client() then return end at top of physic_object_on_use_callback. Stash content manipulation must be host-authoritative.
---

## MODS WITH NO CONFLICTS (confirmed clean)

| Mod | Reason |
|---|---|
| 293- PDA Taskboard - iTheon | UI only, on_key_release non-conflicting |
| 302- Minimalist companion UI - Kageeskl | No .script files |
| 304- Dark Signal Weather and Ambiance Audio - Shrike | No .script files |
| 307- GAMMA French Patch - XDomWeedX | No .script files |
| 312- Gunslinger Guns for Anomaly | No .script files |
| 318- BAS Saiga Reanimation v2 - Synd1cate | No .script files |
| 322- Tactical Torch Reanimation - Skywhyz | No .script files |
| 327- Semi Radiant AI - xcvb | Config .ltx files only |
| 332- QoL Patch to RF Receiver - Cookbook | MCM config script only |
| 336- Item UI Improvements - Utjan | UI display script only |
| 337- QoL Bundle - Utjan | z_fetch_shows_count.script -- no conflicting callbacks |
| 341- Extra Level Transitions Fix - Qball | No .script files |
| 343- G.A.M.M.A. Traduccion Espanola | No .script files |
| 355- Steyr Scout - JMerc75 | No .script files |
| 360- GAMMA Reload Timing Fix - aegis27 | No .script files |
| 363- Winchester 1892 - billwa | ammo_check_mcm.script -- MCM only |
| 385- Even More Hideout Furnitures | No .script files |
| 394- Return Menu Music - Mirrowel | main_menu callbacks only |
| 40- FDDA - Feel_Fried | enhanced_animations_mcm.script -- MCM only |
| 410- 3DSS for GAMMA | zoom calc only, on_key_release non-conflicting |
| 411- Renegades Fixed Ports Collection | No .script files |
| 416- Devices of Anomaly Redone | No .script files |
| 418- Dynamic Icons Indicators - HarukaSai | MCM and UI only |
| 419- Artefacts Belt Scroller | No .script files |
| 422- Desert Eagle Re-animated | No .script files |
| 428- Authentic Reticle for 3DSS | No .script files |
| 429- The Covenant Weapon Pack 3DSS | No .script files |
| 432- BRN-180 Assault Rifle - JMerc75 | No .script files |
| 433- UDP-9 Carbine - Pilliii | No .script files |
| 437- Weighted NPC Random Loadouts - SD | No .script files |
| 439- The Covenant Weapon Pack for DX9 | No .script files |
| 443- Photo of a Loved One Animated | No .script files |
| 49- Skill System - Haruka | No .script files |
| 51- Tougher important NPCs - hexef | alife() read-only sim:object() lookup only |
| 54- Lsz AI tweak - IgorNitch | placeholder.script -- empty |
| 91- Pretty Pistols Pack - Blackgrowl | alife_create_item calls commented out |
| 95- Doom-like weapon inspection - Grokitach | actor_on_update is read-only anim state check |
| Anomaly 1.5.2 fixes | No .script files |
| Anomaly 1.5.3 Shaders Fix | No .script files |
| AlphaLion's Reworked Stash Quest and Map Markers | on_xml_read callbacks only |

---

## SUMMARY TABLE

| Severity | Count | Primary Mods Affected |
|---|---|---|
| CRITICAL | 6 | Anomaly Magazines Redux (4), ATHI Mags Redux (2), Autolooter (1) |
| HIGH | 5 | Anomaly Magazines Redux (2), ATHI Mags Redux (1), Autolooter fix (2) |
| MEDIUM | 5 | Stealth Overhaul (2), FDDA Redone (2), Perk-Based Artefacts (1) |
| LOW | 6 | Stealth Overhaul light gem, Mark Switch, LowerSprint, Fluid Aim, Mossberg Reanim, Disassembly Tweaks |

**Priority fix order for MP launch:**
1. Anomaly Magazines Redux + ATHI Mags Redux: npc_on_death_callback alife_create_item on death (CRITICAL -- every NPC kill)
2. Anomaly Magazines Redux + ATHI Mags Redux: death_manager.set_weapon_drop_condition monkey-patch (CRITICAL -- every NPC death drop)
3. Autolooter: alife():release() / alife_release() in handle_delete (CRITICAL -- user-triggered)
4. Anomaly Magazines Redux: alife_create_item in reload/unjam path (CRITICAL -- every weapon reload)
5. ATHI Mags Redux: actor_stash_patch.script backpack stash create/release (HIGH -- user-triggered)
6. Anomaly Magazines Redux: mags_patches.script global table pollution of item_parts/item_weapon (HIGH -- disassembly and weapon interactions)
7. Autolooter + fix script: on_key_press and handle_disassemble alife paths (HIGH -- user-triggered)
8. FDDA Redone: alife_create_item dummy + itms_manager monkey-patch (MEDIUM -- every item use)
9. Perk-Based Artefacts: alife_release_id on stash open (MEDIUM -- user-triggered, desync risk)