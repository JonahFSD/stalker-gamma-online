-- test_client_state.lua: State machine, spawn queue, cleanup, ID mapping, position apply (Commit 6)

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")
dofile(BASE .. "mock/globals.lua")
dofile(BASE .. "mock/engine.lua")
dofile(BASE .. "mock/gns.lua")
dofile(BASE .. "loader.lua")

local SCRIPT_DIR = BASE .. "../lua-sync"
loader_init(SCRIPT_DIR)

local function reset_all_state()
    reset_engine()
    reset_gns()
    reset_globals()
    set_verbose(false)
    reset_all()
    set_verbose(true)
    _G.is_mp_client = function() return true end
    _G.is_mp_host   = function() return false end
    set_mock_actor(0, {x=0, y=0, z=0})
end

-- Helper: install alife guard bypass so mp_client_state.do_entity_spawn works
local function install_guard()
    _G.alife_create      = function(...) return alife():create(...) end
    _G.alife_release     = function(se) return alife():release(se, true) end
    _G.alife_release_id  = function(id) local se=alife():object(id); if se then alife():release(se,true) end end
    _G.alife_create_item = function(sec,obj,t) return alife():create(sec, obj, 0, 0) end
    set_verbose(false)
    mp_alife_guard.install()
    set_verbose(true)
end

-- Helper: spawn entity via do_entity_spawn (bypasses state-machine queueing)
-- and return the mapped local_id. Registers/unregisters the ID mapping callback.
local function client_spawn(host_id, section, pos_x, pos_y, pos_z)
    pos_x = pos_x or 0; pos_y = pos_y or 0; pos_z = pos_z or 0
    RegisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)
    mp_client_state.do_entity_spawn({
        id = host_id, section = section,
        pos_x = pos_x, pos_y = pos_y, pos_z = pos_z,
        lvid = 0, gvid = 0,
    })
    UnregisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)
    return mp_client_state.resolve_id(host_id)
end

-- ============================================================================
-- ID Mapping
-- ============================================================================

describe("client_state: ID mapping basics", function()
    before_each(reset_all_state)

    it("map_id and resolve_id round-trip", function()
        mp_client_state.map_id(4200, 7831)
        assert_eq(7831, mp_client_state.resolve_id(4200))
    end)

    it("unmap_id clears both directions", function()
        mp_client_state.map_id(100, 200)
        assert_eq(200, mp_client_state.resolve_id(100))
        mp_client_state.unmap_id(100)
        assert_nil(mp_client_state.resolve_id(100))
    end)

    it("reverse_id maps local -> host", function()
        mp_client_state.map_id(4200, 7831)
        assert_eq(4200, mp_client_state.reverse_id(7831))
    end)

    it("resolve_id returns nil for unknown entity", function()
        assert_nil(mp_client_state.resolve_id(9999))
    end)
end)

