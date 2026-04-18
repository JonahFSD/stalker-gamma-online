# Client Connection Sequence Map

*Research deliverable. No code has been written. Synthesis of 5 parallel investigation tracks plus cross-track verification.*

**Bottom line up front:** The central hypothesis is **CONFIRMED**. The client's native A-Life is fully populated from `all.spawn` during level load, **before** `set_mp_client_mode(true)` is ever called. Every fixed-identity entity (`story_id`-bearing: NPCs, story squads, quest items) exists twice on the client when the host streams it — once from `CALifeStorageManager::load`, once from `ENTITY_SPAWN`. The engine's `CALifeStoryRegistry::add` aborts on duplicate by default.

**Recommended next patch:** Strategy C2 (Lua-side client pre-apply de-dup using host-supplied `story_id`), layered with a small Strategy A broadcast filter for bandwidth. Rationale and diff sketch in §8.

---

## 1. What happens on connect (timeline)

End-to-end, from user click to crash:

1. **Level load** (singleplayer flow, client-side): user hits Continue → engine `game_sv_Single::load_game` → `CALifeUpdateManager::load_game` → `CALifeUpdateManager::load` (`alife_update_manager.cpp:281-307`) → `CALifeStorageManager::load(save_name)` (`alife_storage_manager.cpp:169-232`) → `CALifeStorageManager::load(buffer,...)` (`alife_storage_manager.cpp:126-167`).
2. Spawn file parsed: `spawns().load(source, file_name)` (`alife_storage_manager.cpp:139`, dispatches to `alife_spawn_registry.cpp:54-79`). This reads `$game_spawn$/*.spawn`, game graph, patrol paths, and story-id token tables.
3. `objects().load(source)` deserializes every persisted `CSE_ALifeDynamicObject`.
4. Registration loop (`alife_storage_manager.cpp:153`): `register_object((*I).second, false)` is called for every entity. This funnels through `CALifeSimulatorBase::register_object()` (`alife_simulator_base2.cpp:23-56`), which inserts into `story_objects()` at line 32: `story_objects().add(object->m_story_id, object)` (via `CALifeStoryRegistry::add` — `alife_story_registry.cpp:20-40`). **Every story_id in the world is now registered on the client.**
5. Second pass (`alife_storage_manager.cpp:160-161`): per-object `on_register()` runs, firing `_G.CSE_ALifeDynamicObject_on_register` functor for each.
6. Engine finishes load; `Level().OnAlifeSimulatorLoaded()` (`Level.cpp:1777-1782`) fires.
7. Lua bootstrap: `axr_main.on_game_start()` → every registered script's `on_game_start`. Our `mp_core.on_game_start` (`mp_core.script:508`) registers `actor_on_update` and installs `mp_alife_guard`.
8. Actor spawns, `actor_on_first_update` fires (Lua, via `_g.script:2319 alife_first_update` — which itself iterates `alife:object(1..65534)` assuming a populated world).
9. **User sits in a loaded, populated level.** Client A-Life already contains every story NPC, story squad, etc. with their canonical story_ids registered.
10. User opens F10 menu, clicks **Connect**. `mp_connect()` → `gns.connect()`. Returns immediately (async).
11. `mp_update` (every frame, `mp_core.script:318`) polls GNS. Several ticks later `EVENT_CONNECTED` arrives → `mp_on_connection_event` (`:354-396`) → `mp_activate_client_mode()` (`:128-145`) → `alife():set_mp_client_mode(true)` at line 134. **Too late — damage is done.** This flag only silences the per-frame simulator tick in `CALifeUpdateManager::update` / `shedule_Update` (`alife_update_manager.cpp:114-119, 121-146`, per patch `alife_update_manager.cpp.patch`). It has no effect on initial population, which already ran ~30 s ago at step 4.
12. Host sends `FULL_STATE` (`mp_host_events.script:570`) → client enters `STATE_CLEANING` (iterates `alife:object(1..65534)`, releases everything — this does attempt to empty the native A-Life, but see §3.2 on leakage).
13. Host streams `ENTITY_SPAWN` at 50/frame (`:502-556`). For every host entity, `mp_client_state.do_entity_spawn_inner` (`mp_client_state.script:180-238`) calls `mp_alife_guard.internal_create(sim, section, pos, lvid, gvid)` — **without** a `story_id` arg (the wire payload has no `story_id` field per §4).
14. Engine `alife():create()` funnels through `CALifeSimulatorBase::spawn_item` → `register_object` → `story_objects().add(m_story_id, object)`. The section's `.ltx` supplies `m_story_id = ah_sarik_squad` (for example). The registry already holds an entry for that id (a survivor of CLEANING, or a re-leaked native object, or the client's native copy never fully released).
15. **Collision.** `CALifeStoryRegistry::add` (`alife_story_registry.cpp:20-40`) hits the `I != m_objects.end()` branch; with `duplicate_story_id_crash = TRUE` (default, `alife_story_registry.cpp:19`, CVar at `console_commands.cpp:3040`), asserts fatally via `R_ASSERT4(no_assert, ...)` → `Debug.fail` → native crash at `AnomalyDX11AVX.exe+0x000000014013BCF8`. If GAMMA ships with the CVar set to `0` (possible — runtime install not inspected), the assert is skipped but the object is dropped from the registry while still inserted into every other registry (objects/graph/scheduled/smart_terrains/groups at `alife_simulator_base2.cpp:28-34`), leaving a split-brain object. The Lua-side parallel registry (see §2.3) then warns and a downstream deref crashes a few frames later — consistent with the observed "warning, then crash" pattern.

