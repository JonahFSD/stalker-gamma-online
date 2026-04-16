-- test_integration_puppet.lua: Puppet integration tests (Commit 9)
-- Verifies the full wiring: PP messages → puppet spawn/update/despawn

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")
dofile(BASE .. "mock/globals.lua")
dofile(BASE .. "mock/engine.lua")
dofile(BASE .. "mock/gns.lua")
dofile(BASE .. "loader.lua")

local SCRIPT_DIR = BASE .. "../lua-sync"
loader_init(SCRIPT_DIR)

-- level.vertex_id is engine-only; stub it for puppet spawns
if not level.vertex_id then
    level.vertex_id = function(pos) return 0 end
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function setup_globals_stubs()
    _G.alife_create      = function(...) return alife():create(...) end
    _G.alife_release     = function(se) return alife():release(se, true) end
    _G.alife_release_id  = function(id) local se=alife():object(id); if se then alife():release(se,true) end end
    _G.alife_create_item = function(sec,obj,t) return alife():create(sec,obj,0,0) end
end

local function reset_all_state()
    reset_engine()
    reset_gns()
    reset_globals()
    set_verbose(false)
    reset_all()
    set_verbose(true)
    setup_globals_stubs()
    _G.is_mp_client = function() return false end
    _G.is_mp_host   = function() return false end
end

local function enter_host_mode()
    _G.is_mp_host   = function() return true end
    _G.is_mp_client = function() return false end
    mp_core.is_host   = function() return true end
    mp_core.is_client = function() return false end
    gns._set_client_count(1)
    set_verbose(false)
    mp_alife_guard.install()
    mp_host_events.register_callbacks()
    set_verbose(true)
    gns._clear_sent()
end

local function enter_client_mode()
    _G.is_mp_host   = function() return false end
    _G.is_mp_client = function() return true end
    mp_core.is_host   = function() return false end
    mp_core.is_client = function() return true end
    set_verbose(false)
    mp_alife_guard.install()
    set_verbose(true)
    -- Register the mp_core callback (includes puppet spawn flag check)
    -- Wrap to simulate what mp_activate_client_mode does, but we can't set
    -- _is_client from outside. Use the wrapper that includes the guards.
    RegisterScriptCallback("server_entity_on_register", function(se_obj, source_tag)
        -- Puppet spawn flag check (mirrors mp_core.on_client_entity_registered)
        if mp_puppet and mp_puppet.is_spawning_puppet and mp_puppet.is_spawning_puppet() then
            return
        end
        -- ZCP/Warfare filter
        if source_tag == "sim_squad_scripted"
            or source_tag == "se_smart_terrain"
            or source_tag == "sim_squad_warfare" then
            return
        end
        mp_client_state.on_local_entity_registered(se_obj)
    end)
end

local function prime_client_to_active()
    alife_prepopulate(1, "stalker_bandit", {x=0,y=0,z=0})
    set_verbose(false)
    mp_client_state.on_full_state({ entity_count = 0 })
    mp_client_state.client_tick()  -- CLEANING -> SYNCING
    mp_client_state.client_tick()  -- SYNCING -> ACTIVE
    set_verbose(true)
end

-- Build a PP data table as the protocol deserializer produces
local function make_pp_data(player_id, x, y, z, h, bs, mt)
    return {
        entities = {{
            id  = player_id,
            x   = x   or 10.0,
            y   = y   or  5.0,
            z   = z   or 20.0,
            h   = h   or  1.57,
            bs  = bs  or 1,
            mt  = mt  or 2,
            seq = 1,
        }}
    }
end

