-- test_puppet.lua: Puppet NPC lifecycle tests (Commit 5)

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")
dofile(BASE .. "mock/globals.lua")
dofile(BASE .. "mock/engine.lua")
dofile(BASE .. "mock/gns.lua")
dofile(BASE .. "loader.lua")

local SCRIPT_DIR = BASE .. "../lua-sync"
loader_init(SCRIPT_DIR)

-- level.vertex_id is not in the mock (engine-only API).
-- Stub it so spawn_puppet can compute lvid.
if not level.vertex_id then
    level.vertex_id = function(pos) return 0 end
end

local function set_client_mode(on)
    _G.is_mp_client = function() return on end
end

local function install_guard()
    _G.alife_create      = function(...) return alife():create(...) end
    _G.alife_release     = function(se) return alife():release(se, true) end
    _G.alife_release_id  = function(id) local se=alife():object(id); if se then alife():release(se,true) end end
    _G.alife_create_item = function(sec,obj,t) return alife():create(sec, obj, 0, 0) end
    set_verbose(false)
    mp_alife_guard.install()
    set_verbose(true)
end

local function reset_all_state()
    reset_engine()
    reset_gns()
    reset_globals()
    set_verbose(false)
    reset_all()
    set_verbose(true)
    set_client_mode(false)
    set_mock_actor(0, {x=0, y=0, z=0})
end

-- ============================================================================
-- Spawn / despawn basics
-- ============================================================================

describe("puppet: spawn creates entity and tracks it", function()
    before_each(function()
        reset_all_state()
        install_guard()
        set_client_mode(true)
    end)

    it("spawn_puppet registers puppet in both tracking tables", function()
        local pos = vector():set(10, 0, 10)
        mp_puppet.spawn_puppet(1, pos)

        assert_eq(1, mp_puppet.get_puppet_count())

        local ids = mp_puppet.get_puppet_ids()
        local found = false
        for se_id, flag in pairs(ids) do
            if flag == true then found = true end
        end
        assert_true(found, "puppet se_id should be in get_puppet_ids()")
    end)

    it("spawning for same conn_id twice does not duplicate", function()
        local pos = vector():set(5, 0, 5)
        mp_puppet.spawn_puppet(1, pos)
        mp_puppet.spawn_puppet(1, pos)
        assert_eq(1, mp_puppet.get_puppet_count())
    end)

    it("two different conn_ids produce two puppets", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))
        mp_puppet.spawn_puppet(2, vector():set(5, 0, 5))
        assert_eq(2, mp_puppet.get_puppet_count())
    end)
end)

-- ============================================================================
-- Despawn
-- ============================================================================

describe("puppet: despawn removes entity and cleans tables", function()
    before_each(function()
        reset_all_state()
        install_guard()
        set_client_mode(true)
    end)

    it("despawn_puppet empties both tables for that conn_id", function()
        local pos = vector():set(3, 0, 3)
        mp_puppet.spawn_puppet(1, pos)
        assert_eq(1, mp_puppet.get_puppet_count())

        -- Capture se_id before despawn
        local ids_before = {}
        for se_id in pairs(mp_puppet.get_puppet_ids()) do
            ids_before[#ids_before + 1] = se_id
        end
        assert_eq(1, #ids_before)

        mp_puppet.despawn_puppet(1)

        assert_eq(0, mp_puppet.get_puppet_count())

        local ids_after = mp_puppet.get_puppet_ids()
        assert_nil(ids_after[ids_before[1]], "se_id should be removed from puppet_se_ids after despawn")
    end)

    it("despawn removes entity from alife registry", function()
        local pos = vector():set(0, 0, 0)
        mp_puppet.spawn_puppet(1, pos)

        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end
        assert_not_nil(se_id)
        assert_not_nil(alife():object(se_id), "entity should exist before despawn")

        mp_puppet.despawn_puppet(1)

        assert_nil(alife():object(se_id), "entity should be gone after despawn")
    end)

    it("despawn of unknown conn_id is a no-op", function()
        mp_puppet.despawn_puppet(999)  -- no puppet for 999 — should not error
        assert_eq(0, mp_puppet.get_puppet_count())
    end)
end)

-- ============================================================================
-- is_puppet
-- ============================================================================

describe("puppet: is_puppet returns correct values", function()
    before_each(function()
        reset_all_state()
        install_guard()
        set_client_mode(true)
    end)

    it("is_puppet returns true for a spawned puppet se_id", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))

        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end
        assert_not_nil(se_id)

        assert_true(mp_puppet.is_puppet(se_id))
    end)

    it("is_puppet returns false for a non-puppet entity id", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))
        assert_false(mp_puppet.is_puppet(9999))
    end)

    it("is_puppet returns false after the puppet is despawned", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))

        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end

        mp_puppet.despawn_puppet(1)
        assert_false(mp_puppet.is_puppet(se_id))
    end)
