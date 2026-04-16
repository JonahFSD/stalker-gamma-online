-- test_integration.lua: End-to-end flows (Commit 7)
-- Host → wire → client tests using the full stack.

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")
dofile(BASE .. "mock/globals.lua")
dofile(BASE .. "mock/engine.lua")
dofile(BASE .. "mock/gns.lua")
dofile(BASE .. "loader.lua")

local SCRIPT_DIR = BASE .. "../lua-sync"
loader_init(SCRIPT_DIR)

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
    -- No actor by default — tests that need one set it explicitly
    _G.is_mp_client = function() return false end
    _G.is_mp_host   = function() return false end
end

-- Configure as host (sets both _G and mp_core module functions)
local function enter_host_mode()
    _G.is_mp_host   = function() return true end
    _G.is_mp_client = function() return false end
    mp_core.is_host   = function() return true end
    mp_core.is_client = function() return false end
    gns._set_client_count(1)
    set_verbose(false)
    mp_host_events.register_callbacks()
    set_verbose(true)
    gns._clear_sent()
end

-- Configure as client (sets both _G and mp_core module functions)
local function enter_client_mode()
    _G.is_mp_host   = function() return false end
    _G.is_mp_client = function() return true end
    mp_core.is_host   = function() return false end
    mp_core.is_client = function() return true end
    set_verbose(false)
    mp_alife_guard.install()
    set_verbose(true)
    RegisterScriptCallback("server_entity_on_register", mp_client_state.on_local_entity_registered)
end

-- Drive the client sync machine from IDLE → ACTIVE.
-- Uses alife_prepopulate (bypasses create) to force the CLEANING path,
-- which correctly sets _spawn_queue_index=1 before the SYNCING tick.
-- This avoids the zero-index crash in tick_sync on empty queues.
local function prime_client_to_active()
    alife_prepopulate(1, "stalker_bandit", {x=0,y=0,z=0})
    set_verbose(false)
    mp_client_state.on_full_state({ entity_count = 0 })
    mp_client_state.client_tick()  -- CLEANING → SYNCING (releases the 1 entity)
    mp_client_state.client_tick()  -- SYNCING (empty queue, index=1) → ACTIVE
    set_verbose(true)
end

