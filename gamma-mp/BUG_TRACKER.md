# GAMMA MP Bug Tracker

Last updated: 2026-04-15

## Status Key
- FIXED: Code change applied, needs deploy+test
- CONFIRMED_SAFE: Investigated, not a bug
- OPEN: Identified, not yet fixed
- IN_PROGRESS: Currently being worked on

---

## Bug #1: Async Connection State (FIXED)
**Severity:** CRITICAL
**File:** `lua-sync/mp_core.script`
**Problem:** A-Life suppressed and saves blocked immediately on `mp_connect()`, before connection confirmed. On rejection, cleanup was incomplete — `_is_client = false` but A-Life stayed suppressed.
**Fix:** Added `_is_connecting` intermediate state. All game state changes deferred to `mp_activate_client_mode()` which only fires on `EVENT_CONNECTED`. New `mp_on_connect_failed()` for lightweight rejection cleanup.
**Commit:** `fix: async connection state management`

## Bug #2: Double World State (FIXED)
**Severity:** CRITICAL
**File:** `lua-sync/mp_client_state.script`
**Problem:** Client's save-loaded entities coexisted with host's network entities. Two copies of every NPC.
**Fix:** Added CLEANING->SYNCING->ACTIVE state machine. `on_full_state()` collects all existing entity IDs (0-65534 scan), batched deletion at 50/frame, queued spawn processing at 20/frame.

## Bug #3: Buffer Overflow on Full State (FIXED)
**Severity:** MEDIUM
**File:** `lua-sync/mp_host_events.script` lines 310-361
**Problem:** `send_full_state()` sends individual `ENTITY_SPAWN` messages per entity via reliable channel with no per-frame budget. With 2000+ tracked entities, all messages sent in one frame. GNS_MAX_MESSAGE_SIZE is 64KB per message (each spawn ~200 bytes, so individual messages are fine), but the GNS internal send buffer could overflow.
**Fix:** Stateful continuation with per-connection cursor. `send_full_state()` sends the FULL_STATE header immediately (to trigger client CLEANING state), snapshots `_tracked_ids` into a stable per-connection array, and queues the work. `tick_full_state()` drives 50 entities/frame per connection from `mp_core.mp_update()` every frame (no rate limit). Environment state (weather/time) is sent after the last entity batch. `cancel_full_state(conn_id)` cleans up if a client disconnects mid-stream. With 2000 entities at 50/frame: ~40 frames (~0.67s at 60fps) to complete.

## Bug #4: ID Mapping Key Collisions (FIXED)
**Severity:** HIGH
**File:** `lua-sync/mp_client_state.script`
**Problem:** Pending spawn key `section_%.0f_%.0f_%.0f` rounded positions to integers. Two entities of same section at nearby positions collided — second overwrote first, orphaning the first entity forever.
**Fix:** Changed to `%.4f` precision (matches float32 exactly). Changed storage from single host_id to FIFO list per key (`table.remove(list, 1)`) for same-position same-section edge case.

## Bug #5: Create Synchronicity (CONFIRMED_SAFE)
**Severity:** N/A
**Problem:** Concern that `alife():create()` might fire `server_entity_on_register` callback asynchronously, breaking FIFO ordering.
**Finding:** Engine fires callback SYNCHRONOUSLY. Call chain: `create()` -> `CALifeSimulatorBase::spawn_item()` -> `register_object()` -> `CSE_ALifeDynamicObject::on_register()` -> direct `luabind::functor` call. No queueing. FIFO guaranteed. Only exception: during save load, `can_register_objects()` is false and callbacks batch — irrelevant to MP runtime.

## Bug #6: Level Mismatch (FIXED)
**Severity:** HIGH
**File:** `lua-sync/mp_client_state.script` lines 296-306
**Problem:** Host on Level A sends entities with Level A vertex IDs. Client on Level B tries to teleport offline entities using stale `m_level_vertex_id`/`m_game_vertex_id` from Level A. `level.object_by_id()` only returns online entities on current level.
**Fix:** In `apply_entity_position()` offline fallback, compare `game_graph():vertex(gvid):level_id()` against the actor's level ID before calling `teleport_object`. Return early if they differ. Falls through to original behavior if `game_graph()` or `db.actor` are unavailable.