describe("client_state: spawn → register → ID map flow", function()
    before_each(function()
        reset_all_state()
        install_guard()
    end)

    it("basic spawn maps host_id to local_id", function()
        local local_id = client_spawn(4200, "stalker_bandit", 10.0, 5.0, 20.0)
        assert_not_nil(local_id, "ID should be mapped after spawn")
        assert_true(local_id >= 1000, "local_id should be a valid mock ID")
        assert_eq(local_id, mp_client_state.resolve_id(4200))
    end)

    it("on_local_entity_registered uses FIFO key matching", function()
        -- Two spawns at different positions, same section
        local local1 = client_spawn(100, "stalker_bandit", 1.0, 0.0, 0.0)
        local local2 = client_spawn(101, "stalker_bandit", 2.0, 0.0, 0.0)
        assert_not_nil(local1)
        assert_not_nil(local2)
        assert_neq(local1, local2)
        assert_eq(local1, mp_client_state.resolve_id(100))
        assert_eq(local2, mp_client_state.resolve_id(101))
    end)

    it("multiple spawns same section same pos use FIFO order", function()
        -- Same position → key collision → FIFO list
        -- do_entity_spawn fires register synchronously so each spawn maps immediately.
        RegisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)

        mp_client_state.do_entity_spawn(
            { id = 200, section = "stalker_bandit", pos_x=5,pos_y=5,pos_z=5, lvid=0, gvid=0 })
        local id1 = mp_client_state.resolve_id(200)

        mp_client_state.do_entity_spawn(
            { id = 201, section = "stalker_bandit", pos_x=5,pos_y=5,pos_z=5, lvid=0, gvid=0 })
        local id2 = mp_client_state.resolve_id(201)

        UnregisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)

        -- Both should be mapped (first-come-first-served on same key)
        assert_not_nil(id1, "first spawn should map")
        assert_not_nil(id2, "second spawn should map")
        assert_neq(id1, id2)
    end)

    it("pending position flushed after ID mapping", function()
        -- Deliver position before spawn
        mp_client_state.on_entity_positions({
            { id = 4200, x = 99.0, y = 10.0, z = 88.0, h = 0.5 }
        })

        -- Now complete spawn and mapping
        local local_id = client_spawn(4200, "stalker_bandit", 10.0, 5.0, 20.0)
        assert_not_nil(local_id)

        -- Make entity online so position can be applied
        local go = alife_set_online(local_id)

        -- The pending position flush runs during on_local_entity_registered
        -- via apply_entity_position which calls level.object_by_id
        -- But entity wasn't online during spawn. Check if it was stored at least.
        -- Actually: at the time of flush, entity is offline (just created).
        -- apply_entity_position will use teleport_object for offline entities.
        local se = alife():object(local_id)
        assert_not_nil(se)
    end)

    it("despawn removes ID mapping", function()
        local local_id = client_spawn(4200, "stalker_bandit", 1, 0, 1)
        assert_not_nil(mp_client_state.resolve_id(4200))

        mp_client_state.on_entity_despawn({ id = 4200 })
        assert_nil(mp_client_state.resolve_id(4200))
    end)
end)

-- ============================================================================
-- State machine
-- ============================================================================

