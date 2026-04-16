-- test_alife_guard.lua: Metatable patching, blocking, bypass, globals (Commit 4)

local BASE = debug.getinfo(1, "S").source:match("@(.+[\\/])") or "./"
dofile(BASE .. "framework.lua")
dofile(BASE .. "mock/globals.lua")
dofile(BASE .. "mock/engine.lua")
dofile(BASE .. "mock/gns.lua")
dofile(BASE .. "loader.lua")

local SCRIPT_DIR = BASE .. "../lua-sync"
loader_init(SCRIPT_DIR)

-- mp_alife_guard checks _G.is_mp_client() for the client_check()
-- We control client mode via this global.
local function set_client_mode(on)
    _G.is_mp_client = function() return on end
end

local function reset_all_state()
    reset_engine()
    reset_gns()
    reset_globals()
    set_verbose(false)
    reset_all()
    set_verbose(true)
    set_client_mode(false)

    -- Provide global stubs that alife_guard layer 2 needs
    _G.alife_create      = function(...) return alife():create(...) end
    _G.alife_release     = function(se, msg) return alife():release(se, true) end
    _G.alife_release_id  = function(id, msg)
        local se = alife():object(id)
        if se then alife():release(se, true) end
    end
    _G.alife_create_item = function(sec, obj, t) return alife():create(sec, obj, 0, 0) end
end

describe("alife_guard: install", function()
    before_each(reset_all_state)

    it("install() returns true (metatable patch succeeds)", function()
        local ok = mp_alife_guard.install()
        assert_true(ok, "install should return true with proper metatable")
    end)

    it("is_installed() returns true after install()", function()
        mp_alife_guard.install()
        assert_true(mp_alife_guard.is_installed())
    end)

    it("metatable __index is still a table after install", function()
        mp_alife_guard.install()
        local mt = getmetatable(alife())
        assert_not_nil(mt)
        assert_eq("table", type(mt.__index))
    end)

    it("alife() still works normally after install (not client mode)", function()
        mp_alife_guard.install()
        set_client_mode(false)
        local pos = vector():set(1, 2, 3)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        assert_not_nil(se, "create should succeed when not in client mode")
        assert_eq("stalker_bandit", se:section_name())
    end)
end)

