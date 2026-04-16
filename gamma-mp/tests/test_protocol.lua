-- test_protocol.lua: Serialization round-trip tests + dispatch routing (Commit 3)

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")
dofile(BASE .. "mock/globals.lua")
dofile(BASE .. "mock/engine.lua")
dofile(BASE .. "mock/gns.lua")
dofile(BASE .. "loader.lua")

local SCRIPT_DIR = BASE .. "../lua-sync"
loader_init(SCRIPT_DIR)

-- Bootstrap: set up global helpers mp_core registers, without actually calling on_game_start
local function setup_globals()
    _G.is_mp_client = function() return false end
    _G.is_mp_host   = function() return false end
    _G.is_mp_active = function() return false end
end

local function reset_all_state()
    reset_engine()
    reset_gns()
    reset_globals()
    setup_globals()
    set_verbose(false)
    reset_all()
    set_verbose(true)
end

-- ============================================================================
-- Helpers to extract the last sent message
-- ============================================================================

local function last_reliable()
    local sent = gns._get_sent_reliable()
    return sent[#sent] and sent[#sent].payload or nil
end

local function last_unreliable()
    local sent = gns._get_sent_unreliable()
    return sent[#sent] and sent[#sent].payload or nil
end

-- ============================================================================
-- Round-trip helpers: use mp_protocol internals via public API
-- We broadcast an event and parse the captured payload back via on_message.
-- ============================================================================

-- Parse a captured payload string using the same logic mp_protocol.deserialize uses.
-- Since deserialize is local, we round-trip via on_message with a tracked dispatch.
local function parse_payload(payload)
    -- Split on | to get msg_type + kv pairs
    local parts = {}
    for part in payload:gmatch("[^|]+") do
        parts[#parts + 1] = part
    end
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
                    entries[#entries+1] = { id=vals[1], x=vals[2], y=vals[3], z=vals[4], h=vals[5] or 1.0 }
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

-- ============================================================================
-- Tests
-- ============================================================================

describe("Protocol: ENTITY_SPAWN serialize/deserialize", function()
    before_each(reset_all_state)

    it("round-trips all fields", function()
        local MSG = mp_protocol.get_msg_types()
        local payload_data = {
            id      = 100,
            section = "stalker_bandit",
            clsid   = 400,
            pos_x   = 10.5,
            pos_y   = 20.0,
            pos_z   = 30.0,
            lvid    = 500,
            gvid    = 100,
        }
        mp_protocol.broadcast_event(MSG.ENTITY_SPAWN, payload_data)
        local payload = last_reliable()
        assert_not_nil(payload)
        assert_contains(payload, "ES|")

        local msg_type, data = parse_payload(payload)
        assert_eq("ES", msg_type)
        assert_eq(100, data.id)
        assert_eq("stalker_bandit", data.section)
        assert_eq(400, data.clsid)
        assert_eq(10.5, data.pos_x)
        assert_eq(20.0, data.pos_y)
        assert_eq(30.0, data.pos_z)
        assert_eq(500, data.lvid)
        assert_eq(100, data.gvid)
    end)

    it("includes parent_id when set", function()
        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_event(MSG.ENTITY_SPAWN, {
            id = 200, section = "wpn_ak74", clsid = 402,
            pos_x = 0, pos_y = 0, pos_z = 0,
            lvid = 0, gvid = 0, parent_id = 150,
        })
        local payload = last_reliable()
        local msg_type, data = parse_payload(payload)
        assert_eq("ES", msg_type)
        assert_eq(150, data.parent_id)
    end)
end)

describe("Protocol: ENTITY_POS batch serialize/deserialize", function()
    before_each(reset_all_state)

    it("round-trips 5 entities", function()
        local MSG = mp_protocol.get_msg_types()
        local entities = {}
        for i = 1, 5 do
            entities[i] = { id = i * 10, x = i * 1.1, y = i * 2.2, z = i * 3.3, h = 0.5 }
        end
        mp_protocol.broadcast_snapshot(MSG.ENTITY_POS, entities)
        local payload = last_unreliable()
        assert_not_nil(payload)
        assert_contains(payload, "EP|")

        local msg_type, data = parse_payload(payload)
        assert_eq("EP", msg_type)
        assert_not_nil(data.entities)
        assert_eq(5, #data.entities)

        for i = 1, 5 do
            local e = data.entities[i]
            assert_eq(i * 10, e.id)
            -- Float precision: compare with tolerance
            assert_true(math.abs(e.x - i * 1.1) < 0.01, "x mismatch at " .. i)
            assert_true(math.abs(e.y - i * 2.2) < 0.01, "y mismatch at " .. i)
            assert_true(math.abs(e.z - i * 3.3) < 0.01, "z mismatch at " .. i)
        end
    end)

    it("handles single entity", function()
        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_snapshot(MSG.ENTITY_POS, {
            { id = 42, x = 100.0, y = 200.0, z = 300.0, h = 1.0 }
        })
        local payload = last_unreliable()
        local msg_type, data = parse_payload(payload)
        assert_eq("EP", msg_type)
        assert_eq(1, #data.entities)
        assert_eq(42, data.entities[1].id)
    end)
end)

describe("Protocol: ENTITY_DEATH serialize/deserialize", function()
    before_each(reset_all_state)

    it("round-trips with killer", function()
        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_event(MSG.ENTITY_DEATH, {
            id = 500, killer_id = 600, pos_x = 1.0, pos_y = 2.0, pos_z = 3.0,
        })
        local payload = last_reliable()
        local msg_type, data = parse_payload(payload)
        assert_eq("ED", msg_type)
        assert_eq(500, data.id)
        assert_eq(600, data.killer_id)
    end)

    it("round-trips without killer (killer_id = -1)", function()
        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_event(MSG.ENTITY_DEATH, {
            id = 501, killer_id = -1,
        })
        local payload = last_reliable()
        local msg_type, data = parse_payload(payload)
        assert_eq("ED", msg_type)
        assert_eq(501, data.id)
        assert_eq(-1, data.killer_id)
    end)
end)

describe("Protocol: WEATHER_SYNC and TIME_SYNC", function()
    before_each(reset_all_state)

    it("WEATHER_SYNC round-trip", function()
        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_event(MSG.WEATHER_SYNC, { preset = "storm" })
        local payload = last_reliable()
        local msg_type, data = parse_payload(payload)
        assert_eq("WS", msg_type)
        assert_eq("storm", data.preset)
    end)

    it("TIME_SYNC round-trip", function()
        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_event(MSG.TIME_SYNC, { hours = 14, mins = 30, factor = 5.0 })
        local payload = last_reliable()
        local msg_type, data = parse_payload(payload)
        assert_eq("TS", msg_type)
        assert_eq(14, data.hours)
        assert_eq(30, data.mins)
        assert_eq(5.0, data.factor)
    end)
end)

describe("Protocol: PLAYER_POS serialize/deserialize", function()
    before_each(reset_all_state)

    it("round-trips player position", function()
        local MSG = mp_protocol.get_msg_types()
        mp_protocol.broadcast_snapshot(MSG.PLAYER_POS, {
            { id = 0, x = 50.0, y = 10.0, z = 75.0, h = 0.8 }
        })
        local payload = last_unreliable()
        local msg_type, data = parse_payload(payload)
        assert_eq("PP", msg_type)
        assert_eq(1, #data.entities)
        assert_eq(0, data.entities[1].id)
        assert_true(math.abs(data.entities[1].x - 50.0) < 0.01)
    end)
end)

describe("Protocol: dispatch routing", function()
    before_each(function()
        reset_all_state()
    end)

    it("ES message while client calls mp_client_state.on_entity_spawn", function()
        -- mp_protocol.on_message checks mp_core.is_client() / mp_core.is_host()
        local orig_is_client = mp_core.is_client
        local orig_is_host   = mp_core.is_host
        mp_core.is_client = function() return true end
        mp_core.is_host   = function() return false end

        local called_with = nil
        local orig = mp_client_state.on_entity_spawn
        mp_client_state.on_entity_spawn = function(data) called_with = data end

        mp_protocol.on_message(1, "ES|id=42|section=stalker_bandit|clsid=400|pos_x=1|pos_y=2|pos_z=3|lvid=0|gvid=0", 100)

        mp_client_state.on_entity_spawn = orig
        mp_core.is_client = orig_is_client
        mp_core.is_host   = orig_is_host

        assert_not_nil(called_with, "on_entity_spawn should have been called")
        assert_eq(42, called_with.id)
        assert_eq("stalker_bandit", called_with.section)
    end)

    it("PP message while host calls mp_host_events.on_client_player_pos", function()
        local orig_is_client = mp_core.is_client
        local orig_is_host   = mp_core.is_host
        mp_core.is_client = function() return false end
        mp_core.is_host   = function() return true end

        local called_conn, called_data = nil, nil
        local orig = mp_host_events.on_client_player_pos
        mp_host_events.on_client_player_pos = function(conn_id, data)
            called_conn = conn_id; called_data = data
        end

        mp_protocol.on_message(2, "PP|1,10.0,20.0,30.0,0.9", 30)

        mp_host_events.on_client_player_pos = orig
        mp_core.is_client = orig_is_client
        mp_core.is_host   = orig_is_host

        assert_eq(2, called_conn)
        assert_not_nil(called_data)
    end)

    it("WS message while client calls mp_client_state.on_weather_sync", function()
        local orig_is_client = mp_core.is_client
        local orig_is_host   = mp_core.is_host
        mp_core.is_client = function() return true end
        mp_core.is_host   = function() return false end

        local called = nil
        local orig = mp_client_state.on_weather_sync
        mp_client_state.on_weather_sync = function(data) called = data end

        mp_protocol.on_message(1, "WS|preset=clear_sky", 20)

        mp_client_state.on_weather_sync = orig
        mp_core.is_client = orig_is_client
        mp_core.is_host   = orig_is_host

        assert_not_nil(called)
        assert_eq("clear_sky", called.preset)
    end)
end)

describe("Protocol: malformed message handling", function()
    before_each(function()
        reset_all_state()
        -- Set client mode via mp_core so dispatch runs (needed for "unknown" warning)
        mp_core.is_client = function() return true end
        mp_core.is_host   = function() return false end
    end)

    it("empty string does not crash", function()
        -- Should return early without error
        mp_protocol.on_message(1, "", 0)
    end)

    it("nil data does not crash", function()
        mp_protocol.on_message(1, nil, 0)
    end)

    it("unknown message type logs warning and does not crash", function()
        set_verbose(false)
        clear_log()
        mp_protocol.on_message(1, "ZZ|foo=bar", 10)
        set_verbose(true)
        -- Should log a warning
        local found = false
        for _, line in ipairs(get_log()) do
            if line:find("Unknown") then found = true end
        end
        assert_true(found, "should log unknown message warning")
    end)

    it("message with no pipe separator does not crash", function()
        mp_protocol.on_message(1, "INVALID_NO_PIPE", 20)
    end)
end)

summary()