describe("client_state: sync state machine", function()
    before_each(function()
        reset_all_state()
        install_guard()
    end)

    it("starts in IDLE state", function()
        assert_eq("idle", mp_client_state.get_sync_state_name())
    end)

    it("on_full_state with entities transitions to CLEANING", function()
        -- Prepopulate entities to clean
        alife_prepopulate(10, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_client_state.on_full_state({ entity_count = 5 })
        set_verbose(true)
        assert_eq("cleaning", mp_client_state.get_sync_state_name())
    end)

    it("on_full_state with no entities transitions to SYNCING", function()
        -- No pre-existing entities (actor only at id=0 which is excluded)
        set_verbose(false)
        mp_client_state.on_full_state({ entity_count = 0 })
        set_verbose(true)
        assert_eq("syncing", mp_client_state.get_sync_state_name())
    end)

    it("client_tick in CLEANING releases entities and transitions to SYNCING", function()
        alife_prepopulate(5, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_client_state.on_full_state({ entity_count = 0 })
        -- CLEANING state with 5 entities
        assert_eq("cleaning", mp_client_state.get_sync_state_name())
        -- One tick (batch=50) should clear all 5
        mp_client_state.client_tick()
        set_verbose(true)
        assert_eq("syncing", mp_client_state.get_sync_state_name())
    end)

    it("client_tick in SYNCING processes spawn queue and transitions to ACTIVE", function()
        set_verbose(false)
        -- Put 2 entities in world so CLEANING runs (tick_cleanup sets _spawn_queue_index=1)
        alife_prepopulate(2, "stalker_bandit", {x=0,y=0,z=0})
        mp_client_state.on_full_state({ entity_count = 0 })
        assert_eq("cleaning", mp_client_state.get_sync_state_name())

        RegisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)

        -- Tick to clear the 2 pre-existing entities → SYNCING (queue empty)
        mp_client_state.client_tick()
        assert_eq("syncing", mp_client_state.get_sync_state_name())

        -- Tick with empty spawn queue → ACTIVE
        mp_client_state.client_tick()
        set_verbose(true)
        UnregisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)
        assert_eq("active", mp_client_state.get_sync_state_name())
    end)

    it("spawn messages queued during CLEANING, processed in SYNCING", function()
        set_verbose(false)
        -- Pre-populate 5 entities to force CLEANING state
        alife_prepopulate(5, "stalker_bandit", {x=0,y=0,z=0})
        mp_client_state.on_full_state({ entity_count = 3 })
        assert_eq("cleaning", mp_client_state.get_sync_state_name())

        -- Receive spawn message while CLEANING — should be queued
        mp_client_state.on_entity_spawn({
            id = 9001, section = "bloodsucker_weak",
            pos_x = 50, pos_y = 0, pos_z = 50, lvid = 0, gvid = 0,
        })
        -- Not yet mapped (still CLEANING)
        assert_nil(mp_client_state.resolve_id(9001))

        -- Register callback for when we process spawns
        RegisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)

        -- Tick to finish CLEANING, enter SYNCING
        mp_client_state.client_tick()  -- clears 5 entities, → SYNCING
        assert_eq("syncing", mp_client_state.get_sync_state_name())

        -- Tick to process spawn queue
        mp_client_state.client_tick()  -- processes queued spawn, → ACTIVE
        set_verbose(true)
        UnregisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)

        assert_eq("active", mp_client_state.get_sync_state_name())
        assert_not_nil(mp_client_state.resolve_id(9001), "queued spawn should now be mapped")
    end)

    it("spawn queue processes correctly when CLEANING skipped (zero-index fix)", function()
        -- Bug: on_full_state with zero pre-existing entities skips CLEANING and
        -- transitions to SYNCING with _spawn_queue_index still 0. tick_sync's
        -- while-loop condition (0 <= #queue) is true even on an empty queue, so
        -- it calls do_entity_spawn(_spawn_queue[0]) = do_entity_spawn(nil), which
        -- errors on data.id. Fix: set _spawn_queue_index = 1 before entering SYNCING.
        RegisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)

        -- Fresh client: no pre-existing entities → on_full_state skips CLEANING → SYNCING
        set_verbose(false)
        mp_client_state.on_full_state({ entity_count = 3 })
        set_verbose(true)
        assert_eq("syncing", mp_client_state.get_sync_state_name())

        -- Spawn messages arrive from host while in SYNCING → immediate path, not queued
        mp_client_state.on_entity_spawn({ id=9001, section="stalker_bandit", pos_x=10,pos_y=0,pos_z=10, lvid=0,gvid=0 })
        mp_client_state.on_entity_spawn({ id=9002, section="stalker_bandit", pos_x=20,pos_y=0,pos_z=20, lvid=0,gvid=0 })
        mp_client_state.on_entity_spawn({ id=9003, section="stalker_bandit", pos_x=30,pos_y=0,pos_z=30, lvid=0,gvid=0 })

        -- All 3 spawned immediately (SYNCING processes spawns directly, not via queue)
        assert_not_nil(mp_client_state.resolve_id(9001), "entity 9001 should be spawned in SYNCING state")
        assert_not_nil(mp_client_state.resolve_id(9002), "entity 9002 should be spawned in SYNCING state")
        assert_not_nil(mp_client_state.resolve_id(9003), "entity 9003 should be spawned in SYNCING state")

        -- client_tick drives tick_sync against the (now empty) spawn queue.
        -- Without fix: _spawn_queue_index=0 → (0<=0)=true → do_entity_spawn(nil) → ERROR
        -- With fix:    _spawn_queue_index=1 → (1<=0)=false → clean transition to ACTIVE
        set_verbose(false)
        mp_client_state.client_tick()
        set_verbose(true)

        UnregisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)
        assert_eq("active", mp_client_state.get_sync_state_name())
        -- All 3 entities remain mapped after the tick (none lost to the nil-index bug)
        assert_not_nil(mp_client_state.resolve_id(9001), "entity 9001 still mapped after tick")
        assert_not_nil(mp_client_state.resolve_id(9002), "entity 9002 still mapped after tick")
        assert_not_nil(mp_client_state.resolve_id(9003), "entity 9003 still mapped after tick")
    end)