---

## 2. Engine crash site analysis (Track 1)

### 2.1 Story Objects registry

- **Class:** `CALifeStoryRegistry` — `xrGame\alife_story_registry.h:15-29`.
- **Shape:** `DEFINE_MAP(_STORY_ID, CSE_ALifeDynamicObject*, STORY_P_MAP, STORY_P_PAIR_IT);` at `alife_space.h:211`. `story_id → CSE_ALifeDynamicObject*` (raw pointer).
- **Add:** `alife_story_registry.cpp:20-40`. On duplicate:
  - `duplicate_story_id_crash == TRUE` + `no_assert == false` (the default from `register_object`): `R_ASSERT4(no_assert, "Specified story object is already in the Story registry!", ...)` → fatal.
  - `duplicate_story_id_crash == FALSE`: `Msg("![CALifeStoryRegistry::add] Specified story object is already in the Story registry! ...")` + early return; object is **dropped** from story registry only.
- **CVar (verified):** registered at `console_commands.cpp:3040` as `CMD4(CCC_Integer, "duplicate_story_id_crash", &duplicate_story_id_crash, 0, 1);`. Default `TRUE` at `alife_story_registry.cpp:19`.
- **The log line `~ Story Objects | Multiple objects trying to use same story_id ah_sarik_squad` does NOT match the engine string.** That engine string is `"![CALifeStoryRegistry::add] Specified story object is already in the Story registry!"`. The log line is emitted by a Lua-side parallel story registry (GAMMA / Anomaly `_g.script` or `bind_story_object.script` family — not in the xray-monolith tree or in the Stalker_GAMMA vanilla extract we have). **This means there are TWO story registries in play — engine and Lua** — and the Lua one is what emits the warning. The engine registry's reaction is governed by the CVar above.

### 2.2 Registration and lookup call sites

- **Single engine insertion site:** `CALifeSimulatorBase::register_object()` — `alife_simulator_base2.cpp:32`: `story_objects().add(object->m_story_id, object)`.
- **Single engine removal site:** `CALifeSimulatorBase::unregister_object()` — `alife_simulator_base2.cpp:68`: `story_objects().remove(object->m_story_id)`.
- **Lua-exposed lookup:** `alife():story_object(id)` — `alife_simulator_script.cpp:80` → `self->story_objects().object(id, /*no_assert=*/true)` → returns 0 on miss. Binding at `alife_simulator_script.cpp:607`.
- **Enum exposure to Lua:** `story_ids` and `spawn_story_ids` are exposed as luabind enums (`alife_simulator_script.cpp:672, 692`) — Lua sees `story_ids._story_ids["ah_sarik"]` resolving to the numeric story_id.
- `m_story_id` is a **readable field** on `CSE_ALifeObject` from Lua: `.def_readonly("m_story_id", &CSE_ALifeObject::m_story_id)` at `xrServer_Objects_ALife_script.cpp:58`. **This is load-bearing for Strategy C2** — the client can read the story_id of any native se_obj it holds.

### 2.3 Crash at RVA 0x13BCF8

**VERIFIED:** `C:\ANOMALY\appdata\user.ltx:96` contains `duplicate_story_id_crash 1` explicitly. The crash is the **direct** mechanism:

- **Direct (CONFIRMED):** `duplicate_story_id_crash == TRUE` → `R_ASSERT4(no_assert, "Specified story object is already in the Story registry!", ...)` fires → `Debug.fail` → native crash reporter. RVA 0x13BCF8 is the assert path in the patched build. The Lua-side `~ Story Objects | Multiple objects trying to use same story_id ah_sarik_squad` warning fires first (from a Lua parallel registry — text not locatable in engine source or in C:\GAMMA\mods\**\*.script, possibly in a compiled .xr or the base Anomaly install; see §7 Q3), but the fatal event is the immediate engine R_ASSERT4 a few ticks later.

(Alternate downstream path — CVar == 0 → `Msg` + early-return + stale-pointer deref — is not in play on this machine. Mentioned for completeness only.)

**Immediate implication:** setting `duplicate_story_id_crash 0` via console on the client would convert the fatal crash into a non-fatal warning + split-brain registry state. That's a valid **stopgap** while C2 is developed, but not a real fix — the entity ends up inserted in every non-story registry with its story slot dropped, creating latent correctness bugs. C2 remains the correct target.

### 2.4 Patchability assessment

**Cheapest mitigation (only viable if CVar is `1` currently):** Add `execute("duplicate_story_id_crash 0")` via Lua at `mp_activate_client_mode`. Suppresses the immediate assert. Does NOT address downstream stale-pointer reads or the Lua-side registry warning/crash. Stopgap only.

**Better engine fix (contingent):** In `CALifeStoryRegistry::add` (`alife_story_registry.cpp:20-40`), when `ai().get_alife() && ai().alife().mp_client_mode()` is true, **replace** the existing entry with the new object rather than warn-and-drop. Also zero the evicted object's `m_story_id` to `INVALID_STORY_ID` so its future `unregister_object` does not clear the slot. This is Strategy C1 in §6.

**Accessor path from `alife_story_registry.cpp`:** `ai().alife().mp_client_mode()` — from `alife_update_manager.h:48`. Include `alife_update_manager.h` and `ai_space.h` (both likely already in the TU). Confirmed accessor pattern is used elsewhere post-patch.

### 2.5 Sibling uniqueness registries (the whack-a-mole horizon)