end)

-- ============================================================================
-- update_puppet — online entity
-- ============================================================================

describe("puppet: update_puppet applies position to online entity", function()
    before_each(function()
        reset_all_state()
        install_guard()
        set_client_mode(true)
    end)

    it("update_puppet moves game_object when entity is online", function()
        local spawn_pos = vector():set(0, 0, 0)
        mp_puppet.spawn_puppet(1, spawn_pos)

        -- Get the se_id and bring the entity online
        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end
        assert_not_nil(se_id)

        local go = alife_set_online(se_id)
        assert_not_nil(go)

        local new_pos = vector():set(42, 5, 88)
        mp_puppet.update_puppet(1, { pos = new_pos, h = 1.57, bs = 2, mt = 2 })

        local actual = go:position()
        assert_true(math.abs(actual.x - 42) < 0.01, "x should be updated")
        assert_true(math.abs(actual.z - 88) < 0.01, "z should be updated")
    end)

    it("update_puppet sets heading on game_object", function()
        local pos = vector():set(0, 0, 0)
        mp_puppet.spawn_puppet(1, pos)

        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end
        local go = alife_set_online(se_id)

        mp_puppet.update_puppet(1, { h = 3.14 })
        assert_true(math.abs(go._heading - 3.14) < 0.01, "heading should be set")
    end)

    it("update_puppet sets body_state and movement_type", function()
        local pos = vector():set(0, 0, 0)
        mp_puppet.spawn_puppet(1, pos)

        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end
        local go = alife_set_online(se_id)

        mp_puppet.update_puppet(1, { bs = 0, mt = 0 })
        assert_eq(0, go._body_state)
        assert_eq(0, go._move_type)
    end)
end)

-- ============================================================================
-- update_puppet — offline entity (graceful no-op)
-- ============================================================================

describe("puppet: update_puppet handles offline entity gracefully", function()
    before_each(function()
        reset_all_state()
        install_guard()
        set_client_mode(true)
    end)

    it("update_puppet does not error when entity is offline", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))
        -- Entity is offline (we did NOT call alife_set_online)
        -- This must complete without error
        mp_puppet.update_puppet(1, {
            pos = vector():set(10, 0, 10),
            h   = 1.0,
            bs  = 1,
            mt  = 1,
        })
        -- Still tracking the puppet
        assert_eq(1, mp_puppet.get_puppet_count())
    end)

    it("update_puppet caches state while offline for later application", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))

        -- Send update while offline — stored in puppet record
        mp_puppet.update_puppet(1, { h = 2.5 })

        -- Bring online and send another update — heading should apply from fresh data
        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end
        local go = alife_set_online(se_id)

        mp_puppet.update_puppet(1, { h = 1.1 })
        assert_true(math.abs(go._heading - 1.1) < 0.01, "heading should reflect latest update")
    end)

    it("update_puppet for unknown conn_id is a no-op", function()
        mp_puppet.update_puppet(999, { pos = vector():set(1, 0, 1) })
        -- no error = pass
    end)
