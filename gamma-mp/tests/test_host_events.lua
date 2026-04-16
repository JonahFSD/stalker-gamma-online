-- test_host_events.lua: Entity tracking, snapshots, death broadcast, full state (Commit 5)

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
    _G.is_mp_client = function() return false end
    _G.is_mp_host   = function() return true end
    -- mp_client_state guard: is_applying_remote_death() must return false
    -- (mp_client_state is loaded, use its actual function)
end

local function has_reliable_matching(substr)
    for _, m in ipairs(gns._get_sent_reliable()) do
        if m.payload and m.payload:find(substr, 1, true) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- Entity tracking
-- ============================================================================

describe("host_events: build_entity_registry", function()
    before_each(reset_all_state)

    it("scans all pre-existing entities", function()
        -- Pre-populate 100 entities (bypass callbacks)
        alife_prepopulate(100, "stalker_bandit", {x=0,y=0,z=0})
        gns._set_client_count(1)
        set_verbose(false)
        mp_host_events.build_entity_registry()
        set_verbose(true)
        assert_eq(100, mp_host_events.get_tracked_count())
    end)

    it("is idempotent — double build gives correct count", function()
        alife_prepopulate(50, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_host_events.build_entity_registry()
        mp_host_events.build_entity_registry()
        set_verbose(true)
        assert_eq(50, mp_host_events.get_tracked_count())
    end)
end)

describe("host_events: track/untrack (via register callbacks)", function()
    before_each(function()
        reset_all_state()
        gns._set_client_count(1)
        set_verbose(false)
        mp_host_events.register_callbacks()
        set_verbose(true)
        gns._clear_sent()
    end)

    it("on_entity_register tracks entity and count increments", function()
        local pos = vector():set(1,0,1)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        assert_eq(1, mp_host_events.get_tracked_count())
        assert_not_nil(se)
    end)

    it("on_entity_register broadcasts ES when clients present", function()
        local pos = vector():set(5, 0, 5)
        alife():create("stalker_bandit", pos, 0, 0)
        assert_true(has_reliable_matching("ES|"), "should have broadcast ES")
    end)

    it("on_entity_register includes position in broadcast", function()
        local pos = vector():set(12.5, 3.0, 7.75)
        alife():create("stalker_bandit", pos, 10, 20)
        local found = false
        for _, m in ipairs(gns._get_sent_reliable()) do
            if m.payload and m.payload:find("ES|") and
               m.payload:find("12.5") and m.payload:find("7.75") then
                found = true
            end
        end
        assert_true(found, "ES message should contain position")
    end)

    it("no broadcast when 0 clients", function()
        gns._set_client_count(0)
        gns._clear_sent()
        local pos = vector():set(0,0,0)
        alife():create("stalker_bandit", pos, 0, 0)
        assert_false(has_reliable_matching("ES|"), "should NOT broadcast with no clients")
    end)

    it("ZCP source tags: tracked but not broadcast", function()
        gns._clear_sent()
        local pos = vector():set(0,0,0)
        -- Fire callback manually with source_tag
        local se = alife():create("stalker_bandit", pos, 0, 0)
        -- The first create fired the normal callback. Now test filtered source_tag.
        -- Reset and fire manually.
        mp_host_events.unregister_callbacks()
        reset_engine()
        mp_host_events.register_callbacks()
        gns._clear_sent()

        local pos2 = vector():set(0,0,0)
        -- We need to fire server_entity_on_register WITH a source_tag.
        -- Create the se_obj manually without triggering our callback, then fire it.
        local fake_se = { id = 9999, position = pos2,
            m_level_vertex_id = 0, m_game_vertex_id = 0, parent_id = 65535,
            _section = "sim_squad_scripted", _clsid = 400, _alive = true,
        }
        fake_se.clsid        = function(self) return self._clsid end
        fake_se.section_name = function(self) return self._section end
        fake_se.alive        = function(self) return self._alive end

        fire_callback("server_entity_on_register", fake_se, "sim_squad_scripted")

        -- Should be tracked
        assert_eq(1, mp_host_events.get_tracked_count())
        -- Should NOT be broadcast
        assert_false(has_reliable_matching("ES|"), "ZCP entities should not be broadcast")
    end)

    it("on_entity_unregister untracks entity and broadcasts ER", function()
        local pos = vector():set(0,0,0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        assert_eq(1, mp_host_events.get_tracked_count())
        gns._clear_sent()

        alife():release(se, true)
        assert_eq(0, mp_host_events.get_tracked_count())
        assert_true(has_reliable_matching("ER|"), "should broadcast ER on despawn")
    end)

    it("swap-remove maintains contiguous array", function()
        -- Track 5 entities, untrack the middle one, check count
        local ids = {}
        for i = 1, 5 do
            local pos = vector():set(i, 0, 0)
            local se = alife():create("stalker_bandit", pos, 0, 0)
            ids[i] = se
        end
        assert_eq(5, mp_host_events.get_tracked_count())

        gns._clear_sent()
        -- Release the 3rd entity
        alife():release(ids[3], true)
        assert_eq(4, mp_host_events.get_tracked_count())
    end)
end)

-- ============================================================================
-- Death broadcasting
-- ============================================================================

describe("host_events: death broadcasting", function()
    before_each(function()
        reset_all_state()
        gns._set_client_count(1)
        set_verbose(false)
        mp_host_events.register_callbacks()
        set_verbose(true)
        gns._clear_sent()
    end)

    it("on_npc_death broadcasts ENTITY_DEATH", function()
        local pos = vector():set(0,0,0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        local go = alife_set_online(se.id)
        gns._clear_sent()

        -- Simulate death callback (npc_on_death_callback fired with game_object)
        local mock_killer = { id = function() return 0 end }
        mp_host_events.on_npc_death(go, mock_killer)

        assert_true(has_reliable_matching("ED|"), "should broadcast ED on death")
    end)

    it("death message includes entity id and killer_id", function()
        local pos = vector():set(0,0,0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        local go = alife_set_online(se.id)
        gns._clear_sent()

        local killer_go = { id = function() return 777 end }
        mp_host_events.on_npc_death(go, killer_go)

        local found = false
        for _, m in ipairs(gns._get_sent_reliable()) do
            if m.payload and m.payload:find("ED|") and
               m.payload:find("killer_id=777") then
                found = true
            end
        end
        assert_true(found, "ED message should contain killer_id")
    end)

    it("death skipped when is_applying_remote_death() is true", function()
        -- Simulate mp_client_state guard
        local orig = mp_client_state.is_applying_remote_death
        mp_client_state.is_applying_remote_death = function() return true end

        local pos = vector():set(0,0,0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        local go = alife_set_online(se.id)
        gns._clear_sent()

        mp_host_events.on_npc_death(go, nil)

        mp_client_state.is_applying_remote_death = orig

        assert_false(has_reliable_matching("ED|"), "should NOT broadcast when applying remote death")
    end)

    it("no death broadcast when 0 clients", function()
        gns._set_client_count(0)
        local pos = vector():set(0,0,0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        local go = alife_set_online(se.id)
        gns._clear_sent()
        mp_host_events.on_npc_death(go, nil)
        assert_false(has_reliable_matching("ED|"))
    end)
end)

-- ============================================================================
-- Environment sync
-- ============================================================================

describe("host_events: environment sync", function()
    before_each(function()
        reset_all_state()
        gns._set_client_count(1)
        set_verbose(false)
        mp_host_events.register_callbacks()
        set_verbose(true)
        gns._clear_sent()
    end)

    it("send_environment_sync broadcasts WS and TS", function()
        set_level_weather("storm")
        set_level_time(14, 30)
        mp_host_events.send_environment_sync()
        assert_true(has_reliable_matching("WS|"), "should send WS")
        assert_true(has_reliable_matching("TS|"), "should send TS")
    end)

    it("WS message contains weather preset", function()
        set_level_weather("clear_sky")
        mp_host_events.send_environment_sync()
        local found = false
        for _, m in ipairs(gns._get_sent_reliable()) do
            if m.payload and m.payload:find("WS|") and m.payload:find("preset=clear_sky") then
                found = true
            end
        end
        assert_true(found)
    end)
end)

-- ============================================================================
-- Position snapshots
-- ============================================================================

describe("host_events: send_snapshots round-robin", function()
    before_each(function()
        reset_all_state()
        gns._set_client_count(1)
        set_verbose(false)
        mp_host_events.register_callbacks()
        set_verbose(true)
        gns._clear_sent()
        set_mock_actor(0, {x=0,y=0,z=0})
    end)

    it("sends EP snapshot with online entities (up to 100)", function()
        -- Create and bring online 10 entities
        for i = 1, 10 do
            local pos = vector():set(i, 0, 0)
            local se = alife():create("stalker_bandit", pos, 0, 0)
            alife_set_online(se.id)
        end
        gns._clear_sent()

        mp_host_events.send_snapshots()

        -- Should have sent at least one unreliable EP message
        local sent = gns._get_sent_unreliable()
        local found = false
        for _, m in ipairs(sent) do
            if m.payload and m.payload:find("EP|") then found = true end
        end
        assert_true(found, "should have sent EP snapshot")
    end)

    it("caps snapshot at 100 entities per call", function()
        -- Create 250 entities, all online
        for i = 1, 250 do
            local pos = vector():set(i, 0, 0)
            local se = alife():create("stalker_bandit", pos, 0, 0)
            alife_set_online(se.id)
        end
        gns._clear_sent()
        mp_host_events.send_snapshots()

        -- Parse EP message to count entities
        local total = 0
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("EP|") then
                for _ in m.payload:gmatch(";") do total = total + 1 end
                total = total + 1  -- one more than semicolons
            end
        end
        assert_true(total <= 100, "snapshot should cap at 100 entities, got " .. total)
        assert_true(total > 0, "should have sent at least 1 entity")
    end)

    it("round-robin advances cursor across multiple calls", function()
        -- Create 200 entities, all online
        for i = 1, 200 do
            local pos = vector():set(i, 0, 0)
            local se = alife():create("stalker_bandit", pos, 0, 0)
            alife_set_online(se.id)
        end

        -- First call — get entity IDs seen
        gns._clear_sent()
        mp_host_events.send_snapshots()
        local first_payload = nil
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("EP|") then first_payload = m.payload end
        end

        -- Second call — cursor should have advanced, different slice
        gns._clear_sent()
        mp_host_events.send_snapshots()
        local second_payload = nil
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("EP|") then second_payload = m.payload end
        end

        -- They should be different (cursor advanced)
        assert_not_nil(first_payload)
        assert_not_nil(second_payload)
        assert_neq(first_payload, second_payload)
    end)
end)

-- ============================================================================
-- Full state streaming
-- ============================================================================

describe("host_events: full state streaming", function()
    before_each(function()
        reset_all_state()
        gns._set_client_count(1)
        set_verbose(false)
        mp_host_events.register_callbacks()
        set_verbose(true)
        gns._clear_sent()
    end)

    it("send_full_state sends FS header immediately", function()
        alife_prepopulate(10, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_host_events.build_entity_registry()
        set_verbose(true)
        gns._clear_sent()

        set_verbose(false)
        mp_host_events.send_full_state(1)
        set_verbose(true)

        assert_true(has_reliable_matching("FS|"), "should send FS header")
    end)

    it("tick_full_state streams entities in batches and completes", function()
        -- Prepopulate 120 entities (>50 batch = requires multiple ticks)
        alife_prepopulate(120, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_host_events.build_entity_registry()
        gns._clear_sent()
        mp_host_events.send_full_state(1)  -- sends FS header + first 50 immediately
        set_verbose(true)

        -- Count ES messages so far
        local function count_es()
            local n = 0
            for _, m in ipairs(gns._get_sent_reliable()) do
                if m.payload and m.payload:find("^ES|") then n = n + 1 end
            end
            return n
        end

        -- First batch was sent in send_full_state call itself
        local after_first = count_es()
        assert_true(after_first >= 50, "first batch should have sent 50 entities")

        -- Drive remaining
        set_verbose(false)
        mp_host_events.tick_full_state()  -- second batch
        mp_host_events.tick_full_state()  -- third (completes remaining 20 + WS + TS)
        set_verbose(true)

        local total = count_es()
        assert_eq(120, total, "should have sent all 120 entities total")
    end)

    it("cancel_full_state stops streaming", function()
        alife_prepopulate(200, "stalker_bandit", {x=0,y=0,z=0})
        set_verbose(false)
        mp_host_events.build_entity_registry()
        gns._clear_sent()
        mp_host_events.send_full_state(1)
        mp_host_events.cancel_full_state(1)
        -- Count ES before cancel
        local before = 0
        for _, m in ipairs(gns._get_sent_reliable()) do
            if m.payload and m.payload:find("^ES|") then before = before + 1 end
        end
        -- Tick — should do nothing (cancelled)
        mp_host_events.tick_full_state()
        mp_host_events.tick_full_state()
        set_verbose(true)

        local after = 0
        for _, m in ipairs(gns._get_sent_reliable()) do
            if m.payload and m.payload:find("^ES|") then after = after + 1 end
        end
        assert_eq(before, after, "tick after cancel should not send more entities")
    end)
end)

-- ============================================================================
-- Host PLAYER_POS snapshot — extended fields
-- ============================================================================

describe("host_events: host PLAYER_POS extended fields", function()
    -- Helper: find the PP unreliable payload and parse the first entry's fields.
    -- PP wire format: "PP|id,x,y,z,h,bs,mt,seq;..."
    -- Returns array of numbers [id, x, y, z, heading, bs, mt, seq] or nil.
    local function get_pp_fields()
        for _, m in ipairs(gns._get_sent_unreliable()) do
            if m.payload and m.payload:find("^PP|") then
                local entry = m.payload:match("^PP|([^;]+)")
                if entry then
                    local vals = {}
                    for v in entry:gmatch("[^,]+") do
                        vals[#vals + 1] = tonumber(v)
                    end
                    return vals  -- [1]=id [2]=x [3]=y [4]=z [5]=heading [6]=bs [7]=mt [8]=seq
                end
            end
        end
        return nil
    end

    before_each(function()
        reset_all_state()
        gns._set_client_count(1)
        set_verbose(false)
        mp_host_events.register_callbacks()
        mp_protocol.reset_pp_seq()
        set_verbose(true)
        gns._clear_sent()
    end)

    it("host PP includes heading derived from actor:direction()", function()
        local actor = set_mock_actor(0, {x=0, y=0, z=0})
        -- direction (1,0,0) → heading = math.atan2(1,0) = π/2
        actor:set_direction(vector():set(1, 0, 0))

        mp_host_events.send_snapshots()

        local vals = get_pp_fields()
        assert_not_nil(vals, "PP message not found")
        assert_not_nil(vals[5], "heading field missing")
        local expected = math.atan2(1, 0)
        assert_true(math.abs(vals[5] - expected) < 0.001,
            string.format("heading: expected ~%.4f, got %.4f", expected, vals[5]))
    end)

    it("host PP includes body_state and movement_type", function()
        local actor = set_mock_actor(0, {x=0, y=0, z=0})
        actor:set_body_state(1)     -- stand
        actor:set_movement_type(2)  -- standing

        mp_host_events.send_snapshots()

        local vals = get_pp_fields()
        assert_not_nil(vals, "PP message not found")
        assert_eq(1, vals[6], "body_state field")
        assert_eq(2, vals[7], "movement_type field")
    end)
end)

summary()