| Registry | Key | Collision | File:line |
|---|---|---|---|
| `CALifeStoryRegistry` | `_STORY_ID` | `R_ASSERT4` (CVar-gated) or `Msg`+drop | `alife_story_registry.cpp:20-40` |
| `CALifeObjectRegistry` | `_OBJECT_ID` | `THROW2` (debug) / silent double-insert (release) | `alife_object_registry_inline.h:11-22` |
| `CALifeSmartTerrainRegistry` | `OBJECT_ID` of smart zone | `VERIFY` (debug) / silent (release) | `alife_smart_terrain_registry.cpp:17-26` |
| `CALifeGroupRegistry` | `OBJECT_ID` of online/offline group | `VERIFY` (debug) / silent (release) | `alife_group_registry.cpp:17-26` |
| `CALifeSpawnRegistry` | `_SPAWN_STORY_ID → _SPAWN_ID` | Read-only lookup, no runtime add | `alife_spawn_registry_inline.h:50` |
| `Level().Objects` | net `OBJECT_ID` | `Msg`+`return false` (clean abort) | `GameObject.cpp:317-324` |
| Config parser for story_ids | shared_str | `R_ASSERT3` at load | `alife_simulator_script.cpp:111` |
| DLTX section registry | `[section]` | `Debug.fatal` unless `!` override | `Xr_ini.cpp:377` |

**Key observation:** `OBJECT_ID`-keyed registries cannot collide at runtime on the client because IDs are allocated locally by `alife():create()`. The at-risk class is **semantic-key registries**: engine `story_id` + the **Lua parallel `story_id` registry** (§2.1) + possibly `SPAWN_STORY_ID` (unconfirmed live behavior). Strategy C1 alone covers the engine side but not the Lua side; Strategy C2 covers both by never triggering either.

---

## 3. Native A-Life init sequence (Track 2)

### 3.1 Alife population pipeline

Call chain (save-load branch):

```
game_sv_Single::load_game                                 game_sv_single.cpp:250-257
  → CALifeUpdateManager::load_game                        alife_update_manager.cpp:316-335
  → CALifeUpdateManager::load                             alife_update_manager.cpp:281-307
  → CALifeStorageManager::load(save_name)                 alife_storage_manager.cpp:169-232
  → CALifeStorageManager::load(buffer, ..., file_name)    alife_storage_manager.cpp:126-167
      spawns().load(source, file_name)                    (alife_spawn_registry.cpp:54-79)
      objects().load(source)                              deserialize persisted CSE_*
      for obj in objects: register_object(obj, false)     alife_storage_manager.cpp:153
      for obj in objects: obj->on_register()              alife_storage_manager.cpp:160-161
```

New-game branch: `CALifeUpdateManager::new_game` (`alife_update_manager.cpp:251-279`) → `spawns().load` + `spawn_new_objects()` → `CALifeSurgeManager::spawn_new_objects` (`alife_surge_manager.cpp:64-70`) → `fill_new_spawns` / `spawn_new_spawns` → `create(object, spawn, spawn_id)` per record (`alife_simulator_base.cpp:187-234`), which calls `register_object(i, true)` at line 211 and `on_register()` at line 269-272.

Both branches funnel through **`CALifeSimulatorBase::register_object()`** — `alife_simulator_base2.cpp:23-56`. That function writes to object/graph/scheduled/story_id/smart_terrain/group registries.

### 3.2 Hypothesis check: is initial population gated by `mp_client_mode`?

**CONFIRMED — hypothesis is correct. Initial population is NOT gated.**

Evidence:

- The existing engine patch places `m_mp_client_mode` guards only in `CALifeUpdateManager::update` and `CALifeUpdateManager::shedule_Update` (`alife_update_manager.cpp:114-119, 121-146`, per `alife_update_manager.cpp.patch`). These are the per-frame simulator ticks, not the load path.
- `CALifeStorageManager::load` (both overloads), `CALifeUpdateManager::load`, `CALifeUpdateManager::new_game`, `CALifeSurgeManager::spawn_new_objects`, and `CALifeSimulatorBase::register_object` do **not** read `m_mp_client_mode` anywhere.
- `CALifeUpdateManager` constructor initializes `m_mp_client_mode = false` (`alife_update_manager.cpp:74`). There is no pre-ctor path to set it true.
- Direct grep verification: `alife_storage_manager.cpp:153` contains `register_object((*I).second, false);` inside `CALifeStorageManager::load`, which runs during level load. No guard precedes it.

`alife():set_mp_client_mode(true)` runs in `mp_activate_client_mode` (`mp_core.script:132-134`), which fires on GNS `EVENT_CONNECTED` — several frames *after* the user clicks Connect, which itself happens after the level is fully loaded. The flag exists to silence future ticks, not to scrub the existing world.

### 3.3 `mp_activate_client_mode` timing relative to level load

See §1 for the full timeline. The sequence is:

1. Engine populates A-Life from `all.spawn` (alife_storage_manager.cpp:126-167).
2. `on_game_start` runs (Lua) — we register callbacks but cannot intercept past events.
3. User loads, plays for arbitrary time in singleplayer.
4. User hits Connect. `EVENT_CONNECTED` eventually arrives.
5. `set_mp_client_mode(true)` fires.

**Conclusion:** Under the current connect-from-F10 model, the flag can never be set before `all.spawn` populates.

### 3.4 Earlier hook points (if any)