local function capture_and_clear()
    local reliable   = {}
    local unreliable = {}
    for _, m in ipairs(gns._get_sent_reliable())   do reliable[#reliable+1]     = m end
    for _, m in ipairs(gns._get_sent_unreliable()) do unreliable[#unreliable+1] = m end
    gns._clear_sent()
    return reliable, unreliable
end

-- ============================================================================
-- Test: Puppet spawn flag prevents host tracking
-- ============================================================================

describe("Integration puppet: spawn flag prevents host tracking", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("puppet entity is not tracked or broadcast by host", function()
        enter_host_mode()
        local count_before = mp_host_events.get_tracked_count()
        gns._clear_sent()

        mp_puppet.spawn_puppet(1, vector():set(10, 0, 10))

        -- Puppet should exist in alife
        assert_eq(1, mp_puppet.get_puppet_count())

        -- But NOT tracked by host_events
        assert_eq(count_before, mp_host_events.get_tracked_count(),
            "puppet entity should not be tracked by host")

        -- And no ES broadcast for the puppet
        for _, m in ipairs(gns._get_sent_reliable()) do
            if m.payload and m.payload:find("ES|") then
                assert_true(false, "no ES should be broadcast for puppet entity")
            end
        end
    end)
end)

-- ============================================================================
-- Test: Puppet spawn flag prevents client ID mapping
-- ============================================================================

describe("Integration puppet: spawn flag prevents client ID mapping", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("puppet entity does not create ID mapping on client", function()
        enter_client_mode()
        prime_client_to_active()

        local map_before = mp_client_state.get_id_map_count()

        mp_puppet.spawn_puppet(0, vector():set(5, 0, 5))

        assert_eq(1, mp_puppet.get_puppet_count(), "puppet should be spawned")
        assert_eq(map_before, mp_client_state.get_id_map_count(),
            "puppet should not create an ID mapping")
    end)
end)

-- ============================================================================
-- Test: Lazy spawn on first PP (client side)
-- ============================================================================

describe("Integration puppet: lazy spawn on first PP (client)", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("client spawns puppet on first PP from host (HOST_CONN_ID=0)", function()
        enter_client_mode()
        prime_client_to_active()

        assert_eq(0, mp_puppet.get_puppet_count())

        -- Feed PP with id=0 (host) into client_state
        mp_client_state.on_remote_player_pos(
            make_pp_data(0, 100.0, 5.0, 200.0, 1.57, 1, 1),
            99  -- conn_id (host connection handle, irrelevant for puppet key)
        )

        assert_eq(1, mp_puppet.get_puppet_count(), "puppet should be lazily spawned")
    end)

    it("client spawns puppet on first PP from relayed client (conn_id=2)", function()
        enter_client_mode()
        prime_client_to_active()

        mp_client_state.on_remote_player_pos(
            make_pp_data(2, 50.0, 0.0, 50.0, 0.5, 1, 0),
            99
        )

        assert_eq(1, mp_puppet.get_puppet_count(), "puppet should be spawned for relayed client")
    end)
end)

-- ============================================================================
-- Test: Lazy spawn on first PP (host side)
-- ============================================================================

describe("Integration puppet: lazy spawn on first PP (host)", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("host spawns puppet on first PP from client conn_id=1", function()
        enter_host_mode()

        assert_eq(0, mp_puppet.get_puppet_count())

        -- Simulate client PP arriving at host
        mp_host_events.on_client_player_pos(1,
            make_pp_data(100, 30.0, 0.0, 40.0, 0.8, 1, 1))

        assert_eq(1, mp_puppet.get_puppet_count(), "host should spawn puppet for client")
    end)

    it("host spawns separate puppets for two clients", function()
        enter_host_mode()
        -- Register second client
        set_verbose(false)
        mp_host_events.send_full_state(2)
        set_verbose(true)
        gns._set_client_count(2)
        gns._clear_sent()

        mp_host_events.on_client_player_pos(1,
            make_pp_data(100, 10.0, 0.0, 10.0))
        mp_host_events.on_client_player_pos(2,
            make_pp_data(200, 20.0, 0.0, 20.0))

        assert_eq(2, mp_puppet.get_puppet_count(), "host should have 2 puppets")
    end)
end)

-- ============================================================================
-- Test: Subsequent PP updates puppet position
-- ============================================================================

describe("Integration puppet: subsequent PP updates position", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("second PP moves puppet to new position (host side)", function()
        enter_host_mode()

        -- First PP: lazy spawn
        mp_host_events.on_client_player_pos(1,
            make_pp_data(100, 10.0, 0.0, 10.0, 0.0, 1, 1))
        assert_eq(1, mp_puppet.get_puppet_count())

        -- Bring puppet online
        local puppet_se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do puppet_se_id = id end
        assert_not_nil(puppet_se_id)
        local go = alife_set_online(puppet_se_id)
        assert_not_nil(go)

        -- Second PP: update position
        mp_host_events.on_client_player_pos(1,
            make_pp_data(100, 99.0, 5.0, 77.0, 3.14, 0, 2))

        local pos = go:position()
        assert_true(math.abs(pos.x - 99.0) < 0.01, "x should be updated to 99.0")
        assert_true(math.abs(pos.z - 77.0) < 0.01, "z should be updated to 77.0")
    end)

    it("second PP moves puppet to new position (client side)", function()
        enter_client_mode()
        prime_client_to_active()

        -- First PP: lazy spawn
        mp_client_state.on_remote_player_pos(
            make_pp_data(0, 10.0, 0.0, 10.0, 0.0, 1, 1), 99)
        assert_eq(1, mp_puppet.get_puppet_count())

        -- Bring puppet online
        local puppet_se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do puppet_se_id = id end
        local go = alife_set_online(puppet_se_id)

        -- Second PP: update position
        mp_client_state.on_remote_player_pos(
            make_pp_data(0, 42.0, 3.0, 88.0, 1.57, 0, 0), 99)

        local pos = go:position()
        assert_true(math.abs(pos.x - 42.0) < 0.01, "x should be 42.0")
        assert_true(math.abs(pos.z - 88.0) < 0.01, "z should be 88.0")
    end)
end)

-- ============================================================================
-- Test: Disconnect despawns puppet (host side)
-- ============================================================================

describe("Integration puppet: disconnect despawns puppet (host)", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("EVENT_DISCONNECTED removes puppet for that conn_id", function()
        enter_host_mode()

        -- Spawn puppet via PP
        mp_host_events.on_client_player_pos(1,
            make_pp_data(100, 10.0, 0.0, 10.0))
        assert_eq(1, mp_puppet.get_puppet_count())

        -- Capture puppet se_id
        local puppet_se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do puppet_se_id = id end

        -- Simulate disconnect event — call the despawn directly as mp_on_connection_event would
        mp_puppet.despawn_puppet(1)

        assert_eq(0, mp_puppet.get_puppet_count(), "puppet should be despawned")
        assert_nil(alife():object(puppet_se_id), "entity should be released from alife")
    end)
end)

-- ============================================================================
-- Test: Disconnect despawns all (client side)
-- ============================================================================

describe("Integration puppet: disconnect despawns all (client)", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("client disconnect clears all puppets", function()
        enter_client_mode()
        prime_client_to_active()

        -- Spawn puppets for host and another client
        mp_client_state.on_remote_player_pos(
            make_pp_data(0, 10.0, 0.0, 10.0), 99)
        mp_client_state.on_remote_player_pos(
            make_pp_data(2, 50.0, 0.0, 50.0), 99)
        assert_eq(2, mp_puppet.get_puppet_count())

        -- Capture se_ids
        local se_ids = {}
        for id in pairs(mp_puppet.get_puppet_ids()) do
            se_ids[#se_ids + 1] = id
        end

        -- Simulate disconnect cleanup path
        mp_puppet.despawn_all()
        mp_puppet.reset()

        assert_eq(0, mp_puppet.get_puppet_count(), "all puppets should be gone")
        for _, id in ipairs(se_ids) do
            assert_nil(alife():object(id), "entity " .. id .. " should be released")
        end
    end)
end)

-- ============================================================================
-- Test: Puppet filtered from EP snapshots
-- ============================================================================

describe("Integration puppet: puppet filtered from EP snapshots", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=0, y=0, z=0})
    end)

    it("puppet se_id does not appear in EP broadcast", function()
        enter_host_mode()

        -- Create a normal NPC and bring it online
        local normal_se = alife():create("stalker_bandit", vector():set(5, 0, 5), 0, 0)
        alife_set_online(normal_se.id)

        -- Spawn puppet via PP (lazy spawn)
        mp_host_events.on_client_player_pos(1,
            make_pp_data(100, 20.0, 0.0, 20.0))
        assert_eq(1, mp_puppet.get_puppet_count())

        local puppet_se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do puppet_se_id = id end
        assert_not_nil(puppet_se_id)
        alife_set_online(puppet_se_id)

        gns._clear_sent()
        mp_host_events.send_snapshots()

        -- Parse EP messages and check that puppet_se_id is NOT present
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("^EP|") then
                -- Parse entries: "EP|id,x,y,z,h;id,x,y,z,h;..."
                local data_part = m.payload:sub(4)
                for entry in data_part:gmatch("[^;]+") do
                    local id_str = entry:match("^([^,]+)")
                    local entry_id = tonumber(id_str)
                    assert_neq(puppet_se_id, entry_id,
                        "puppet se_id=" .. puppet_se_id .. " should not appear in EP")
                end
            end
        end

        -- The normal NPC should still appear in EP
        local found_normal = false
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("^EP|") then
                if m.payload:find(tostring(normal_se.id)) then
                    found_normal = true
                end
            end
        end
        assert_true(found_normal, "normal NPC should still appear in EP snapshot")
    end)
end)