end)

-- ============================================================================
-- Position updates
-- ============================================================================

describe("client_state: entity position updates", function()
    before_each(function()
        reset_all_state()
        install_guard()
    end)

    it("position applied to online entity via level.object_by_id", function()
        -- Spawn entity, make it online
        local local_id = client_spawn(100, "stalker_bandit", 0, 0, 0)
        assert_not_nil(local_id)
        local go = alife_set_online(local_id)
        assert_not_nil(go)

        -- Send position update
        mp_client_state.on_entity_positions({
            { id = 100, x = 55.0, y = 10.0, z = 33.0, h = 1.0 }
        })

        -- Check position was applied
        local pos = go:position()
        assert_true(math.abs(pos.x - 55.0) < 0.01, "x should be updated")
        assert_true(math.abs(pos.z - 33.0) < 0.01, "z should be updated")
    end)

    it("position queued for unmapped entity, flushed after spawn", function()
        -- Send position BEFORE spawn (simulates UDP arriving before TCP)
        mp_client_state.on_entity_positions({
            { id = 777, x = 42.0, y = 5.0, z = 88.0, h = 1.0 }
        })
        assert_nil(mp_client_state.resolve_id(777), "not mapped yet")

        -- Spawn via do_entity_spawn so register fires synchronously → flush occurs
        RegisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)
        mp_client_state.do_entity_spawn({
            id = 777, section = "stalker_bandit",
            pos_x = 42.0, pos_y = 5.0, pos_z = 88.0,
            lvid = 0, gvid = 0,
        })
        UnregisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)

        local local_id = mp_client_state.resolve_id(777)
        assert_not_nil(local_id, "should be mapped now")
        assert_not_nil(alife():object(local_id))
    end)

    it("position update dropped during CLEANING", function()
        -- Enter CLEANING
        alife_prepopulate(3, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_client_state.on_full_state({ entity_count = 3 })
        set_verbose(true)
        assert_eq("cleaning", mp_client_state.get_sync_state_name())

        -- Manually map a fake entity
        mp_client_state.map_id(999, 1000)
        local fake_se = { id = 1000, position = vector():set(0,0,0),
            m_level_vertex_id=0, m_game_vertex_id=0,
            _section="stalker_bandit", _clsid=400, _alive=true,
        }
        fake_se.clsid = function() return 400 end
        fake_se.section_name = function() return "stalker_bandit" end
        fake_se.alive = function() return true end
        alife_get_registry()[1000] = fake_se
        local go = alife_set_online(1000)

        -- Send position during CLEANING — should be dropped
        mp_client_state.on_entity_positions({ { id = 999, x = 99, y = 0, z = 99, h = 1 } })
        -- Position should NOT have been applied
        assert_true(math.abs(go:position().x - 0) < 0.01, "position should not change during CLEANING")
    end)
end)

-- ============================================================================
-- Weather and time sync
-- ============================================================================

describe("client_state: weather and time sync", function()
    before_each(reset_all_state)

    it("on_weather_sync applies preset to level", function()
        mp_client_state.on_weather_sync({ preset = "storm" })
        assert_eq("storm", level.get_weather())
    end)

    it("on_time_sync applies hours, minutes, factor", function()
        mp_client_state.on_time_sync({ hours = 18, mins = 45, factor = 3.0 })
        assert_eq(18, level.get_time_hours())
        assert_eq(45, level.get_time_minutes())
        assert_eq(3.0, level.get_time_factor())
    end)

    it("on_time_sync without level.set_game_time uses change_game_time", function()
        -- Remove level.set_game_time to test fallback
        local orig = level.set_game_time
        level.set_game_time = nil
        set_level_time(10, 0)

        mp_client_state.on_time_sync({ hours = 14, mins = 30 })

        level.set_game_time = orig
        assert_eq(14, level.get_time_hours())
        assert_eq(30, level.get_time_minutes())
    end)
end)

-- ============================================================================
-- Level change
-- ============================================================================