- `CLevel::OnAlifeSimulatorLoaded` (`Level.cpp:1777-1782`) — fires AFTER `CALifeStorageManager::load`. Too late.
- Alundaio's `ENGINE_LUA_ALIFE_STORAGE_MANAGER_CALLBACKS` fires `alife_storage_manager.CALifeStorageManager_load(file_name)` inside the load (`alife_storage_manager.cpp:129-133`) — usable as a "we are loading" signal but `spawns().load` + register loop runs after it unless we patch.
- **`user.ltx` cmdline / config flag read in `CALifeUpdateManager` constructor** (`alife_update_manager.cpp:59-75`): add a small patch that reads a persistent `mp_client_boot = 1` flag and initializes `m_mp_client_mode` accordingly. This runs before any population path — the only pre-load Lua-inaccessible hook point.
- No Lua callback can influence the flag in time. `axr_main.on_game_start()` is the earliest Lua hook and it already runs too late.

### 3.5 The universal spawn funnel

`CALifeSimulatorBase::register_object(CSE_ALifeDynamicObject*, bool add_object)` — `alife_simulator_base2.cpp:23-56` — is the single choke point. Everything goes through it:

- `CALifeStorageManager::load` loop (alife_storage_manager.cpp:153) — load-time.
- `CALifeSurgeManager::spawn_new_spawns` → `create(...)` (alife_simulator_base.cpp:211) — new-game / surge.
- Lua `alife():create(section, pos, lvi, gvi)` → `CALifeSimulatorBase::spawn_item` (alife_simulator_base.cpp:137-138).
- Variant `create(CSE_ALifeGroupAbstract*, CSE_ALifeDynamicObject*)` (line 181).
- Variant `create(CSE_ALifeObject*)` (lines 262, 266).

Gating `register_object` directly on `m_mp_client_mode` would block host-driven sync creates too. A safe gate needs a two-state flag: "suppress native population" vs "accept sync creates". Track 5 Strategy B's cleanest gate is at `CALifeStorageManager::load(buffer,...)` and `CALifeUpdateManager::new_game(save_name)` — the two actual load entry points — leaving `register_object` alone so sync-driven `alife():create()` still works.

### 3.6 Lua observability during initial population

- `CSE_ALifeDynamicObject::on_register()` (`alife_dynamic_object.cpp:29-44`) calls `_G.CSE_ALifeDynamicObject_on_register(id)` functor for every registered dynamic object. Fires during the post-registration pass at `alife_storage_manager.cpp:160-161` for every entity loaded from `all.spawn`. **Defining this functor in Lua gives us a direct observable for native population** — a useful diagnostic.
- `server_entity_on_register` (the Lua-land callback our sync uses) does NOT fire during `all.spawn` load for generic entities. It fires only for script-class subclasses (sim_squad_scripted, smart_terrain, bind_* binders) via luabind virtual dispatch.

### 3.7 Open questions

1. Is `_G.CSE_ALifeDynamicObject_on_register` resolvable *at load time*? The script engine is alive by `CAI_Space` init (before CALifeSimulator ctor), but the functor lookup succeeds only if a script assigned `_G.x = ...` at top-level, not inside `on_game_start`. Worth testing.
2. Is there `on_before_register` hook worth hijacking? The engine calls `CSE_ALifeDynamicObject::on_before_register` (`alife_simulator_base2.cpp:25`) but the default is a no-op with no Lua surface. Virtual subclasses could override.

---

## 4. Sync broadcast catalog (Track 3)

### 4.1 Messages the host sends

| MSG | Code | Channel | Rate | Site | Payload |
|---|---|---|---|---|---|
| ENTITY_SPAWN | ES | reliable | event-driven + 50/frame stream | `mp_host_events.script:267` / `:535` | `id, section, clsid, pos_x/y/z, lvid, gvid, parent_id?` |
| ENTITY_DESPAWN | ER | reliable | event-driven | `:279-281` | `id` |
| ENTITY_DEATH | ED | reliable | event-driven | `:310` | `id, killer_id, pos_x/y/z` |
| WEATHER_SYNC | WS | reliable | ~5 s tick | `:437, :545` | `preset` |
| TIME_SYNC | TS | reliable | ~5 s tick | `:442, :548` | `hours, mins, factor` |
| FULL_STATE | FS | reliable | per-connection | `:570` | `entity_count` |
| LEVEL_CHANGE | LC | reliable | on transition | `:483` | `level` |
| ENTITY_POS | EP | unreliable | 20 Hz / 100 round-robin | `:399` | `id, x, y, z, h` × N |
| PLAYER_POS | PP | unreliable | 20 Hz | `:411, :654` | `id, x, y, z, h, bs, mt, seq` × N |

Not sent from host: `SQUAD_ASSIGN`, `INVENTORY_CHANGE`, `PLAYER_EQUIP`, `PLAYER_STATS` (handlers exist, no emitter).

### 4.2 ENTITY_SPAWN trigger conditions

`mp_host_events.on_entity_register(se_obj, source_tag)` at `mp_host_events.script:210-268`:

1. Puppet guard (`:217-220`).
2. `source_tag` filter (`:224-228`): skips `sim_squad_scripted`, `se_smart_terrain`, `sim_squad_warfare`. This is the ZCP/Warfare class-override filter — it removes smart_terrains and script-squad instances from broadcast entirely. **Smart_terrains therefore do NOT collide** on the client side (§5.3 confirms this excludes ~300-500 entities of deterministic-collision).
3. Level match (`:230-243`): reject entities not on the host's current level via `game_graph():vertex(gvid):level_id()` comparison.
4. Client-count gate (`:249`): return if no clients.
5. Broadcast (`:251-267`).