-- Parse a payload string (same logic as mp_protocol.deserialize)
local function parse_payload(payload)
    local parts = {}
    for p in payload:gmatch("[^|]+") do parts[#parts+1] = p end
    if #parts == 0 then return nil, nil end
    local msg_type = parts[1]
    local data = {}
    if msg_type == "EP" or msg_type == "PP" then
        if #parts >= 2 then
            local entries = {}
            for entry in parts[2]:gmatch("[^;]+") do
                local vals = {}
                for v in entry:gmatch("[^,]+") do vals[#vals+1] = tonumber(v) end
                if #vals >= 4 then
                    entries[#entries+1] = {id=vals[1],x=vals[2],y=vals[3],z=vals[4],h=vals[5]}
                end
            end
            data.entities = entries
        end
    else
        for i = 2, #parts do
            local eq = parts[i]:find("=")
            if eq then
                local key = parts[i]:sub(1, eq-1)
                local val = parts[i]:sub(eq+1)
                data[key] = tonumber(val) or val
            end
        end
    end
    return msg_type, data
end

-- Capture all reliable/unreliable payloads, then clear sent queues
local function capture_and_clear()
    local reliable   = {}
    local unreliable = {}
    for _, m in ipairs(gns._get_sent_reliable())   do reliable[#reliable+1]     = m.payload end
    for _, m in ipairs(gns._get_sent_unreliable()) do unreliable[#unreliable+1] = m.payload end
    gns._clear_sent()
    return reliable, unreliable
end

-- Feed payloads into mp_protocol.on_message (as client)
local function replay_messages(payloads)
    for _, payload in ipairs(payloads) do
        if payload then
            mp_protocol.on_message(1, payload, #payload)
        end
    end
end

-- ============================================================================
-- Integration: Full entity lifecycle
-- ============================================================================

describe("Integration: full entity lifecycle (host → wire → client)", function()
    before_each(reset_all_state)

    it("host entity spawn received and mapped on client (ACTIVE state)", function()
        -- Phase 1: Host spawns entity, capture ES
        enter_host_mode()
        local pos = vector():set(100.5, 20.3, 50.7)
        local host_se = alife():create("stalker_bandit", pos, 10, 20)
        local host_id = host_se.id

        local es_reliable, _ = capture_and_clear()
        assert_true(#es_reliable >= 1, "host should have broadcast at least 1 message")

        -- Verify ES content
        local found_es = nil
        for _, p in ipairs(es_reliable) do
            if p:sub(1,3) == "ES|" then found_es = p end
        end
        assert_not_nil(found_es, "should have ES message")
        local msg_type, spawn_data = parse_payload(found_es)
        assert_eq("ES", msg_type)
        assert_eq(host_id, spawn_data.id)
        assert_eq("stalker_bandit", spawn_data.section)

        -- Phase 2: Reset engine, switch to client, prime to ACTIVE, replay ES
        reset_engine()
        set_mock_actor(0, {x=0,y=0,z=0})
        enter_client_mode()
        prime_client_to_active()

        replay_messages(es_reliable)

        -- Phase 3: Assert ID mapping established
        local local_id = mp_client_state.resolve_id(host_id)
        assert_not_nil(local_id, "client should have mapped host_id → local_id")
        assert_not_nil(alife():object(local_id), "local entity should exist")
        assert_eq("stalker_bandit", alife():object(local_id):section_name())
    end)
end)

-- ============================================================================
-- Integration: Position sync flow
-- ============================================================================

describe("Integration: position sync flow", function()
    before_each(reset_all_state)

    it("host snapshot updates entity position on client", function()
        -- Phase 1: Host spawns entity
        enter_host_mode()
        local pos = vector():set(10.0, 5.0, 20.0)
        local host_se = alife():create("stalker_bandit", pos, 0, 0)
        local host_id = host_se.id
        alife_set_online(host_id)

        local es_reliable, _ = capture_and_clear()

        -- Phase 2: Client receives ES, primes to ACTIVE
        reset_engine()
        set_mock_actor(0, {x=0,y=0,z=0})
        enter_client_mode()
        prime_client_to_active()

        replay_messages(es_reliable)
        local local_id = mp_client_state.resolve_id(host_id)
        assert_not_nil(local_id, "entity should be mapped after ES")
        local client_go = alife_set_online(local_id)

        -- Phase 3: Host broadcasts EP with updated position
        mp_core.is_host   = function() return true end
        mp_core.is_client = function() return false end
        gns._clear_sent()

        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_snapshot(MSG.ENTITY_POS, {
            { id = host_id, x = 99.0, y = 10.0, z = 77.0, h = 0.8 }
        })
        local _, ep_unreliable = capture_and_clear()

        -- Phase 4: Client receives EP
        mp_core.is_host   = function() return false end
        mp_core.is_client = function() return true end
        replay_messages(ep_unreliable)

        local updated = client_go:position()
        assert_true(math.abs(updated.x - 99.0) < 0.01, "x should be 99.0")
        assert_true(math.abs(updated.z - 77.0) < 0.01, "z should be 77.0")
    end)
end)

-- ============================================================================
-- Integration: Entity death flow
-- ============================================================================

describe("Integration: entity death flow", function()
    before_each(reset_all_state)

    it("host death event kills entity on client", function()
        -- Phase 1: Host spawns entity and then kills it
        enter_host_mode()
        local pos = vector():set(5.0, 0.0, 5.0)
        local host_se = alife():create("stalker_bandit", pos, 0, 0)
        local host_id = host_se.id
        local go = alife_set_online(host_id)

        local es_reliable, _ = capture_and_clear()

        -- Death event
        mp_host_events.on_npc_death(go, nil)
        local ed_reliable, _ = capture_and_clear()

        -- Verify ED message exists
        local found_ed = false
        for _, p in ipairs(ed_reliable) do
            if p:sub(1,3) == "ED|" then found_ed = true end
        end
        assert_true(found_ed, "host should have sent ED")

        -- Phase 2: Client receives ES, primes to ACTIVE, receives ED
        reset_engine()
        set_mock_actor(0, {x=0,y=0,z=0})
        enter_client_mode()
        prime_client_to_active()

        replay_messages(es_reliable)
        local local_id = mp_client_state.resolve_id(host_id)
        assert_not_nil(local_id, "entity should be mapped before death")
        assert_true(alife():object(local_id):alive(), "entity should be alive before ED")

        replay_messages(ed_reliable)
        assert_false(alife():object(local_id):alive(), "entity should be dead after ED")
    end)
end)

-- ============================================================================
-- Integration: Full state streaming to new client
-- ============================================================================

describe("Integration: full state streaming", function()
    before_each(reset_all_state)

    it("client receives full state and maps all entities (no actor overlap)", function()
        -- Phase 1: Host creates entities (no actor in registry to avoid count confusion)
        local ENTITY_COUNT = 20
        for i = 1, ENTITY_COUNT do
            -- Use alife_prepopulate so no server_entity_on_register fires (bypasses callbacks)
            -- But we need them in registry for build_entity_registry to find them.
            -- Actually let's create via alife():create() but without callbacks registered yet.
            local pos = vector():set(i * 5.0, 0, i * 5.0)
            -- Direct registry insert (alife_prepopulate) avoids triggering any callbacks
        end
        alife_prepopulate(ENTITY_COUNT, "stalker_bandit", {x=0,y=0,z=0})

        enter_host_mode()
        set_verbose(false)
        mp_host_events.build_entity_registry()  -- finds the ENTITY_COUNT entities
        set_verbose(true)
        assert_eq(ENTITY_COUNT, mp_host_events.get_tracked_count())

        -- Stream full state
        gns._clear_sent()
        set_verbose(false)
        mp_host_events.send_full_state(1)   -- header + first batch
        -- Tick enough times to send all entities (50/tick, so 1 tick handles 20)
        mp_host_events.tick_full_state()
        set_verbose(true)

        -- Count ES sent
        local es_count = 0
        local all_reliable = {}
        for _, m in ipairs(gns._get_sent_reliable()) do
            all_reliable[#all_reliable+1] = m.payload
            if m.payload and m.payload:sub(1,3) == "ES|" then es_count = es_count + 1 end
        end
        assert_eq(ENTITY_COUNT, es_count, "should have streamed all entities")

        -- Phase 2: Fresh client receives full state
        reset_engine()
        enter_client_mode()

        -- Prepopulate 1 entity at a position that won't collide with any host entity key.
        -- This forces on_full_state to enter CLEANING mode (not the direct SYNCING path),
        -- which correctly sets _spawn_queue_index=1 before tick_sync runs.
        -- (Without this, the zero-index bug in tick_sync crashes on empty queues.)
        alife_prepopulate(1, "stalker_bandit", {x=999, y=999, z=999})

        -- Replay: FS finds 1 entity → CLEANING; 20 ES messages queued
        replay_messages(all_reliable)

        -- Tick: CLEANING removes the 1 entity → SYNCING (index=1)
        mp_client_state.client_tick()
        -- Tick: SYNCING processes 20 queued spawns (batch=20) → ACTIVE
        mp_client_state.client_tick()

        local mapped = mp_client_state.get_id_map_count()
        assert_eq(ENTITY_COUNT, mapped,
            string.format("should have %d ID mappings, got %d", ENTITY_COUNT, mapped))
    end)
end)

-- ============================================================================
-- Integration: alife guard protects during client mode
-- ============================================================================

describe("Integration: alife guard protects client", function()
    before_each(reset_all_state)

    it("mod alife_create is blocked, internal_create succeeds", function()
        _G.is_mp_client = function() return true end
        mp_core.is_client = function() return true end
        set_verbose(false)
        mp_alife_guard.install()
        set_verbose(true)

        -- 1. Simulate mod calling alife():create() directly → blocked
        local pos = vector():set(0,0,0)
        local blocked = alife():create("stalker_bandit", pos, 0, 0)
        assert_nil(blocked, "alife():create should be blocked in client mode")

        -- 2. Internal bypass succeeds
        local se = mp_alife_guard.internal_create(alife(), "stalker_bandit", pos, 0, 0)
        assert_not_nil(se, "internal_create should succeed regardless")
        assert_eq("stalker_bandit", se:section_name())

        local bc, _ = mp_alife_guard.get_block_counts()
        assert_eq(1, bc, "only the mod's create should be counted")
    end)

    it("global alife_create blocked, no entity created", function()
        _G.is_mp_client = function() return true end
        _G.alife_create = function(...) return alife():create(...) end
        set_verbose(false)
        mp_alife_guard.install()
        set_verbose(true)

        local before = 0
        for _ in pairs(alife_get_registry()) do before = before + 1 end

        _G.alife_create("stalker_bandit", vector():set(0,0,0), 0, 0)

        local after = 0
        for _ in pairs(alife_get_registry()) do after = after + 1 end
        assert_eq(before, after, "no entity should be created when blocked")
    end)
end)

-- ============================================================================
-- Integration: Weather and time sync end-to-end
-- ============================================================================

describe("Integration: environment sync end-to-end", function()
    before_each(reset_all_state)

    it("host weather propagates to client level", function()
        -- Host side: set weather and broadcast
        mp_core.is_host   = function() return true end
        mp_core.is_client = function() return false end
        gns._set_client_count(1)
        set_level_weather("thunder")
        gns._clear_sent()
        mp_host_events.send_environment_sync()

        local reliable, _ = capture_and_clear()

        -- Client side
        reset_engine()
        mp_core.is_client = function() return true end
        mp_core.is_host   = function() return false end
        set_level_weather("default")

        replay_messages(reliable)

        assert_eq("thunder", level.get_weather(), "client weather should match host")
    end)

    it("host time propagates to client level", function()
        mp_core.is_host   = function() return true end
        mp_core.is_client = function() return false end
        gns._set_client_count(1)
        set_level_time(18, 45)
        gns._clear_sent()
        mp_host_events.send_environment_sync()

        local reliable, _ = capture_and_clear()

        reset_engine()
        mp_core.is_client = function() return true end
        mp_core.is_host   = function() return false end
        set_level_time(12, 0)

        replay_messages(reliable)

        assert_eq(18, level.get_time_hours(), "client hours should match host")
        assert_eq(45, level.get_time_minutes(), "client minutes should match host")
    end)
end)

summary()