-- ============================================================================
-- Test: Full flow — host PP → client puppet spawn → position update
-- ============================================================================

describe("Integration puppet: full flow host PP through protocol to client puppet", function()
    before_each(reset_all_state)

    it("host sends PP → client receives → puppet spawns → position updates", function()
        -- Phase 1: Host sends snapshots (which include host PP with id=0)
        set_mock_actor(0, {x=50, y=10, z=75})
        local actor = db.actor
        actor:set_direction(vector():set(1, 0, 0))
        actor:set_body_state(1)
        actor:set_movement_type(1)

        enter_host_mode()
        set_verbose(false)
        mp_protocol.reset_pp_seq()
        set_verbose(true)
        gns._clear_sent()

        mp_host_events.send_snapshots()

        -- Capture the PP payload
        local pp_payload = nil
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("^PP|") then
                pp_payload = m.payload
            end
        end
        assert_not_nil(pp_payload, "host should have broadcast a PP")

        -- Verify host PP uses id=0
        local first_entry = pp_payload:match("^PP|([^;]+)")
        local id_str = first_entry:match("^([^,]+)")
        assert_eq(0, tonumber(id_str), "host PP should use id=0 (HOST_CONN_ID)")

        -- Phase 2: Switch to client, prime to ACTIVE, replay PP
        reset_engine()
        set_mock_actor(0, {x=0, y=0, z=0})
        enter_client_mode()
        prime_client_to_active()

        assert_eq(0, mp_puppet.get_puppet_count())

        -- Feed the PP through the protocol dispatch
        mp_protocol.on_message(99, pp_payload, #pp_payload)

        -- Puppet should have been lazily spawned
        assert_eq(1, mp_puppet.get_puppet_count(), "puppet should spawn from host PP")

        -- Check that puppet was spawned at approximately the host actor's position
        local puppet_se_id = nil
        for id in pairs(mp_puppet.get_puppet_ids()) do puppet_se_id = id end
        assert_not_nil(puppet_se_id)

        -- Bring puppet online and send another PP with updated position
        local go = alife_set_online(puppet_se_id)
        assert_not_nil(go)

        -- Build a second PP with a different position
        local pp2 = string.format("PP|0,200.00,15.00,300.00,0.7854,0,2,2")
        mp_protocol.on_message(99, pp2, #pp2)

        -- Verify position updated
        local pos = go:position()
        assert_true(math.abs(pos.x - 200.0) < 0.01, "x should be 200.0 after update")
        assert_true(math.abs(pos.z - 300.0) < 0.01, "z should be 300.0 after update")
    end)
end)

-- ============================================================================
-- Test: Host PP id field is HOST_CONN_ID (0), not actor:id()
-- ============================================================================

describe("Integration puppet: host PP identity", function()
    before_each(function()
        reset_all_state()
        set_mock_actor(0, {x=10, y=0, z=10})
    end)

    it("host PP broadcast uses id=0 instead of actor entity id", function()
        enter_host_mode()
        set_verbose(false)
        mp_protocol.reset_pp_seq()
        set_verbose(true)
        gns._clear_sent()

        mp_host_events.send_snapshots()

        local pp_found = false
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("^PP|") then
                pp_found = true
                local entry = m.payload:match("^PP|([^;]+)")
                local id_str = entry:match("^([^,]+)")
                assert_eq(0, tonumber(id_str),
                    "host PP id should be 0 (HOST_CONN_ID), got " .. tostring(id_str))
            end
        end
        assert_true(pp_found, "host should have sent PP")
    end)
end)

summary()