`build_entity_registry()` (`:153-204`) runs once at `mp_host()`. Does a 0..65534 scan with level-match filter. **Does NOT broadcast** — silently populates `_tracked_ids`. Broadcasts only happen from step 5 onward as new registrations fire.

### 4.3 ENTITY_SPAWN payload contents

Serialization (`mp_protocol.script:47-58`): key=val pairs joined by `|`. No whitelist; whatever the host writes goes on the wire.

Host writes (`mp_host_events.script:251-265`, `:522-534`): `id`, `section`, `clsid`, `pos_x/y/z`, `lvid`, `gvid`, `parent_id` (if ≠ 65535). 

**`story_id` is NEVER sent.** The host does not read `se_obj.m_story_id` and does not include it in the payload. The client therefore cannot tell, from the wire, whether an incoming spawn has a fixed story_id or not. **This is a critical gap for Strategy C2** — requires a small protocol extension (add `story_id` field to ENTITY_SPAWN).

### 4.4 Client apply flow

`mp_client_state.on_entity_spawn(data)` (`mp_client_state.script:159-170`) queues if in CLEANING/IDLE, else calls `do_entity_spawn_inner(data)` (`:180-238`):

1. If mapping already exists → refresh `_network_entities`, return.
2. Build pending-spawn key.
3. Call `mp_alife_guard.internal_create(sim, section, pos, lvid, gvid [, parent_id])`. **No `story_id` argument** — `alife():create()` binding does not accept one; the engine derives it from the section's `.ltx`. If the section declares `$story_id = ah_sarik_squad`, the engine's `CALifeStoryRegistry::add` is called with that id. Collision → §2.3.

### 4.5 Full state streaming — scope

`send_full_state(conn_id)` (`:561-587`): deep-copy `_tracked_ids` → per-connection queue; `tick_full_state` (`:591-598`) streams at 50 entities/frame, each via ENTITY_SPAWN with full payload. Closes with WEATHER_SYNC + TIME_SYNC.

`_tracked_entities` (from §4.2 step 3 enumeration) contains **every** alife object on the host's current level that passes the level-match filter — including all `all.spawn`-sourced entities. The code has **no origin tag**: runtime-spawned and load-time-spawned are indistinguishable. For Joe connecting to Jonah's session, FULL_STATE is essentially a replay of Jonah's native alife.

### 4.6 Other fixed-identity references

- `LEVEL_CHANGE` carries only a level name string — no entity/squad/smart refs.
- `ENTITY_DEATH` has `id` + `killer_id`, both resolved via `resolve_id` (falls back to "dead with no killer" on unresolved).
- `SQUAD_ASSIGN` handler exists client-side but no host code emits it — currently dead.
- `ENTITY_DESPAWN`, `ENTITY_POS`, `PLAYER_POS`: numeric IDs only.

**Only `ENTITY_SPAWN` carries fixed-identity implications**, via the `section` field resolving to a config that specifies a story_id.

### 4.7 Open questions

1. What `source_tag` does `smr_pop.script` pass? If it's not in the three-string filter, ZCP runtime mutant spawns pass through and are broadcast (correct behavior, but confirm).
2. `clsid` is on the wire but has no consumer in `mp_client_state` — dead field?
3. Host-native ENTITY_SPAWN for offline-on-host entities: `alife():create()` on an offline gvid — does the engine accept that without warning? (Most offline-alife entities move through `game_sv_Single::OnCreate` when they come online on host; when host streams them to client, client creates them from scratch — engine probably fine, but untested.)

---

## 5. Fixed-identity collision catalog (Track 4)

### 5.1 story_ids

- **Primary source:** `Stalker_GAMMA\G.A.M.M.A\modpack_addons\197- New Storylines (DLTX minimodpack) - Demonized\gamedata\configs\mod_system_storylines.ltx` — 99 explicit `story_id = ...` assignments. Duplicated in `...Quests Rebalance\gamedata\configs\mod_system_storylines.ltx`.
- **Engine enum source:** `game_story_ids.ltx` / `mod_system.ltx` (in C:\GAMMA runtime, not in source tree) — read by engine at startup (`xrServer_Objects_ALife.cpp:158`, section `"story_ids"`) and exposed as `story_ids._story_ids` luabind enum.
- **Engine also reads `"spawn_story_ids"`** (`xrServer_Objects_ALife.cpp:170`) — a parallel id set for spawn records.
- **Ballpark totals:** Additional-Storylines overlay = 99; vanilla Anomaly baseline estimated 400–600. **Total ≈ 500–700 story_ids per GAMMA session**, but these are WORLDWIDE. Per-level, only 50–150 are live in alife at any given time.
- **Sample:** `ah_sarik_squad`, `ah_sarik`, `ah_bol_kovalev_squad`, `ah_yan_markov`, `dragun_squad`, `brodyaga`, `strelok_pda_item`, `monolith_pri_b36_smart_terrain_defense_squad`, `jup_b8_isg_attack_squad`, `pri_a15_ht_sbu_enforcer_1`.

### 5.2 Unique NPCs

Traders/quest NPCs pinned via `character_profile = X` + `story_id = X` in squad_descr or storylines. Example (`mod_system_storylines.ltx:1508-1513`):
```
[ah_sarik]:stalker
$spawn = respawn\ah_sarik
character_profile = ah_sarik
story_id = ah_sarik
```
Vanilla GAMMA includes ~20–30 trader NPCs + 40–60 storyline characters ≈ **60–90 total**, all subset of §5.1.

### 5.3 Smart_terrains