end)

-- ============================================================================
-- despawn_all
-- ============================================================================

describe("puppet: despawn_all clears everything", function()
    before_each(function()
        reset_all_state()
        install_guard()
        set_client_mode(true)
    end)

    it("despawn_all removes all puppets from tracking tables", function()
        mp_puppet.spawn_puppet(1, vector():set(1, 0, 0))
        mp_puppet.spawn_puppet(2, vector():set(2, 0, 0))
        mp_puppet.spawn_puppet(3, vector():set(3, 0, 0))

        assert_eq(3, mp_puppet.get_puppet_count())

        mp_puppet.despawn_all()

        assert_eq(0, mp_puppet.get_puppet_count())

        local ids = mp_puppet.get_puppet_ids()
        local count = 0
        for _ in pairs(ids) do count = count + 1 end
        assert_eq(0, count, "puppet_se_ids should be empty after despawn_all")
    end)

    it("despawn_all releases all entities from alife", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))
        mp_puppet.spawn_puppet(2, vector():set(5, 0, 0))

        local se_ids = {}
        for id in pairs(mp_puppet.get_puppet_ids()) do
            se_ids[#se_ids + 1] = id
        end
        assert_eq(2, #se_ids)

        mp_puppet.despawn_all()

        for _, id in ipairs(se_ids) do
            assert_nil(alife():object(id), "entity " .. id .. " should be removed from alife")
        end
    end)

    it("despawn_all on empty state is a no-op", function()
        mp_puppet.despawn_all()
        assert_eq(0, mp_puppet.get_puppet_count())
    end)
end)

-- ============================================================================
-- reset
-- ============================================================================

describe("puppet: reset clears state", function()
    before_each(function()
        reset_all_state()
        install_guard()
        set_client_mode(true)
    end)

    it("reset empties tracking tables", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))
        mp_puppet.spawn_puppet(2, vector():set(5, 0, 0))
        assert_eq(2, mp_puppet.get_puppet_count())

        mp_puppet.reset()

        assert_eq(0, mp_puppet.get_puppet_count())

        local ids = mp_puppet.get_puppet_ids()
        local count = 0
        for _ in pairs(ids) do count = count + 1 end
        assert_eq(0, count)
    end)

    it("reset leaves alife entities in place (no release)", function()
        mp_puppet.spawn_puppet(1, vector():set(0, 0, 0))

        local se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do se_id = id end
        assert_not_nil(se_id)
        assert_not_nil(alife():object(se_id), "entity should exist before reset")

        mp_puppet.reset()

        -- reset() does NOT release entities (caller must call despawn_all first)
        assert_not_nil(alife():object(se_id), "entity still in alife after reset (reset only clears tables)")
    end)
end)

-- ============================================================================
-- guard bypass: spawn uses internal_create
-- ============================================================================

describe("puppet: spawn uses internal_create (bypasses alife guard)", function()
    before_each(function()
        reset_all_state()
        install_guard()
    end)

    it("spawn_puppet succeeds even when guard is active in client mode", function()
        -- With the guard installed and client mode on, alife():create() would return nil.
        -- spawn_puppet uses internal_create and must succeed anyway.
        set_client_mode(true)

        local pos = vector():set(10, 0, 10)
        mp_puppet.spawn_puppet(1, pos)

        assert_eq(1, mp_puppet.get_puppet_count(), "puppet should be tracked despite guard blocking normal creates")
    end)

    it("normal alife():create() is blocked while puppet spawn succeeds", function()
        set_client_mode(true)

        -- Confirm the guard really is blocking normal creates
        local blocked = alife():create("stalker_bandit", vector():set(0,0,0), 0, 0)
        assert_nil(blocked, "guard should block normal alife():create() in client mode")

        -- But puppet spawn should still work
        mp_puppet.spawn_puppet(2, vector():set(5, 0, 5))
        assert_eq(1, mp_puppet.get_puppet_count())
    end)
end)

summary()
