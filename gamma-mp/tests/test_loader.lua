-- test_loader.lua: Verify script loader works correctly (Commit 2)

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")
dofile(BASE .. "mock/globals.lua")
dofile(BASE .. "mock/engine.lua")
dofile(BASE .. "mock/gns.lua")
dofile(BASE .. "loader.lua")

-- Script dir is one level up from tests/
local SCRIPT_DIR = BASE .. "../lua-sync"
loader_init(SCRIPT_DIR)

describe("Loader: individual script load", function()
    before_each(function()
        reset_engine()
        reset_gns()
        -- Unload all scripts so each test starts clean
        for _, name in ipairs({"mp_alife_guard","mp_client_state","mp_core","mp_host_events","mp_protocol"}) do
            _G[name] = nil
        end
    end)

    it("load mp_protocol without error", function()
        local mod = load_script("mp_protocol")
        assert_not_nil(mod)
        assert_not_nil(_G.mp_protocol)
    end)

    it("mp_protocol.get_msg_types() returns MSG table", function()
        load_script("mp_protocol")
        local MSG = mp_protocol.get_msg_types()
        assert_not_nil(MSG)
        assert_eq("ES", MSG.ENTITY_SPAWN)
        assert_eq("ED", MSG.ENTITY_DEATH)
        assert_eq("ER", MSG.ENTITY_DESPAWN)
        assert_eq("EP", MSG.ENTITY_POS)
        assert_eq("PP", MSG.PLAYER_POS)
        assert_eq("WS", MSG.WEATHER_SYNC)
        assert_eq("TS", MSG.TIME_SYNC)
        assert_eq("FS", MSG.FULL_STATE)
        assert_eq("LC", MSG.LEVEL_CHANGE)
    end)

    it("mp_protocol has send helpers", function()
        load_script("mp_protocol")
        assert_eq("function", type(mp_protocol.send_event))
        assert_eq("function", type(mp_protocol.broadcast_event))
        assert_eq("function", type(mp_protocol.send_snapshot))
        assert_eq("function", type(mp_protocol.broadcast_snapshot))
        assert_eq("function", type(mp_protocol.on_message))
    end)

    it("load mp_alife_guard without error", function()
        load_script("mp_alife_guard")
        assert_not_nil(mp_alife_guard)
        assert_eq("function", type(mp_alife_guard.install))
        assert_eq("function", type(mp_alife_guard.uninstall))
        assert_eq("function", type(mp_alife_guard.internal_create))
        assert_eq("function", type(mp_alife_guard.internal_release))
    end)
end)

describe("Loader: load all 5 scripts", function()
    before_each(function()
        reset_engine()
        reset_gns()
        reset_globals()
        for _, name in ipairs({"mp_alife_guard","mp_client_state","mp_core","mp_host_events","mp_protocol"}) do
            _G[name] = nil
        end
    end)

    it("load_all() loads all scripts without error", function()
        set_verbose(false)
        load_all()
        set_verbose(true)
        assert_not_nil(mp_protocol)
        assert_not_nil(mp_alife_guard)
        assert_not_nil(mp_core)
        assert_not_nil(mp_host_events)
        assert_not_nil(mp_client_state)
    end)

    it("cross-script references resolve after load_all", function()
        set_verbose(false)
        load_all()
        set_verbose(true)
        -- mp_host_events.register_callbacks() references mp_protocol.get_msg_types()
        -- Test: calling get_msg_types from another module context works
        local MSG = mp_protocol.get_msg_types()
        assert_not_nil(MSG.ENTITY_SPAWN)
    end)

    it("reset_all() produces clean module state", function()
        set_verbose(false)
        load_all()
        -- Taint mp_protocol by calling it
        mp_protocol.get_msg_types()
        reset_all()
        set_verbose(true)
        -- After reset, modules exist again (fresh load)
        assert_not_nil(mp_protocol)
        assert_not_nil(mp_client_state)
    end)
end)

summary()