- 20–50 per level, 300–500 worldwide.
- **Filtered out of broadcast** via `source_tag == "se_smart_terrain"` at `mp_host_events.script:225`. **Not a collision surface** as long as the filter holds.

### 5.4 Squads

- Generic runtime squad templates (`squad_descr_default_mutants.ltx` etc.) — no `story_id` (grep confirms). Runtime-instantiated with engine IDs — only collide on `OBJECT_ID`, which ID remapping handles. **Not a problem.**
- Named story squads — ~60% of the 99 additional story_ids + similar fraction of vanilla. **~50-60 named squads with story_id worldwide**, ~10-20 live per level.

### 5.5 Zones / space_restrictors — confirmed no collision

Grep confirms: `**\Artefacts Reinvention\gamedata\configs\scripts\**\anomal*.ltx` has **zero** `story_id` hits. Matches the log: thousands of zones map successfully. The engine tolerates duplicate zone names at runtime — `space_restrictor` / `zone_mine_*` instances come from `all.spawn` with numeric IDs only.

### 5.6 Unique quest items

GAMMA does not use a `story_item = true` flag (0 hits). Quest items are story_id-pinned sections. ~15-25 worldwide: `ah_gramota`, `strelok_pda_item`, various `*_pda_item`, `decoder`, `guitar_a`, `af_oasis_heart`, etc. Subset of §5.1.

### 5.7 Blast radius estimate

Per-level (representative — Escape, Garbage, Pripyat-ish):
- Unique-identity entities (story_id set, excluding filtered smart_terrains): **~50–150**.
- Total entities (all alife on level): **~2,000–5,000** (thousands of zones + space_restrictors + squad members + items).
- **Ratio: 1–5%.** Filtering fixed-identity entities removes only 1–5% of the sync stream; 95–99% of the sync still flows. Strategy A is strongly viable. Strategy C2 is equivalently surgical (~100 LoC).

### 5.8 Open questions

1. Can't inspect base `all.spawn` (binary) for `space_restrictor` entries that pin story_ids — possible but unlikely edge case.
2. Master vanilla `game_story_ids.ltx` not in source tree — need to read `C:\GAMMA\` runtime for exact baseline count.
3. Are any scripted-spawned story squads created at runtime (not from `all.spawn`)? Some storyline scripts do spawn squads; those would STILL collide on broadcast because they still register in the same story registry.

---

## 6. Strategy analysis and recommendation (Track 5)

### 6.1 Strategy A — Broadcast filter (host-side)

**Description.** Host refuses to broadcast fixed-identity entities. Client keeps native copies. Host streams runtime spawns + all death/despawn/position events.

**Plug-in.** Extend the existing `source_tag` filter at `mp_host_events.script:224-228` and `mp_core.script:221` with `is_fixed_identity(se_obj)` — e.g., `se_obj.m_story_id ~= nil and se_obj.m_story_id ~= INVALID_STORY_ID`. Apply at 3 sites: `on_entity_register`, `build_entity_registry` (the 0-65534 scan), and `_tick_full_state_connection` (so FULL_STATE also excludes).

**Gaps.**
- **ENTITY_DEATH / ENTITY_POS routing** for story NPCs breaks without ID mapping. Would need a companion `ENTITY_MAP` message (host enumerates its fixed-identity entities by `story_id`; client resolves each to its own native ID via `alife():story_object(story_id)`).
- **State divergence.** Native copies start with ltx-default state; host state drifts with time. Acceptable for Phase 0, ugly for Phase 3.
- **Mod delta between players** — if Joe and Jonah don't have identical story-id sets, silent mismatches.

**Scope:** ~80-150 LoC across `mp_host_events.script` + `mp_client_state.script`; optional protocol extension `MSG.EM`. Zero engine patches. Highly reversible.

**Test plan:** (1) No story_id warnings at connect. (2) Killing story NPC on host → client sees death. (3) Drop item → client sees pickup. (4) LEVEL_CHANGE works. (5) Inventory/state sanity at 5 min. (6) 10-min offline-drift check.

### 6.2 Strategy B — Suppress client native A-Life init (engine patch)

**Description.** Gate `CALifeStorageManager::load(buffer,...)` and `CALifeUpdateManager::new_game(save_name)` on `m_mp_client_mode`. Client arrives empty; host's stream populates.

**Temporal ordering problem.** Flag must be set before load. Options:
- **B1** Pre-level main-menu "MP Client" mode → flag persists across level init.
- **B2** `user.ltx` flag `mp_client_boot = 1` read in `CALifeUpdateManager` constructor (alife_update_manager.cpp:59-75). Clunky user experience.
- **B3** Connect-first flow before loading a save.

**Risks.**
- 400+ mods' `on_game_start` handlers read `level.object_by_id(story_npc_id)` and friends at load time. With empty alife, nil propagates everywhere.
- Smart_terrain init, trader setup, task_manager, axr_companions — all break without their expected NPCs.
- Empty-alife boot path is untested engine territory; surprise crashes likely.
- Patch 0008's soft-fail absorbs some of this, but blast radius is large.

**Scope:** 1-2 engine patches, moderate Lua rewiring. Huge test matrix.

**Reversibility:** Easy to revert the engine gate, harder to unwind connection-flow changes.

### 6.3 Strategy C — hybrid / alternatives

**C1 — Engine registry tolerance.** Patch `CALifeStoryRegistry::add` to replace-on-collision when `mp_client_mode` (see §2.4). 10-20 LoC engine-side. Covers engine registry only — does **not** silence the Lua-side parallel registry (`~ Story Objects | Multiple objects trying...`) and does not prevent the downstream Lua-land deref. Useful as **defense-in-depth** but insufficient alone.

**C2 — Client-side pre-apply de-dup (RECOMMENDED, with A as follow-up).** Before `do_entity_spawn_inner` calls `internal_create`, check if a native entity with matching `(story_id)` already exists via `alife():story_object(story_id)`. If yes, map host_id → existing local_id and skip the create. Host must include `story_id` in ENTITY_SPAWN payload (4.3 gap — add 1 field). Sketch:

```lua
-- mp_host_events.script, in the payload build (both :251 and :522):
data.story_id = se_obj.m_story_id  -- numeric or nil