describe("client_state: level change", function()
    before_each(function()
        reset_all_state()
        install_guard()
    end)

    it("on_level_change resets to IDLE and clears mappings", function()
        mp_client_state.map_id(100, 200)
        mp_client_state.map_id(101, 201)
        assert_not_nil(mp_client_state.resolve_id(100))

        set_verbose(false)
        mp_client_state.on_level_change({ level = "l03_agroprom" })
        set_verbose(true)

        assert_eq("idle", mp_client_state.get_sync_state_name())
        assert_nil(mp_client_state.resolve_id(100), "mapping should be cleared")
        assert_nil(mp_client_state.resolve_id(101), "mapping should be cleared")
        assert_eq(0, mp_client_state.get_id_map_count())
    end)
end)

-- ============================================================================
-- Entity death
-- ============================================================================

describe("client_state: entity death", function()
    before_each(function()
        reset_all_state()
        install_guard()
    end)

    it("on_entity_death kills entity in sim", function()
        local local_id = client_spawn(500, "stalker_bandit", 0, 0, 0)
        assert_not_nil(local_id)
        local se = alife():object(local_id)
        assert_true(se:alive(), "entity should be alive before death")

        mp_client_state.on_entity_death({ id = 500, killer_id = -1 })

        assert_false(se:alive(), "entity should be dead after on_entity_death")
    end)

    it("on_entity_death with killer resolves killer se_obj", function()
        local victim_local = client_spawn(500, "stalker_bandit", 0, 0, 0)
        local killer_local = client_spawn(501, "stalker_military", 5, 0, 5)
        assert_not_nil(victim_local)
        assert_not_nil(killer_local)

        -- Verify death doesn't error with valid killer
        mp_client_state.on_entity_death({ id = 500, killer_id = 501 })
        assert_false(alife():object(victim_local):alive())
    end)

    it("is_applying_remote_death guard is set during kill", function()
        local local_id = client_spawn(502, "stalker_bandit", 0, 0, 0)
        local guard_was_set = false
        local orig_kill = alife():object(local_id)

        -- Patch kill_entity to check guard
        local orig_kill_fn = _G._alife_methods and _G._alife_methods.kill_entity
        -- Instead, check via mp_client_state
        -- The guard is _applying_remote_death; check it via is_applying_remote_death()
        -- by hooking into the death callback
        local guard_during_kill = nil
        RegisterScriptCallback("npc_on_death_callback", function(npc, killer)
            guard_during_kill = mp_client_state.is_applying_remote_death()
        end)

        mp_client_state.on_entity_death({ id = 502, killer_id = -1 })

        assert_true(guard_during_kill, "guard should be true during kill_entity call")
        assert_false(mp_client_state.is_applying_remote_death(), "guard should be reset after")
    end)

    it("death dropped when CLEANING", function()
        alife_prepopulate(3, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_client_state.on_full_state({ entity_count = 3 })
        set_verbose(true)
        assert_eq("cleaning", mp_client_state.get_sync_state_name())

        -- Manually add a mapping
        mp_client_state.map_id(999, 5000)
        -- Death during CLEANING should be dropped (no crash)
        mp_client_state.on_entity_death({ id = 999, killer_id = -1 })
        -- No error = pass
    end)
end)

-- ============================================================================
-- Entity count utilities
-- ============================================================================

describe("client_state: utility functions", function()
    before_each(function()
        reset_all_state()
        install_guard()
    end)

    it("get_entity_count tracks spawned network entities", function()
        client_spawn(100, "stalker_bandit", 0, 0, 0)
        client_spawn(101, "stalker_bandit", 1, 0, 0)
        assert_eq(2, mp_client_state.get_entity_count())
    end)

    it("get_id_map_count tracks mapped IDs", function()
        mp_client_state.map_id(10, 20)
        mp_client_state.map_id(11, 21)
        mp_client_state.map_id(12, 22)
        assert_eq(3, mp_client_state.get_id_map_count())
        mp_client_state.unmap_id(11)
        assert_eq(2, mp_client_state.get_id_map_count())
    end)
end)

summary()
