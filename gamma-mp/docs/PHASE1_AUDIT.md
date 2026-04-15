# Phase 1 Audit: Player Visibility — Full Dependency Map

**Date:** 2026-04-15
**Scope:** Engine source (xray-monolith C++), Lua sync layer, GAMMA mod configs
**Purpose:** Map every API, flow, constraint, and risk needed to render remote players in-world

---

## Table of Contents

1. [API Reference](#1-api-reference)
2. [Spawn Flow](#2-spawn-flow)
3. [Update Flow](#3-update-flow)
4. [Animation System](#4-animation-system)
5. [Equipment & Visual Sync](#5-equipment--visual-sync)
6. [Existing MP Infrastructure](#6-existing-mp-infrastructure)
7. [Network Message Flow](#7-network-message-flow)
8. [Level & Distance Constraints](#8-level--distance-constraints)
9. [Collision & Physics](#9-collision--physics)
10. [Death & Damage (Phase 2 Preview)](#10-death--damage-phase-2-preview)
11. [Mod Conflicts](#11-mod-conflicts)
12. [Risk Register](#12-risk-register)
13. [Dependency Graph](#13-dependency-graph)
14. [Recommended Implementation Order](#14-recommended-implementation-order)
15. [Open Questions](#15-open-questions)

---

## 1. API Reference

Every Lua/engine API relevant to spawning and controlling a puppet stalker.

### 1.1 Entity Creation & Lifecycle

| API | Signature | File | Line | Notes |
|-----|-----------|------|------|-------|
| `alife():create()` | `create(section, pos, lvid, gvid)` | `alife_simulator_script.cpp` | 621 | Creates server entity. Fires `server_entity_on_register` **synchronously**. Returns `CSE_ALifeDynamicObject*`. |
| `alife():create()` (with parent) | `create(section, pos, lvid, gvid, parent_id)` | `alife_simulator_script.cpp` | 620 | Creates entity inside another entity's inventory. |
| `alife():release()` | `release(se_obj, true)` | `alife_simulator_script.cpp` | 624-625 | Destroys server entity. Offline = synchronous; online = async via `GE_DESTROY`. |
| `alife():teleport_object()` | `teleport_object(id, gvid, lvid, pos)` | `alife_simulator_script.cpp` | 635 | Moves offline server entity to new position/vertex. |
| `mp_alife_guard.internal_create()` | `internal_create(sim, section, pos, lvid, gvid)` | `mp_alife_guard.script` | 270-278 | Bypasses client-side alife guard. **Use this for puppet spawns.** |
| `mp_alife_guard.internal_release()` | `internal_release(sim, se_obj, true)` | `mp_alife_guard.script` | 283-288 | Bypasses client-side alife guard for despawns. |
| `level.object_by_id()` | `level.object_by_id(id)` -> `CScriptGameObject*` | `level_script.cpp` | (bindings) | Returns game object for online entity, nil for offline. |

### 1.2 Online/Offline Control

| API | Signature | File | Line | Notes |
|-----|-----------|------|------|-------|
| `alife():set_switch_online()` | `set_switch_online(id, bool)` | `alife_simulator_script.cpp` | 608-609 | Sets `flSwitchOnline` flag on server entity. When `true`, entity stays online. |
| `alife():set_switch_offline()` | `set_switch_offline(id, bool)` | `alife_simulator_script.cpp` | 610-611 | Sets `flSwitchOffline` flag. When `false`, entity cannot go offline. |
| `se_obj:can_switch_online()` | getter: `bool`; setter: `(bool)` | `xrServer_Objects_ALife_script.cpp` | 53 | Direct flag access on server entity. |
| `se_obj:can_switch_offline()` | getter: `bool`; setter: `(bool)` | `xrServer_Objects_ALife_script.cpp` | 54 | Direct flag access on server entity. |
| `alife():set_interactive()` | `set_interactive(id, bool)` | `alife_update_manager.cpp` | 351-356 | Controls whether entity participates in A-Life scheduling. |

### 1.3 Position Setting

| API | Signature | File | Line | Notes |
|-----|-----------|------|------|-------|
| `obj:force_set_position()` | `force_set_position(Fvector, bool)` | `script_game_object3.cpp` | 1800 | Direct physics position write. Bypasses collision. `bool` = activate physics shell. **Best for puppet updates.** |
| `obj:set_npc_position()` | `set_npc_position(Fvector)` | `script_game_object2.cpp` | 392 | Moves NPC to position. May include collision correction. |
| `obj:set_actor_position()` | `set_actor_position(pos, skip_collision, keep_speed)` | `script_game_object2.cpp` | 363 | For actor only. Two optional bools. |
| `alife():teleport_object()` | `teleport_object(id, gvid, lvid, pos)` | `alife_update_manager.cpp` | 404 | For offline entities. Requires valid graph/level vertex IDs. |
| `se_obj.position` | read-only `Fvector` | (server entity property) | — | A-Life simulation position. Updated by teleport_object or switch_online. |
| `obj:position()` | returns `Fvector` | `script_game_object_script2.cpp` | 97 | Current rendered world position of online game object. |

### 1.4 Direction & Heading

| API | Signature | File | Line | Notes |
|-----|-----------|------|------|-------|
| `obj:set_desired_direction()` | `set_desired_direction(Fvector*)` or no args | `script_game_object_script2.cpp` | 301-303 | Sets NPC target facing direction. For puppet heading sync. |
| `obj:direction()` | returns `Fvector` | `script_game_object_script2.cpp` | 98 | Current facing direction vector. |
| `obj:get_current_direction()` | returns `Fvector` | `script_game_object_script2.cpp` | 279 | Heading vector getter. |
| `obj:set_actor_direction()` | `(yaw)`, `(yaw,pitch)`, `(yaw,pitch,roll)`, `(Fvector hpb)` | `script_game_object2.cpp` | 411-437 | **Actor camera only** — not body rotation. Not useful for puppets. |

### 1.5 AI Suppression

| API | Signature | File | Line | Notes |
|-----|-----------|------|------|-------|
| `obj:set_mental_state()` | `set_mental_state(EMentalState)` | `script_game_object3.cpp` | 668 | `eMentalStateFree` (1) = relaxed. `eMentalStateDanger` (0) = combat. `eMentalStatePanic` (2) = flee. |
| `obj:set_body_state()` | `set_body_state(EBodyState)` | `script_game_object3.cpp` | 646 | `eBodyStateStand` (1) = standing. `eBodyStateCrouch` (0) = crouched. |
| `obj:set_movement_type()` | `set_movement_type(EMovementType)` | `script_game_object3.cpp` | 655 | `eMovementTypeStand` (2) = stationary. `eMovementTypeWalk` (0). `eMovementTypeRun` (1). |
| `obj:set_desired_position()` | `set_desired_position(Fvector*)` or no args | `script_game_object_script2.cpp` | 298-300 | Sets AI pathfinding target. Call with no args to clear. |
| `obj:invulnerable()` | getter: `bool`; setter: `(bool)` | `script_game_object.cpp` | 1028-1052 | Make puppet ignore damage. **Critical for Phase 1.** |

### 1.6 Visual & Equipment

| API | Signature | File | Line | Notes |
|-----|-----------|------|------|-------|
| `obj:set_visual_name()` | `set_visual_name(string, bool_force)` | `script_game_object2.cpp` | 670-697 | Changes character model. Generates `GE_CHANGE_VISUAL` event. Recalculates bones. **Can change outfit appearance live.** |
| `obj:get_visual_name()` | returns `string` | `script_game_object2.cpp` | 719 | Current visual model path. |
| `obj:item_in_slot()` | `item_in_slot(slot_id)` -> `CScriptGameObject*` or nil | `script_game_object_script2.cpp` | 350 | Read equipped item in slot. Slots: 2=primary weapon, 3=secondary, 7=outfit, 12=helmet. |
| `obj:best_weapon()` | returns `CScriptGameObject*` | `script_game_object_script2.cpp` | 214 | Get prioritized weapon from inventory. |
| `obj:transfer_item()` | `transfer_item(item_obj, recipient_obj)` | `script_game_object_inventory_owner.cpp` | 601-625 | Event-based item transfer (GE_TRADE_SELL/BUY). |
| `obj:IterateInventory()` | `IterateInventory(functor, obj)` | `script_game_object_script3.cpp` | 253 | Iterate all items in inventory. |

### 1.7 Animation

| API | Signature | File | Line | Notes |
|-----|-----------|------|------|-------|
| `obj:play_cycle()` | `play_cycle(anim_name, mix_in)` | `script_game_object2.cpp` | 149-170 | Play looping animation. `mix_in` = blend with current. |
| `obj:add_animation()` | `add_animation(name, hand_usage, use_movement_controller)` | `script_game_object3.cpp` | 389-428 | Queue animation with optional position/rotation offset. |

### 1.8 Enums (Lua Constants)

```
-- Mental States (MonsterSpace::EMentalState)
eMentalStateDanger = 0   -- combat alert
eMentalStateFree   = 1   -- relaxed/idle
eMentalStatePanic  = 2   -- fleeing

-- Body States (MonsterSpace::EBodyState)
eBodyStateCrouch = 0
eBodyStateStand  = 1

-- Movement Types (MonsterSpace::EMovementType)
eMovementTypeWalk  = 0
eMovementTypeRun   = 1
eMovementTypeStand = 2
```

Defined in `ai_monster_space.h` lines 15-34. Lua bindings in `script_animation_action_script.cpp` and `script_movement_action_script.cpp`.

---

## 2. Spawn Flow

Step-by-step creation of a visible puppet stalker from Lua.

### 2.1 Engine Spawn Path (C++)

```
Lua: alife():create("stalker_silent", pos, lvid, gvid)
  │
  ├─> CALifeSimulator__spawn_item()           [alife_simulator_script.cpp:169-173]
  │     calls spawn_item(section, pos, lvid, gvid, -1)
  │
  ├─> CALifeSimulatorBase::create()            [alife_simulator_base.cpp:187-234]
  │     ├─ F_entity_Create(*section)           — instantiate CSE_ALifeHumanStalker
  │     ├─ Spawn_Read/Spawn_Write              — copy template data
  │     ├─ server().PerformIDgen()             — assign unique entity ID
  │     ├─ register_object(entity, true)       — add to A-Life registry
  │     │     └─ fires server_entity_on_register callback (SYNCHRONOUS)
  │     └─ entity->on_spawn()                  — Lua post-spawn hook
  │
  ├─> Distance check: try_switch_online()      [alife_dynamic_object.cpp:133-167]
  │     ├─ if distance_to_actor <= online_distance (405m default)
  │     └─ switch_online(entity)               [alife_switch_manager.cpp:111-120]
  │           ├─ entity.m_bOnline = true
  │           ├─ alife().add_online(entity)    [alife_switch_manager.cpp:50-75]
  │           │     └─ server().Process_spawn() — creates CGameObject with model,
  │           │                                   physics shell, collision, bones
  │           └─ Entity now has a renderable game object
  │
  └─> level.object_by_id(id) now returns non-nil CScriptGameObject
```

### 2.2 Puppet Spawn Sequence (Lua)

```lua
-- 1. Create the server entity (bypasses alife guard on client)
local sim = alife()
local se_obj = mp_alife_guard.internal_create(sim,
    "stalker_silent",           -- section: silent stalker (no voice lines)
    vector():set(x, y, z),     -- world position
    lvid,                       -- level vertex ID (from host data)
    gvid                        -- game vertex ID (from host data)
)

-- 2. Force online + prevent offline (entity stays rendered regardless of distance)
sim:set_switch_online(se_obj.id, true)
sim:set_switch_offline(se_obj.id, false)

-- 3. Wait for game object (switch_online happens during next A-Life update cycle)
-- In practice: poll level.object_by_id(se_obj.id) each frame until non-nil
-- OR: use server_entity_on_register callback which fires synchronously

-- 4. When game object exists:
local obj = level.object_by_id(se_obj.id)
if obj then
    -- Suppress all AI behavior
    obj:set_mental_state(1)      -- eMentalStateFree: no combat
    obj:set_movement_type(2)     -- eMovementTypeStand: don't walk
    obj:set_body_state(1)        -- eBodyStateStand: standing
    obj:set_desired_direction()  -- clear pathfinding direction
    obj:set_desired_position()   -- clear pathfinding target
    obj:invulnerable(true)       -- ignore all damage (Phase 1: no damage sync)
end
```

### 2.3 Section Choice: `stalker_silent`

From `spawn_sections_general.ltx` lines 1-26:
```ini
[stalker_silent]:stalker
$spawn = "respawn\stalker_silent"
character_profile = sim_default_stalker_0
sound_death =           ; ALL sound lines empty
sound_hit =
sound_humming =
sound_alarm =           ; ...etc
```

**Why `stalker_silent`**: No voice barks, no combat sounds, no panic shouts. A puppet shouldn't talk. Inherits from `[stalker]` base class in `m_stalker.ltx` (visual, collision, physics all standard).

**Alternative**: `stalker_azazel` (line 60) uses `character_profile = actor` — same visual as the player character. Could be useful for "you see yourself" cases.

### 2.4 Game Object Wait Problem

`alife():create()` fires `server_entity_on_register` synchronously, but `switch_online()` (which creates the game object) happens in the **next A-Life scheduler tick** — not the same frame. So:

1. Frame N: `create()` → se_obj exists, `level.object_by_id()` returns nil
2. Frame N+1 to N+k: A-Life scheduler runs `try_switch_online()` → distance check → `Process_spawn()`
3. Frame N+k: `level.object_by_id()` returns the game object

**Mitigation**: Use the `server_entity_on_register` callback to track the se_obj.id, then poll `level.object_by_id()` in the update loop until non-nil. Apply AI suppression on first non-nil frame.

---

## 3. Update Flow

How to update position, heading, animation, and equipment on a live puppet.

### 3.1 Position Update

```lua
function update_puppet_position(puppet_id, x, y, z)
    local obj = level.object_by_id(puppet_id)
    if obj then
        -- Online: direct physics position write
        obj:force_set_position(vector():set(x, y, z), false)
    else
        -- Offline: update server entity position via teleport
        local sim = alife()
        local se_obj = sim:object(puppet_id)
        if se_obj then
            sim:teleport_object(puppet_id,
                se_obj.m_game_vertex_id,
                se_obj.m_level_vertex_id,
                vector():set(x, y, z))
        end
    end
end
```

`force_set_position()` directly writes `XFORM().c = pos` and optionally activates the physics shell. No collision correction, no pathfinding — exactly what we want for a networked puppet.

### 3.2 Heading Update

```lua
function update_puppet_heading(puppet_id, heading_rad)
    local obj = level.object_by_id(puppet_id)
    if obj then
        -- Convert heading angle to direction vector
        local dir = vector():set(
            math.sin(heading_rad),
            0,
            math.cos(heading_rad)
        )
        obj:set_desired_direction(dir)
    end
end
```

**Current PP message format** (from `mp_host_events.script:346-356`):
```
PP|id,x,y,z,h
```
Where `h` = health (0.0-1.0). **Heading is NOT currently sent.** This is a gap.

Wait — re-reading the EP format at `mp_host_events.script:322-328`:
```lua
entities[count] = {
    id = id,
    x = pos.x, y = pos.y, z = pos.z,
    h = obj:health() or 1.0,
}
```

The `h` field is health for both EP and PP messages. **Heading angle is not transmitted in any message type.** This needs to be added.

### 3.3 Interpolation

Current snapshot rate: 20Hz (50ms intervals, `mp_host_events.send_snapshots()`).

At 20Hz, linear interpolation between position snapshots is sufficient for smooth movement at walking/running speeds (~2-7 m/s). With 50ms between updates, a running stalker moves ~0.35m between snapshots — imperceptible jitter with lerp.

**Recommended interpolation approach:**
```
For each puppet:
  - Store: last_pos, target_pos, last_update_time
  - On new position message: last_pos = current_pos, target_pos = new_pos, reset timer
  - Each frame: lerp(last_pos, target_pos, elapsed / 50ms)
  - Clamp at target when elapsed >= 50ms
```

### 3.4 What PP Messages Need for Rendering

**Currently sent (PP):**
```
id, x, y, z, h (health)
```

**Missing for Phase 1:**
```
heading      -- yaw angle in radians (float, ~4 chars as text)
body_state   -- 0=crouch, 1=stand (1 char)
move_type    -- 0=walk, 1=run, 2=stand (1 char)
```

**Proposed PP format:**
```
PP|id,x,y,z,health,heading,body,move
PP|4200,100.50,20.30,50.70,0.95,1.57,1,1
```

This adds ~10 bytes per player per message — trivial.

---

## 4. Animation System

### 4.1 Available States

The engine's stalker animation system is state-driven, not keyframe-driven. Animations play automatically based on the combination of:

| State | API | Values | Automatic Animation |
|-------|-----|--------|---------------------|
| Mental | `set_mental_state()` | 0=danger, 1=free, 2=panic | Weapon stance, alertness posture |
| Body | `set_body_state()` | 0=crouch, 1=stand | Crouch/stand skeleton pose |
| Movement | `set_movement_type()` | 0=walk, 1=run, 2=stand | Walk/run/idle locomotion cycle |

**Key insight**: Setting these three states is sufficient for basic visual fidelity. The engine automatically plays the correct animation blend. A puppet with:
- `mental=1, body=1, move=1` → relaxed running animation
- `mental=0, body=0, move=2` → combat crouch idle
- `mental=1, body=1, move=2` → relaxed standing idle

### 4.2 Arbitrary Animations

`obj:play_cycle(anim_name, mix_in)` can override the state-driven system with a specific animation. However:
- We don't know what animation names are valid without inspecting .ogf model files
- The state machine will fight the override on the next AI tick
- For Phase 1, the three-state system (mental/body/movement) should be sufficient

### 4.3 Sprint

There is no explicit "sprint" state in the engine enum. Sprint is `eMovementTypeRun` with `eMentalStateFree` — the engine plays the fastest locomotion cycle.

### 4.4 Death Animation

When `obj:health()` reaches 0, the engine plays a death animation automatically. For Phase 1, puppet death is not synced — the puppet is invulnerable.

---

## 5. Equipment & Visual Sync

### 5.1 How the Engine Renders Equipment

Stalker NPCs have a **single visual model** (`actors\stalker_hero\stalker_hero_1.ogf` by default from `m_stalker.ltx:340`). The outfit/armor changes the visual via `set_visual_name()` — it's a full model swap, not a layer system.

The character profile system (referenced by `character_profile` in spawn sections) determines the NPC's faction appearance, name, icon, and default outfit.

### 5.2 Outfit Visual Path

When a stalker equips an outfit, the engine:
1. Reads the outfit's `player_hud_section` and visual model from its .ltx config
2. Calls the equivalent of `set_visual_name()` internally to swap the body mesh
3. The new mesh includes the outfit's visual representation

**For puppet sync**: We need the host to send the outfit section name. The client then calls `set_visual_name()` with the corresponding visual path.

### 5.3 Reading Actor Equipment (Host Side)

```lua
-- Outfit (slot 7)
local outfit = db.actor:item_in_slot(7)
local outfit_section = outfit and outfit:section() or nil

-- Helmet (slot 12)
local helmet = db.actor:item_in_slot(12)
local helmet_section = helmet and helmet:section() or nil

-- Active weapon (slot 2 = primary, slot 3 = secondary)
local weapon = db.actor:active_item() or db.actor:item_in_slot(2) or db.actor:item_in_slot(3)
local weapon_section = weapon and weapon:section() or nil
```

### 5.4 Applying Visual to Puppet (Client Side)

```lua
-- Option A: Change the visual model directly (for outfit)
local visual_path = get_visual_for_outfit(outfit_section)  -- needs lookup table
obj:set_visual_name(visual_path, true)

-- Option B: Transfer an outfit item to the puppet's inventory
-- This is complex: requires creating the item first, then transferring
-- Engine will auto-apply the visual when the NPC "equips" it
```

**Option A is simpler** but requires a mapping from outfit section → visual path.
**Option B is more correct** but involves entity creation + inventory management.

### 5.5 Weapon in Hands

The held weapon model is determined by the NPC's current `active_item()` — the item in their active weapon slot. For a puppet:
- We'd need to create a weapon entity in the puppet's inventory
- Then make it the active item
- This is complex and may be Phase 2

**Phase 1 recommendation**: Sync the outfit visual only. Weapon-in-hand is Phase 2.

### 5.6 PE Message Format

**Proposed PLAYER_EQUIP message:**
```
PE|outfit=stalker_outfit_cs2|helmet=helm_hardhat|weapon=wpn_ak74
```

Sent reliably on equipment change (not every frame). Client looks up visual paths and applies.

### 5.7 Live Update vs Respawn

`set_visual_name()` can change the model **live** — no need to despawn and respawn. Confirmed in `script_game_object2.cpp:670-697`: it generates a `GE_CHANGE_VISUAL` event that triggers `ChangeVisual()` on the stalker, which recalculates bones and swaps the mesh.

---

## 6. Existing MP Infrastructure

### 6.1 Original X-Ray MP System (Dormant)

The engine contains the complete original Clear Sky multiplayer code, unused by GAMMA:

| File | Class | Purpose |
|------|-------|---------|
| `game_sv_mp.h/cpp` | `game_sv_mp` | MP game server — ranks, teams, voting, corpses |
| `game_cl_mp.h/cpp` | `game_cl_mp` | MP client — HUD, sounds, teams |
| `actor_mp_server.h` | `CSE_ActorMP` | Server-side actor entity with `UPDATE_Read/Write(NET_Packet&)` |
| `actor_mp_server_export.cpp` | — | Serializes actor state: quaternion, velocities, position, yaw/pitch/roll, inventory slot, body state flags |
| `actor_mp_server_import.cpp` | — | Deserializes NET_Packet back into actor state |
| `actor_mp_client.h/cpp` | `CActorMP` | Client-side actor with `net_Export/Import` |
| `actor_mp_state.h/cpp` | `actor_mp_state` | State struct with quantization (111→11 bytes) |
| `xrGameSpyServer.h/cpp` | `xrGameSpyServer` | GameSpy matchmaking (obsolete) |
| `Level_network*.cpp` | — | Engine-level networking, compressed updates, spawn flows |

### 6.2 actor_mp_state Serialization (Reuse Potential)

The `actor_mp_state` struct (`actor_mp_state.h`) contains exactly what we need for player sync:

```cpp
struct actor_mp_state {
    Fquaternion physics_quaternion;       // orientation
    Fvector     physics_linear_velocity;  // movement velocity
    Fvector     physics_position;         // physics engine position
    Fvector     position;                 // logical position
    float       model_yaw;               // body heading
    float       camera_yaw, camera_pitch, camera_roll;  // view angles
    u32         time;                     // timestamp
    float       health;                   // 0-1
    float       radiation;                // 0-1
    u32         inventory_active_slot : 4;  // weapon slot (4 bits)
    u32         body_state_flags : 15;      // movement state
    u32         physics_state_enabled : 1;  // physics active
};
```

The quantization code in `actor_mp_state.cpp` (lines 154-218) uses a 16-bit mask system and packs efficiently:
- Velocity: 8-bit quantized, range [-32, 32] m/s
- Camera angles: 8-bit quantized, range [0, 2pi]
- Health/radiation: 8-bit and 4-bit packed

### 6.3 Can We Reuse It?

**Short answer: No, not directly.** The original MP system is deeply integrated with:
- `NET_Packet` binary serialization (we use text protocol over GNS)
- `xrServer` client/server architecture (we use Lua + gns_bridge)
- GameSpy matchmaking (defunct)
- Engine-level `net_Export/Import` virtual methods

**What we CAN reuse:** The `actor_mp_state` structure is an excellent reference for what fields need syncing and how to quantize them efficiently. When we move to binary protocol (Phase 2), we can adopt the same quantization scheme.

### 6.4 NET_Packet Infrastructure

`NET_Packet` is the engine's binary serialization format. It's used extensively in the original MP but also in single-player for server entity serialization (`STATE_Read/Write`, `UPDATE_Read/Write`). We're not using it because our Lua layer can't easily construct NET_Packets — and the text protocol is simpler to debug.

---

## 7. Network Message Flow

### 7.1 Current Flow (Phase 0)

```
Host                                    Client
─────                                   ──────
mp_update() [every frame]
  ├─ send_snapshots() [every 50ms]
  │   ├─ EP: 100 entity positions       ──UDP──>  on_entity_positions()
  │   │      (round-robin cursor)                    resolve_id() → force_set_position()
  │   │
  │   └─ PP: host actor position         ──UDP──>  on_remote_player_pos()
  │          id, x, y, z, health                     stores in _remote_players[conn_id]
  │                                                  TODO: render puppet
  │
  ├─ [on entity register]
  │   ES: section, pos, ids              ──TCP──>  on_entity_spawn() → do_entity_spawn()
  │                                                  alife():create() → ID mapping
  │
  ├─ [on entity death]
  │   ED: id, killer_id, pos             ──TCP──>  on_entity_death()
  │                                                  kill_entity()
  │
  └─ [every 5s]
      WS: weather preset                 ──TCP──>  level.set_weather()
      TS: hours, mins, factor            ──TCP──>  level.set_game_time()
```

### 7.2 What's Missing for Phase 1

**Client → Host (not implemented):**
```
Client mp_update()
  └─ [every 50ms] PP: client actor pos   ──UDP──>  on_client_player_pos()
       id, x, y, z, health, heading,                 stores in _clients[conn_id]
       body_state, move_type                          TODO: broadcast to other clients
```

**Host → All Clients (not implemented):**
```
Host mp_update()
  └─ [every 50ms] for each connected client:
       PP: that client's position         ──UDP──>  on_remote_player_pos()
           (forwarded from _clients[conn])            create/update puppet entity
```

**Equipment (not implemented):**
```
Client: on equipment change
  PE: outfit, helmet, weapon             ──TCP──>  Host: store + broadcast to others
  
Host: broadcast to other clients
  PE: conn_id, outfit, helmet, weapon    ──TCP──>  Client: update puppet visual
```

### 7.3 Proposed Phase 1 Message Flow

```
Client A                    Host                       Client B
────────                    ────                       ────────

[every 50ms]
PP: my position  ──UDP──>  store in _clients[A]
                           [every 50ms]
                           PP: A's pos      ──UDP──>  create/update puppet_A
                           PP: host pos     ──UDP──>  create/update puppet_host
                 <──UDP──  PP: B's pos                
                 <──UDP──  PP: host pos

[equip change]
PE: my outfit    ──TCP──>  store in _clients[A]
                           PE: A's outfit   ──TCP──>  update puppet_A visual
```

---

## 8. Level & Distance Constraints

### 8.1 Online Distance

**Config** (`alife.ltx` in GAMMA Alife optimization mod):
```ini
switch_distance = 450
switch_factor = 0.1
auto_switch = true
```

**Formula** (`alife_switch_manager_inline.h:35-40`):
```cpp
online_distance  = switch_distance * (1.0 - switch_factor)  = 450 * 0.9 = 405m
offline_distance = switch_distance * (1.0 + switch_factor)  = 450 * 1.1 = 495m
```

Entities within 405m of the actor switch online (get game objects, render).
Entities beyond 495m switch offline (server entity only, no rendering).

**For puppets**: We call `set_switch_online(id, true)` + `set_switch_offline(id, false)` to bypass distance checks entirely. Puppet stays online as long as it exists.

### 8.2 Level Boundary Constraint

**CRITICAL**: `alife_switch_manager.cpp:53` asserts that an entity's game graph vertex must be on the **same level** as the current active level to go online:

```cpp
VERIFY((ai().game_graph().vertex(object->m_tGraphID)->level_id() == 
        graph().level().level_id()));
```

**Impact**: We cannot render a puppet for a remote player who is on a different level. If host is on Garbage and client B is on Cordon, host cannot see client B's puppet.

**Mitigation**: Only create puppets for players on the same level. Destroy puppet when remote player changes level. Show "Player X is on [level name]" in UI instead.

### 8.3 Auto-Switch Suppression

With `set_switch_offline(id, false)`, the puppet cannot auto-offline. But the A-Life scheduler still checks it every tick. If we also call `set_switch_online(id, true)`, the entity stays online.

**Potential issue**: The `can_switch_offline()` override in `CSE_ALifeCreatureAbstract` (`xrServer_Objects_ALife_Monsters.cpp:1192-1195`) also checks `get_health() > 0`. If puppet health drops to 0 somehow (shouldn't happen with `invulnerable(true)`), it can't switch offline — which is actually fine for us, but the VERIFY assertion may fire.

---

## 9. Collision & Physics

### 9.1 Puppet Collision

**Yes, spawned stalker NPCs have full collision.** From `m_stalker.ltx`:
```ini
cform = skeleton      ; collision form = skeletal mesh (line 348)
ph_mass = 80          ; 80kg physics mass (line 522)
ph_box0_center = 0.0, 0.9, 0.0    ; upper body box (line 512)
ph_box0_size = 0.2, 0.9, 0.2
ph_box1_center = 0.0, 0.6, 0.0    ; lower body box (line 514)
ph_box1_size = 0.2, 0.6, 0.2
```

When `Process_spawn()` creates the game object, a physics shell is instantiated with these parameters.

### 9.2 Implications

| Interaction | Behavior | Desirable? |
|-------------|----------|------------|
| Local player walks into puppet | Blocked by collision | Yes — feels solid |
| Local player shoots puppet | Hit registered, but `invulnerable(true)` ignores it | Yes for Phase 1 |
| Puppet blocks NPC pathing | NPCs pathfind around puppet | Acceptable |
| Puppet blocks doorways | Players/NPCs can't pass | **Problem** — could grief |
| Physics objects hit puppet | Collision response | Acceptable |
| Puppet falls through terrain | Depends on `force_set_position` | **Risk** — needs testing |

### 9.3 Do We Want Collision?

**Phase 1: Yes**, with caveats. Solid collision makes the remote player feel "real." The griefing risk (blocking doorways) is acceptable for "two dudes in the Zone."

If collision becomes a problem, we can potentially disable the physics shell after spawn, but this hasn't been tested and may cause rendering issues.

---

## 10. Death & Damage (Phase 2 Preview)

### 10.1 If a Mutant Attacks the Puppet

With `invulnerable(true)`: Hit registered, damage calculated to 0, no death. Puppet continues standing. The mutant AI will continue attempting to attack because the puppet is a valid target (it's a stalker entity).

**Risk**: Mutants could "aggro" on the puppet indefinitely, altering local AI behavior. Phase 2 might need a "don't target this entity" flag or faction override.

### 10.2 If the Local Player Shoots the Puppet

Same as above — invulnerable. No damage, no death animation, no ragdoll. The hit effect (spark/blood decal) may still play.

**Phase 2 design question**: Should shooting a puppet:
a) Do nothing (puppet is cosmetic)?
b) Send a damage event to the host, who applies it to the real player?
c) Something else?

### 10.3 Death Flow (When We Need It)

When `health` reaches 0 on a `CSE_ALifeCreatureAbstract`:
1. `on_death(killer)` is called (`xrServer_Objects_ALife_Monsters.cpp:1066-1071`)
2. `fHealth` set to -1.0 (sentinel)
3. `m_game_death_time` recorded
4. Entity stays online (dead entities can't switch offline: `can_switch_offline()` returns false when health <= 0)
5. Death animation plays automatically
6. Corpse remains until despawned

**Phase 2 sync**: Host sends ED with puppet's ID as the victim → client removes invulnerability → applies lethal hit → death animation plays naturally.

### 10.4 Health Tracking

Health is serialized in NET_Packet as float. In our PP messages, health is already sent as the `h` field. Phase 2 needs:
- Remove invulnerability on puppet
- Apply health deltas from host
- Sync death/respawn state

---

## 11. Mod Conflicts

### 11.1 NPC Spawning Mods

From `MASTER_AUDIT_REPORT.md`:

| Mod | Risk | Impact on Puppet Spawning |
|-----|------|---------------------------|
| ZCP 1.4/1.5d | CRITICAL | `server_entity_on_register` fires for squads/smart terrains. Puppet create() will trigger ZCP callbacks. **Must filter puppet entities in ZCP's handlers.** |
| Dynamic Despawner | CRITICAL | Iterates online NPCs every ~43s and releases excess. **Could despawn puppet.** Gate with `is_host()` check. |
| Dynamic Anomalies | CRITICAL | `alife():create()` in actor_on_update. Not directly puppet-related but could interfere if puppet ID collides. |
| Snipers Remover | CRITICAL | `alife():release()` in npc_on_update. Could target puppet if it matches sniper criteria. |
| axr_companions | CRITICAL | `server_entity_on_unregister` callback. Puppet despawn could trigger companion logic. |

### 11.2 NPC Appearance Mods

| Mod | Path | What It Overrides |
|-----|------|-------------------|
| Stealth Overhaul | `configs/creatures/m_stalker.ltx` | Vision/reaction params (eye_fov, eye_range) |
| NPCs Faster Reactions | `configs/creatures/m_stalker.ltx` | Reaction speed params |
| Death Animations | `configs/creatures/m_stalker.ltx` | Death animation behavior |
| Close Quarter Combat | `configs/creatures/grok_bo_models_capture.ltx` | Bone profiles for melee |

**Impact**: These mods affect stalker behavior/appearance configs. Puppet will inherit these configs when spawned from `stalker_silent` (which inherits from `[stalker]`). This is **acceptable** — we want the puppet to look like a normal stalker.

### 11.3 mp_alife_guard Interaction

`mp_alife_guard.internal_create()` bypasses the metatable guard and calls the **real** `alife():create()`. This means:
- Puppet spawn goes through the normal engine path
- `server_entity_on_register` fires normally
- ZCP and other mods that hook this callback WILL see the puppet entity

**Mitigation**: Tag puppet entities (e.g., store their IDs in a `_puppet_ids` set) and filter them in our callback handlers. OR: use a unique section name like `mp_puppet_stalker` that mods don't know about.

### 11.4 Visual Override Mods

Mods that use `set_visual_name()` or override `ChangeVisual()` could interfere with puppet outfit sync. Not found in current GAMMA mods, but Mark Switch (weapon skins) does similar things for weapons.

---

## 12. Risk Register

| # | Risk | Severity | Likelihood | Mitigation |
|---|------|----------|------------|------------|
| R1 | Puppet entity gets despawned by Dynamic Despawner mod | HIGH | HIGH | Tag puppet IDs; add `is_puppet()` check to despawner guard, or gate entire despawner with `is_host()` |
| R2 | ZCP `server_entity_on_register` callback corrupts ID mapping when puppet spawns | HIGH | CERTAIN | Filter puppet section/ID in our entity registration handler |
| R3 | AI aggro — mutants/NPCs attack the puppet, altering world simulation | MEDIUM | HIGH | Set puppet faction to same as local player. Consider `set_relation()` or dummy squad assignment |
| R4 | Puppet falls through terrain after `force_set_position()` | MEDIUM | MEDIUM | Test in-game. May need to use `set_npc_position()` instead, or snap to level vertex |
| R5 | Game object doesn't exist on first frame after create() | LOW | CERTAIN | Poll `level.object_by_id()` until non-nil; queue AI suppression calls |
| R6 | Puppet on different level crashes with VERIFY assertion | HIGH | HIGH | Only create puppets for same-level players. Destroy when player changes level |
| R7 | Heading sync missing — puppets always face same direction | MEDIUM | CERTAIN | Add heading field to PP message. Already identified as gap |
| R8 | 20Hz not smooth enough for fast movement | LOW | LOW | Linear interpolation covers this. Can increase to 30Hz if needed |
| R9 | Equipment visual desync between host and client mods | MEDIUM | MEDIUM | Use section names (not visual paths) and let each client resolve locally |
| R10 | Puppet blocks doorways/paths, griefing potential | LOW | LOW | Acceptable for Phase 1 "two dudes in the Zone" |
| R11 | `invulnerable(true)` doesn't fully suppress hit effects | LOW | MEDIUM | Cosmetic only — blood/spark decals on puppet. Acceptable |
| R12 | Memory leak from puppet entities not cleaned up on disconnect | HIGH | MEDIUM | Track puppet IDs; on remote player disconnect, `internal_release()` the puppet |
| R13 | Multiple puppets for same player (disconnect/reconnect without cleanup) | MEDIUM | MEDIUM | Map conn_id → puppet_id; cleanup old puppet before creating new |
| R14 | Mod that overrides `stalker_silent` section breaks puppet | LOW | LOW | Unlikely — section is rarely modded. Fallback to `default_stalker` |

---

## 13. Dependency Graph

```
                    ┌─────────────────────┐
                    │  PP Message Update   │  ← Add heading, body_state, move_type
                    │  (mp_protocol.script)│
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                 │
              ▼                ▼                 ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
   │ Host: Send    │  │ Client: Send │  │ Host: Broadcast   │
   │ own position  │  │ own position │  │ other clients' PP │
   │ (exists)      │  │ to host      │  │ to each client    │
   │               │  │ (NEW)        │  │ (NEW)             │
   └──────┬───────┘  └──────┬───────┘  └────────┬──────────┘
          │                  │                    │
          └──────────────────┼────────────────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │ Puppet Entity Manager │  ← NEW module
                  │ (mp_puppet.script?)   │
                  │                       │
                  │ - spawn_puppet(conn)  │
                  │ - despawn_puppet(conn)│
                  │ - update_puppet(conn, │
                  │     pos, heading,     │
                  │     body, move)       │
                  │ - update_equip(conn,  │
                  │     outfit, helmet,   │
                  │     weapon)           │
                  └──────────┬────────────┘
                             │
          ┌──────────────────┼───────────────────┐
          │                  │                    │
          ▼                  ▼                    ▼
┌─────────────────┐ ┌────────────────┐  ┌────────────────┐
│ Entity Spawn    │ │ Position/Anim  │  │ Visual/Equip   │
│                 │ │ Update         │  │ Update         │
│ internal_create │ │                │  │                │
│ set_switch_*    │ │ force_set_pos  │  │ set_visual_name│
│ invulnerable    │ │ set_desired_dir│  │ (Phase 2:      │
│ AI suppression  │ │ set_mental_st  │  │  transfer_item)│
│                 │ │ set_body_state │  │                │
│                 │ │ set_move_type  │  │                │
└─────────────────┘ └────────────────┘  └────────────────┘
          │                  │                    │
          ▼                  ▼                    ▼
┌───────────────────────────────────────────────────────────┐
│                    Engine APIs (C++)                       │
│  alife_simulator, script_game_object, alife_switch_mgr   │
└───────────────────────────────────────────────────────────┘
```

---

## 14. Recommended Implementation Order

### Step 1: PP Message Enhancement
**Files**: `mp_protocol.script`, `mp_host_events.script`
**What**: Add heading, body_state, move_type to PP messages. Both host→client and client→host.
**Why first**: Foundation for everything else. No entity spawning needed to test.
**Risk**: Low — additive change to existing protocol.

### Step 2: Client → Host Position Upload
**Files**: `mp_core.script` (client update loop), `mp_host_events.script` (receive handler)
**What**: Client sends PP with own actor position every 50ms. Host stores in `_clients[conn_id]`.
**Why second**: Host needs client positions before it can broadcast to other clients.
**Depends on**: Step 1 (enhanced PP format).

### Step 3: Host → Client Position Relay
**Files**: `mp_host_events.script` (send_snapshots)
**What**: Host broadcasts each connected client's position to all OTHER clients. Also broadcasts own position (already done).
**Depends on**: Step 2 (client positions available in `_clients`).

### Step 4: Puppet Entity Manager
**Files**: NEW `mp_puppet.script` (or extend `mp_client_state.script`)
**What**: 
- `spawn_puppet(conn_id)` — create stalker_silent, force online, suppress AI, invulnerable
- `despawn_puppet(conn_id)` — internal_release
- `update_position(conn_id, x, y, z, heading)` — force_set_position + set_desired_direction
- `update_animation(conn_id, body, move)` — set_body_state + set_movement_type
- Track `_puppets[conn_id] = { id, se_obj, obj }`
**Depends on**: Step 3 (position data flowing from host).

### Step 5: Interpolation
**Files**: `mp_puppet.script`
**What**: Linear interpolation between position snapshots. Store last/target positions, lerp each frame.
**Depends on**: Step 4 (puppet exists and can be moved).

### Step 6: Puppet Lifecycle
**Files**: `mp_puppet.script`, `mp_client_state.script`, `mp_core.script`
**What**:
- Create puppet on first PP received for a conn_id
- Destroy puppet on disconnect event
- Destroy puppet when remote player changes level
- Handle reconnect (destroy old, create new)
**Depends on**: Step 4.

### Step 7: Equipment Sync (Basic)
**Files**: `mp_protocol.script`, `mp_host_events.script`, `mp_puppet.script`
**What**:
- Host reads own outfit/helmet/weapon sections, sends PE on change
- Client reads own equipment, sends PE to host
- Host relays PE to other clients
- Client applies `set_visual_name()` on puppet based on outfit section
**Depends on**: Step 4 (puppet exists). Can be done in parallel with Step 5.

### Step 8: Mod Conflict Guards
**Files**: Various GAMMA mod scripts, `mp_alife_guard.script`
**What**:
- Tag puppet entities in a `_puppet_ids` set
- Guard Dynamic Despawner, Snipers Remover against puppet IDs
- Filter puppet entities in ZCP callback handlers
**Depends on**: Step 4 (puppet section/ID known).

---

## 15. Open Questions

These cannot be determined from code alone — they require in-game testing.

| # | Question | Why It Matters | How to Test |
|---|----------|----------------|-------------|
| Q1 | Does `force_set_position()` on a stalker NPC keep it above terrain, or can it clip through? | If it clips, we need `set_npc_position()` or level vertex snapping | Spawn NPC, force_set_position to known coordinates, observe |
| Q2 | Does `set_switch_online(id, true)` + `set_switch_offline(id, false)` work reliably together? | Core of puppet persistence | Spawn NPC at >500m from actor, check if game object persists |
| Q3 | How fast does `switch_online` happen after `create()`? Same frame? Next tick? | Determines if we can set AI state immediately or need polling | Create NPC, immediately check `level.object_by_id()` |
| Q4 | Does `set_desired_direction()` actually rotate a standing NPC, or does it only affect pathfinding? | Heading sync correctness | Spawn NPC with `eMovementTypeStand`, call `set_desired_direction()`, observe rotation |
| Q5 | Does `invulnerable(true)` suppress hit VFX (blood decals, impact sparks)? | Visual polish | Shoot an invulnerable NPC, observe |
| Q6 | What happens to A-Life scheduling load with 2-8 permanent online puppets? | Performance | Spawn 8 NPC puppets, measure FPS and A-Life tick time |
| Q7 | Does the outfit visual path follow a deterministic pattern from section name? | Needed for `set_visual_name()` mapping | Read outfit .ltx configs, check `visual` or `player_hud_section` fields |
| Q8 | Can we set `set_mental_state` on an NPC that has no patrol path? | AI state machine may require path | Spawn NPC at random position (no patrol), set mental state, observe for crashes |
| Q9 | Does `stalker_silent` section exist in all GAMMA installations, or is it mod-dependent? | If mod-dependent, need fallback section | Check if `stalker_silent` is defined in base Anomaly or only in ZCP |
| Q10 | What's the maximum number of online stalker NPCs before performance degrades? | Puppet count limit | Spawn increasing numbers of NPCs, measure FPS |
| Q11 | Does `set_visual_name()` on a stalker NPC crash if called before the model is fully loaded? | Timing of visual updates | Call `set_visual_name()` immediately after game object appears |
| Q12 | When a puppet is at the same position as a real NPC, does the engine handle the collision correctly? | Two entities occupying same space | Teleport puppet to known NPC location, observe |

---

## Appendix A: File Reference

### Engine Source (C++) — Key Files for Phase 1

| File | Path | Relevance |
|------|------|-----------|
| `alife_simulator_script.cpp` | `xrGame/` | Lua bindings: create, release, set_switch_*, teleport_object |
| `alife_simulator_base.cpp` | `xrGame/` | Core create/register flow |
| `alife_switch_manager.cpp` | `xrGame/` | Online/offline switching logic, distance checks |
| `alife_switch_manager_inline.h` | `xrGame/` | Online/offline distance calculation |
| `alife_dynamic_object.cpp` | `xrGame/` | try_switch_online/offline, distance checks |
| `script_game_object2.cpp` | `xrGame/` | Position setters, visual setters, hit, play_cycle |
| `script_game_object3.cpp` | `xrGame/` | AI state setters, force_set_position, add_animation |
| `script_game_object_script2.cpp` | `xrGame/` | Lua binding declarations for game_object methods |
| `script_game_object_script3.cpp` | `xrGame/` | More Lua binding declarations |
| `ai_monster_space.h` | `xrGame/` | EMentalState, EBodyState, EMovementType enums |
| `xrServer_Objects_ALife.h/cpp` | `xrServerEntities/` | can_switch_online/offline flags |
| `xrServer_Objects_ALife_Monsters.cpp` | `xrServerEntities/` | on_death, health checks, can_switch_offline override |
| `actor_mp_state.h/cpp` | `xrGame/` | Reference for state serialization and quantization |

### Lua Sync Layer — Files to Modify

| File | What Changes |
|------|-------------|
| `mp_protocol.script` | Enhanced PP format (heading, body_state, move_type), PE handling |
| `mp_host_events.script` | Client position receive + relay, equipment receive + relay, heading in send_snapshots |
| `mp_client_state.script` | Remote player puppet creation/update/destroy, interpolation |
| `mp_core.script` | Client-side position/equipment send in update loop |
| NEW: `mp_puppet.script` | Puppet entity lifecycle manager (optional — could live in mp_client_state) |

### Game Configs

| File | Relevance |
|------|-----------|
| `spawn_sections_general.ltx` | `stalker_silent` section definition (our puppet section) |
| `m_stalker.ltx` | Base stalker class: visual, collision, physics, health |
| `alife.ltx` | switch_distance, switch_factor (online radius) |

---

## Appendix B: Current PP Message vs Required

**Current (Phase 0):**
```
PP|{actor_id},{x},{y},{z},{health}
```

**Required (Phase 1):**
```
PP|{actor_id},{x},{y},{z},{health},{heading},{body_state},{move_type}
```

**Example:**
```
PP|4200,100.50,20.30,50.70,0.95,1.57,1,1
     │     │      │     │    │    │   │  └─ move: 1=run
     │     │      │     │    │    │   └──── body: 1=stand
     │     │      │     │    │    └──────── heading: 1.57 rad (~90deg)
     │     │      │     │    └───────────── health: 0.95
     │     │      │     └────────────────── z: 50.70
     │     │      └──────────────────────── y: 20.30 (vertical)
     │     └─────────────────────────────── x: 100.50
     └───────────────────────────────────── actor ID
```

Added fields cost ~10 bytes per message per player. At 20Hz with 4 players = 800 bytes/sec additional. Negligible.