-- mp_client_state.script, in do_entity_spawn_inner, before line 200:
if data.story_id and data.story_id ~= 0 then
    local existing = sim:story_object(data.story_id)
    if existing then
        map_id(host_id, existing.id)
        _network_entities[host_id] = data
        flush_pending_positions(host_id)
        return
    end
end
-- fall through to normal create path for non-story entities
```

**Properties:**
- **No engine patch.** Pure Lua.
- **Eliminates collision at root** — no duplicate create → no registry insertion → no warning (engine OR Lua).
- **Position sync works automatically** — host's EP messages resolve via map to the native entity; host is authoritative.
- **Death events apply cleanly** — ED resolves through the same map.
- **LEVEL_CHANGE** already wipes the map; de-dup re-runs per level naturally.
- **Protocol backward-compatible** — `story_id` field in ENTITY_SPAWN is additive; old clients ignore it.

**Failure modes:**
- State (health/inventory/scheme state) starts as client-native initial, not host-current. Position will snap via next EP. Inventory mismatch until Phase 3.
- If host killed a story NPC pre-connect, its ENTITY_SPAWN won't appear in FULL_STATE (released on host) → client's native copy is alive while host expects dead. Needs a `dead_story_ids` list in FULL_STATE header. Not urgent for Phase 0.
- Ambiguous story_id in modded data (possible but unverified).

**Scope:** ~60-100 LoC. Touches only `mp_client_state.script` (de-dup function + call site) and `mp_host_events.script` (serialize story_id in two places). Zero engine patches.

**C3 — Host strips story_id / renames section.** Rejected. Section is load-bearing for AI/scheme/inventory configs; stripping breaks more than it fixes.

### 6.4 Decision tree (now resolvable with Tracks 1-4 in hand)

- Track 2 CONFIRMS hypothesis → all strategies are live.
- Track 1 shows story_id is the only engine collision registry active at runtime on the client, but the **Lua-side parallel registry** also warns independently — so C1 alone is insufficient. C2 avoids both by not creating the duplicate at all.
- Track 4 shows blast radius is small (1-5%) → both A and C2 preserve >95% of sync utility.
- Track 3 shows `story_id` is NOT currently on the wire → C2 needs a small protocol extension (trivial).
- Track 4 shows many mod scripts read native A-Life at load (estimated, based on 400+ GAMMA mods inventory) → Strategy B's blast radius is large. **B is contraindicated.**

### 6.5 Recommendation

**Primary: Strategy C2** (Lua de-dup + `story_id` in ENTITY_SPAWN payload).

**Layer: Strategy A-lite** follow-up — once C2 works, add a host-side filter so fixed-identity entities aren't broadcast at all (saves bandwidth, simplifies FULL_STATE). Order matters: C2 first (eliminates crash), A second (optimization).

**Defense-in-depth:** Add `execute("duplicate_story_id_crash 0")` to client bootstrap as a belt-and-suspenders hardening. Run only on client, via `mp_activate_client_mode`. Cost: one `console:execute` call. Value: even if C2 misses a case, the engine won't fatal — just warn.

**Reject:** Strategy B (too invasive for the benefit; blast radius across 400+ mods unacceptable). Strategy C1 alone (doesn't cover Lua-side registry, whack-a-mole follow-up if new registries surface). Strategy C3 (breaks semantics).

### 6.6 Open questions (strategy layer)

1. What is Joe's current `duplicate_story_id_crash` CVar value? If it's 1, crash is immediate assert; if 0, crash is downstream Lua deref. Changes the urgency (but not the recommendation — C2 covers both).
2. Is `alife():story_object(story_id_number)` safe to call with an ID the client has never registered? (Per §2.2 it returns 0 on miss — safe.)
3. How does C2 interact with the client CLEANING phase? CLEANING releases native entities before SYNCING creates new ones. If a story NPC is released in CLEANING and then the host's ENTITY_SPAWN arrives, `story_object` returns nil and C2 falls through to the normal create path — which then registers fresh, no collision. **This is actually fine and means C2 works correctly with the existing state machine.** Worth confirming during testing.
4. What happens if two host entities claim the same story_id via buggy config? C2's `story_object` lookup returns whichever was registered last; second lookup returns the first (still registered). Either case is safe — collision is avoided, second host ID maps to same local as first.

---

## 7. Open questions requiring live data

1. ~~**`duplicate_story_id_crash` value on Joe's install.**~~ **RESOLVED:** `C:\ANOMALY\appdata\user.ltx:96` is `duplicate_story_id_crash 1`. Crash is the immediate `R_ASSERT4`. (No hits for the CVar in `C:\GAMMA\mods\**\*.ltx` so no mod overrides it at runtime.)
2. **RVA 0x13BCF8 symbolic resolution.** Needs PDB for `AnomalyDX11AVX.exe`. Not blocking — both plausible paths (§2.3) lead to the same fix.
3. **Lua-side "Story Objects" registry source.** Grep `C:\GAMMA\gamedata\scripts\**\*.script` for the literal `Multiple objects trying to use same story_id`. Probably `_g.script` or `bind_story_object.script`. Confirms whether C2 also silences the Lua warning (expected: yes, because C2 avoids the duplicate alife:create entirely, which means whatever Lua `on_register` callback drives the Lua registry never sees the duplicate).
4. **`_G.CSE_ALifeDynamicObject_on_register` availability at load time.** Define `_G.CSE_ALifeDynamicObject_on_register = function(id) mp_load_count = (mp_load_count or 0) + 1 end` at top-level of `mp_core.script`; after load, log `mp_load_count`. Validates the observability hook and gives a precise native-population count for any session.
5. **Master vanilla story_id count.** Read `C:\GAMMA\gamedata\configs\game_story_ids.ltx` or `mod_system.ltx` for the full token list; firms up §5.1 estimate.
6. **Offline A-Life drift.** After 10 min of gameplay, compare host's story NPC positions with client's native story NPC positions (those not receiving EP updates because host filters them or we do). Relevant for Phase 3+ planning.
7. **`smr_pop.script` source_tag.** Read `C:\GAMMA\gamedata\scripts\smr_pop.script` to confirm what tag it passes to `SendScriptCallback("server_entity_on_register", ...)`. Determines whether runtime mutant spawns currently pass the filter.
8. **ZCP 1.4 `smr_handle_spawn` client gate.** Already patched per `gamma-mp-release 17c8a26`. Confirm the gate is active on Joe's install.
9. **Does FULL_STATE include offline-on-host entities?** If host's build_entity_registry enumerates offline alife, does `alife():create()` on the client accept offline gvids cleanly? (Should — engine spawns offline entities routinely during simulation — but untested under sync.)

---

## 8. Proposed next patch

**Scope:** Strategy C2 (client-side story_id pre-apply de-dup). One commit. No engine changes.

### File 1: `gamma-mp/lua-sync/mp_host_events.script`

Two sites that build the ENTITY_SPAWN payload need a `story_id` field.

**Site 1: `on_entity_register`, around line 251-265** (the event-driven broadcast):
```lua
-- existing field builds: id, section, clsid, pos_x/y/z, lvid, gvid, (parent_id)
-- ADD:
local sid = se_obj.m_story_id
if sid and sid ~= 65535 and sid ~= 0xFFFFFFFF then  -- INVALID_STORY_ID is u32 max
    data.story_id = sid