## Bug #7: Death Double-Fire (FIXED)
**Severity:** MEDIUM (theoretical)
**File:** `lua-sync/mp_client_state.script` lines 189-231, `lua-sync/mp_host_events.script` lines 182-204
**Problem:** When client calls `kill_entity()` to apply a host death event, it MIGHT re-fire `npc_on_death_callback` locally. If mp_host_events is registered on client (it shouldn't be), this could echo back.
**Fix:** Added `_applying_remote_death` bool flag in `mp_client_state`. Set true immediately before `kill_entity()`, cleared after. Consolidated the 4-branch kill block into a single call site so the flag window is tight. `mp_host_events.on_npc_death()` checks `mp_client_state.is_applying_remote_death()` at entry and returns immediately if set. Host callbacks still only registered on host — this is defense-in-depth.

## Bug #8: kill_entity API Existence (OPEN)
**Severity:** CRITICAL (if missing)
**File:** `lua-sync/mp_client_state.script` lines 220-227
**Problem:** Code calls `sim:kill_entity(se_obj, killer_se)`. If this API doesn't exist in the engine build, it silently errors or crashes.
**Fix:** Test in-game: `lua: alife():kill_entity`. Add safe wrapper with fallback to `sim:release(se_obj, true)`.

## Bug #9: Position Snapshot Cap (FIXED)
**Severity:** HIGH
**File:** `lua-sync/mp_host_events.script`
**Problem:** `send_snapshots()` caps at 100 entities per frame via `for id, _ in pairs()` + `break`. With 2000+ tracked entities, `pairs()` iteration order is non-deterministic (Lua hash table), so the SAME 100 entities could be sent every frame while others never update.
**Fix:** Added `_tracked_ids` indexed array (maintained via O(1) swap-remove in `track_entity`/`untrack_entity`) and `_snapshot_cursor` that advances each frame. `send_snapshots()` now walks the array starting at the cursor, wrapping around, ensuring all entities get position updates across frames. With 2000 entities at 100/frame, full rotation takes 20 frames (1 second at 20Hz).

## Bug #10: force_set_position API Existence (OPEN)
**Severity:** CRITICAL (if missing)
**File:** `lua-sync/mp_client_state.script` line 284
**Problem:** Code calls `obj:force_set_position(target_pos)`. If this game_object method doesn't exist, online entities never move.
**Fix:** Test in-game: `lua: db.actor.force_set_position`. Add safe wrapper with fallback to `obj:set_position()` or `obj:set_movement_position()`.

## Bug #11: Direct alife() Calls from Mods (OPEN)
**Severity:** CRITICAL
**File:** Systemic — 80+ mod .script files
**Problem:** Mods call `alife():create()` and `alife():release()` directly. On client, these bypass sync: creates produce untracked entities, releases destroy host-synced entities.
**Mitigation (partial):** `_g.script` wrapper with `is_mp_client()` guards blocks the most common paths. But mods that import alife() directly bypass this.
**Full fix:** Intercept at the metatable level — wrap `alife()` return value with a proxy that blocks create/release on client. Requires careful engineering to not break mod introspection.

## Bug #12: Level Transitions (OPEN)
**Severity:** CRITICAL
**File:** `lua-sync/mp_core.script` — no handler exists
**Problem:** When host changes level, client has no idea. Host's entity registry resets, new entities spawn on new level, but client still holds old mappings. Complete desync.
**Fix:** Add `LEVEL_CHANGE` message type. Host broadcasts before transition. Client clears all state, resets to IDLE, waits for new `FULL_STATE` after host finishes loading.

## Bug #13: Message Ordering Race (FIXED)
**Severity:** CRITICAL
**File:** `lua-sync/mp_client_state.script`
**Problem:** UDP position snapshots can arrive before TCP spawn messages. `resolve_id()` returns nil, position silently dropped. Entity spawns at creation position and sits frozen until next position update after mapping exists.
**Fix:** Added `_pending_positions` table. `on_entity_positions()` queues positions for unmapped entities. `on_local_entity_registered()` flushes queued position when mapping is established.

## Bug #14: Weather Sync Gap (OPEN)
**Severity:** MEDIUM
**File:** `lua-sync/mp_host_events.script` lines 281-304
**Problem:** Weather sync sent every 5 seconds via reliable channel. If client connects between syncs, they see wrong weather for up to 5 seconds. Not critical — `send_full_state()` includes weather (line 350).
**Fix:** Increase frequency or send weather in every snapshot. Low priority.

## Bug #15: Time Sync Direction (FIXED)
**Severity:** HIGH
**File:** `lua-sync/mp_client_state.script` lines 348-369
**Problem:** Fallback path (no `set_game_time`) uses `level.change_game_time()` which only goes forward. If host time is behind client, sync fails until host catches up. Primary path uses `level.set_game_time()` (our engine patch) which handles backward via 24h wraparound.
**Fix:** Added 24h wraparound to fallback path: when delta is negative, adds 24 hours so `change_game_time()` advances forward to the correct time. Added startup warning in `mp_core.script` `on_game_start()` if `level.set_game_time` is missing.
