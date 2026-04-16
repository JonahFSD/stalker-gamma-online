-- mock/globals.lua: Engine globals for Lua 5.1 test harness

-- Time
local _mock_time_ms = 0
local _log = {}
local _console_cmds = {}

function time_global()
    return _mock_time_ms
end

function advance_time(ms)
    _mock_time_ms = _mock_time_ms + ms
end

function set_time(ms)
    _mock_time_ms = ms
end

-- printf captures output and optionally prints
local _verbose = true

function printf(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = fmt end
    _log[#_log + 1] = msg
    if _verbose then
        print(msg)
    end
end

function get_log()
    return _log
end

function clear_log()
    _log = {}
end

function set_verbose(v)
    _verbose = v
end

-- news_manager stub
-- NOTE: called with dot notation in scripts: news_manager.send_tip(db.actor, msg, ...)
local _tips = {}
news_manager = {
    send_tip = function(actor, msg, a, b, duration)
        _tips[#_tips + 1] = msg
    end,
    get_tips = function()
        return _tips
    end,
    clear_tips = function()
        _tips = {}
    end,
}

-- exec_console_cmd stub (can be replaced by mp_core)
exec_console_cmd = function(cmd)
    _console_cmds[#_console_cmds + 1] = cmd
end

function get_console_cmds()
    return _console_cmds
end

function clear_console_cmds()
    _console_cmds = {}
end

-- Key constants
DIK_keys = {
    DIK_ESCAPE  = 1,
    DIK_F5      = 63,
    DIK_F10     = 68,
}

-- ui_events constants
ui_events = {
    BUTTON_CLICKED    = 17,
    WINDOW_KEY_PRESSED = 45,
}

-- Frect stub
Frect = function()
    return {
        set = function(self, ...) return self end,
    }
end

-- CScriptXmlInit stub
CScriptXmlInit = function()
    return {
        ParseFile      = function(self, ...) end,
        InitStatic     = function(self, ...) end,
        InitEditBox    = function(self, ...) return {} end,
        Init3tButton   = function(self, ...) return {} end,
        InitWindow     = function(self, ...) return {} end,
        InitFrame      = function(self, ...) return {} end,
        InitScrollView = function(self, ...) return {} end,
    }
end

-- UI stubs
Register_UI   = function() end
Unregister_UI = function() end

-- luabind class/super stubs
class = function() end
super = function() end

-- xbus stub (optional — tests can override)
-- NOTE: called with dot notation: xbus.subscribe(event, handler, tag) — no self
local _xbus_subscriptions = {}
xbus = {
    subscribe = function(event, handler, tag)
        _xbus_subscriptions[tag] = { event = event, handler = handler }
    end,
    unsubscribe = function(event, tag)
        _xbus_subscriptions[tag] = nil
    end,
    get_subscriptions = function()
        return _xbus_subscriptions
    end,
}

-- math.abs already exists in Lua 5.1; ensure it's accessible
-- (no action needed)

-- Reset helper for between tests
function reset_globals()
    _mock_time_ms = 0
    _log = {}
    _console_cmds = {}
    _tips = {}
    _xbus_subscriptions = {}
end