end
```

**Site 2: `_tick_full_state_connection`, around line 522-534** (the streaming replay):
same addition to the per-entity `data` table.

(The constant `INVALID_STORY_ID` value: need to verify at write-time via `alife_space.h` — engine uses a u32 sentinel. Guard with `sid and sid > 0 and sid < 65535` as a conservative range check; story_ids in GAMMA are ~16-bit numeric indices from the enum.)

### File 2: `gamma-mp/lua-sync/mp_client_state.script`

**Add function** (top of file, near `resolve_id`):
```lua
local function try_match_existing_by_story_id(sim, story_id)
    if not story_id or story_id == 0 then return nil end
    local se = sim:story_object(story_id)
    if se and se.id then return se.id end
    return nil
end
```

**Modify `do_entity_spawn_inner`** (around line 180-238), insert before the pending-spawn-key block at ~line 200:
```lua
-- Pre-apply de-dup for story-pinned entities:
-- the client's native alife already contains this entity from all.spawn.
-- Map the host ID to the existing local entity instead of creating a duplicate.
local existing_local = try_match_existing_by_story_id(sim, data.story_id)
if existing_local then
    map_id(host_id, existing_local)
    _network_entities[host_id] = data
    if _pending_positions[host_id] then
        local p = _pending_positions[host_id]
        apply_entity_position(host_id, p.x, p.y, p.z, p.h)
        _pending_positions[host_id] = nil
    end
    return
end
-- fall through to normal create path
```

**Defense-in-depth** (in `mp_core.mp_activate_client_mode`, after `set_mp_client_mode(true)` at `mp_core.script:134`):
```lua
-- Harden against any story_id collision we fail to dedup:
-- makes engine's CALifeStoryRegistry::add warn instead of assert.
get_console():execute("duplicate_story_id_crash 0")
```

### Verification steps before ship

1. Deploy + smoke-test: Joe connects to Jonah, confirm no `~ Story Objects` warning and no crash.
2. Walk to `ah_sarik` location on Jonah's side, confirm Joe sees sarik at host-driven position (via EP).
3. Kill sarik on host, confirm Joe's copy dies.
4. Level transition works.
5. 10-minute stability run.

### Patch this document does NOT prescribe (left for follow-up)

- **Strategy A filter** for bandwidth. Add after C2 is stable.
- **`dead_story_ids` in FULL_STATE header** for host-killed pre-connect story NPCs.
- **ENTITY_SPAWN delta**: if a story NPC was moved on host before connect, its client-native ltx-default position will be stale until first EP. Acceptable for Phase 0.

---

*Synthesis validated against direct engine grep: `duplicate_story_id_crash` CVar at `console_commands.cpp:3040`; `register_object((*I).second, false)` at `alife_storage_manager.cpp:153` (confirming unguarded native population); `m_story_id` Lua-readable at `xrServer_Objects_ALife_script.cpp:58`; `alife():story_object(id)` Lua-accessible at `alife_simulator_script.cpp:80,607`; `"Multiple objects trying to use same story_id"` text NOT in engine source → Lua-sourced.*
