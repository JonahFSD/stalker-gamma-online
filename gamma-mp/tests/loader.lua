-- loader.lua: Loads .script files as module tables
-- Replicates Anomaly's module system: each script's public functions are accessible
-- as _G[scriptname].functionname()

local _script_dir = nil   -- set at init
local _loaded     = {}    -- name -> module env table

local _SCRIPTS = {
    "mp_alife_guard",
    "mp_client_state",
    "mp_core",
    "mp_host_events",
    "mp_protocol",
    "mp_puppet",
    -- mp_ui intentionally excluded
}

-- Set the base directory for .script files
function loader_init(script_dir)
    _script_dir = script_dir
end

-- Load a single .script file into a fresh environment table.
-- The env inherits _G so scripts can see all globals (printf, alife, level, etc.)
-- After loading, _G[name] = env so cross-script calls work: mp_protocol.on_message()
function load_script(name)
    assert(_script_dir, "loader_init() not called")

    local path = _script_dir .. "/" .. name .. ".script"

    -- Create per-script environment that falls through to _G
    local env = setmetatable({}, { __index = _G, __newindex = _G })
    -- We want top-level assignments in the script to land in env, not _G.
    -- But Anomaly scripts access each other via _G[name].func(), so we need
    -- public functions in both env AND _G[name].
    -- Strategy: give the script its own table; after load, expose it as _G[name].

    local mod = {}  -- will hold the script's exported functions

    -- Build environment: reads from _G, writes to mod
    local script_env = setmetatable({}, {
        __index = function(t, k)
            -- Check mod first (own definitions), then _G
            local v = mod[k]
            if v ~= nil then return v end
            return _G[k]
        end,
        __newindex = function(t, k, v)
            mod[k] = v
        end,
    })

    local chunk, err = loadfile(path)
    if not chunk then
        error("load_script: failed to load " .. path .. ": " .. tostring(err))
    end

    setfenv(chunk, script_env)
    local ok, load_err = pcall(chunk)
    if not ok then
        error("load_script: error executing " .. name .. ".script: " .. tostring(load_err))
    end

    _loaded[name] = mod
    _G[name]      = mod  -- expose as global: mp_protocol.on_message(), etc.

    return mod
end

-- Load all testable scripts in dependency order
function load_all()
    for _, name in ipairs(_SCRIPTS) do
        if not _loaded[name] then
            load_script(name)
        else
            -- Already loaded — re-expose to _G in case it was cleared
            _G[name] = _loaded[name]
        end
    end
end

-- Unload a single script: remove from _loaded and _G
function unload_script(name)
    _loaded[name] = nil
    _G[name]      = nil
end

-- Reload all scripts from disk (fresh state — clears all module-level locals)
function reset_all()
    for _, name in ipairs(_SCRIPTS) do
        unload_script(name)
    end
    load_all()
end

function get_loaded()
    return _loaded
end