describe("alife_guard: blocking", function()
    before_each(reset_all_state)

    it("create is blocked when client mode active", function()
        mp_alife_guard.install()
        set_client_mode(true)
        local pos = vector():set(0, 0, 0)
        local result = alife():create("stalker_bandit", pos, 0, 0)
        assert_nil(result, "create should return nil in client mode")
    end)

    it("block count increments on each blocked create", function()
        mp_alife_guard.install()
        set_client_mode(true)
        local pos = vector():set(0, 0, 0)
        alife():create("stalker_bandit", pos, 0, 0)
        alife():create("stalker_bandit", pos, 0, 0)
        alife():create("stalker_bandit", pos, 0, 0)
        local bc, br = mp_alife_guard.get_block_counts()
        assert_eq(3, bc)
    end)

    it("create passes through when NOT client mode", function()
        mp_alife_guard.install()
        set_client_mode(false)
        local pos = vector():set(5, 5, 5)
        local se = alife():create("bloodsucker_weak", pos, 1, 1)
        assert_not_nil(se)
        assert_eq("bloodsucker_weak", se:section_name())
    end)

    it("release is blocked in client mode", function()
        mp_alife_guard.install()
        -- Create BEFORE client mode
        set_client_mode(false)
        local pos = vector():set(0, 0, 0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        local id = se.id
        assert_not_nil(alife():object(id), "entity should exist")

        -- Now activate client mode and try to release
        set_client_mode(true)
        alife():release(se, true)
        -- Entity should still exist (release was blocked)
        assert_not_nil(alife():object(id), "entity should still exist after blocked release")

        local bc, br = mp_alife_guard.get_block_counts()
        assert_eq(1, br)
    end)
end)

describe("alife_guard: bypass (internal_create / internal_release)", function()
    before_each(reset_all_state)

    it("internal_create bypasses guard in client mode", function()
        mp_alife_guard.install()
        set_client_mode(true)

        local sim = alife()
        local pos = vector():set(10, 0, 10)
        local se = mp_alife_guard.internal_create(sim, "stalker_bandit", pos, 0, 0)
        assert_not_nil(se, "internal_create should succeed even in client mode")
        assert_eq("stalker_bandit", se:section_name())

        -- Block count should NOT have incremented (bypass doesn't count)
        local bc, _ = mp_alife_guard.get_block_counts()
        assert_eq(0, bc)
    end)

    it("internal_release bypasses guard in client mode", function()
        mp_alife_guard.install()
        -- Create in host mode
        set_client_mode(false)
        local pos = vector():set(0, 0, 0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        local id = se.id
        assert_not_nil(alife():object(id))

        -- Switch to client mode and release via bypass
        set_client_mode(true)
        mp_alife_guard.internal_release(alife(), se, true)
        assert_nil(alife():object(id), "entity should be gone after internal_release")
    end)
end)

describe("alife_guard: global overrides", function()
    before_each(reset_all_state)

    it("alife_create blocked in client mode", function()
        mp_alife_guard.install()
        set_client_mode(true)
        local pos = vector():set(0, 0, 0)
        local result = _G.alife_create("stalker_bandit", pos, 0, 0, nil, nil)
        assert_nil(result, "global alife_create should be blocked")
        local bc, _ = mp_alife_guard.get_block_counts()
        assert_true(bc >= 1)
    end)

    it("alife_release blocked in client mode", function()
        mp_alife_guard.install()
        set_client_mode(false)
        local pos = vector():set(0, 0, 0)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        local id = se.id

        set_client_mode(true)
        _G.alife_release(se, "test")
        -- entity still exists (blocked)
        assert_not_nil(alife():object(id))
    end)

    it("alife_create_item blocked in client mode", function()
        mp_alife_guard.install()
        set_client_mode(true)
        local pos = vector():set(0, 0, 0)
        local result = _G.alife_create_item("wpn_ak74", pos, nil)
        assert_nil(result)
        local bc, _ = mp_alife_guard.get_block_counts()
        assert_true(bc >= 1)
    end)

    it("global wrappers pass through when not client mode", function()
        mp_alife_guard.install()
        set_client_mode(false)
        local pos = vector():set(1, 1, 1)
        local result = _G.alife_create("stalker_bandit", pos, 0, 0, nil, nil)
        assert_not_nil(result, "alife_create should succeed when not in client mode")
    end)
end)

describe("alife_guard: idempotent install", function()
    before_each(reset_all_state)

    it("calling install() twice does not error", function()
        mp_alife_guard.install()
        mp_alife_guard.install()  -- second call — should be no-op
        assert_true(mp_alife_guard.is_installed())
    end)

    it("guard still works correctly after double install", function()
        mp_alife_guard.install()
        mp_alife_guard.install()
        set_client_mode(true)
        local pos = vector():set(0, 0, 0)
        local result = alife():create("stalker_bandit", pos, 0, 0)
        assert_nil(result, "guard should still block after double install")
    end)
end)

describe("alife_guard: uninstall", function()
    before_each(reset_all_state)

    it("uninstall removes guard — create works in client mode after uninstall", function()
        mp_alife_guard.install()
        set_client_mode(true)

        -- Should be blocked
        local pos = vector():set(0, 0, 0)
        local blocked = alife():create("stalker_bandit", pos, 0, 0)
        assert_nil(blocked, "should be blocked before uninstall")

        mp_alife_guard.uninstall()
        assert_false(mp_alife_guard.is_installed())

        -- After uninstall, create goes through (client mode is still on but guard is gone)
        local se = alife():create("stalker_bandit", pos, 0, 0)
        assert_not_nil(se, "should succeed after uninstall")
    end)
end)

summary()
