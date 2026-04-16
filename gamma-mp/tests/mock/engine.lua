-- mock/engine.lua: X-Ray engine API mock for Lua 5.1 test harness
-- Mocks: alife(), level.*, db.*, vector, game_graph(), SIMBOARD, callbacks

-- ============================================================================
-- Callback System
-- ============================================================================

local _callbacks = {}  -- name -> { handler, handler, ... }

function RegisterScriptCallback(name, handler)
    _callbacks[name] = _callbacks[name] or {}
    local list = _callbacks[name]
    -- avoid duplicates
    for _, h in ipairs(list) do
        if h == handler then return end
    end
    list[#list + 1] = handler
end

function UnregisterScriptCallback(name, handler)
    local list = _callbacks[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
            return
        end
    end
end

-- TEST HELPER: fire all registered handlers for a callback
function fire_callback(name, ...)
    local list = _callbacks[name]
    if not list then return end
    for _, h in ipairs(list) do
        h(...)
    end
end

-- TEST HELPER
function get_callback_count(name)
    local list = _callbacks[name]
    return list and #list or 0
end

function reset_callbacks()
    _callbacks = {}
end

-- ============================================================================
-- vector class
-- ============================================================================

local vector_mt = {}
vector_mt.__index = vector_mt

function vector_mt:set(x, y, z)
    self.x = x or 0
    self.y = y or 0
    self.z = z or 0
    return self
end

function vector_mt:__tostring()
    return string.format("vec(%.3f, %.3f, %.3f)", self.x or 0, self.y or 0, self.z or 0)
end

function vector()
    return setmetatable({ x = 0, y = 0, z = 0 }, vector_mt)
end

-- ============================================================================
-- cse_alife_object (mock server entity)
-- ============================================================================

local CLSID_STALKER  = 400
local CLSID_MONSTER  = 401
local CLSID_ITEM     = 402

local function make_se_obj(id, section, pos, lvid, gvid, parent_id, clsid_val)
    local obj = {
        id               = id,
        position         = vector():set(pos.x or 0, pos.y or 0, pos.z or 0),
        m_level_vertex_id = lvid or 0,
        m_game_vertex_id  = gvid or 0,
        parent_id        = parent_id or 65535,
        _section         = section,
        _clsid           = clsid_val or CLSID_STALKER,
        _alive           = true,
    }
    function obj:clsid()        return self._clsid end
    function obj:section_name() return self._section end
    function obj:alive()        return self._alive end
    return obj
end

-- ============================================================================
-- game_object (mock online entity returned by level.object_by_id)
-- ============================================================================

local function make_game_object(se_obj)
    local go = {
        _se         = se_obj,
        _pos        = vector():set(se_obj.position.x, se_obj.position.y, se_obj.position.z),
        _health     = 1.0,
        _alive      = true,
        _body_state = 1,
        _move_type  = 1,
        _heading    = 0,
        _last_anim  = nil,
        _gvid       = se_obj.m_game_vertex_id,
    }
    function go:id()                return self._se.id end
    function go:position()          return self._pos end
    function go:health()            return self._health end
    function go:alive()             return self._alive end
    function go:section()           return self._se._section end
    function go:game_vertex_id()    return self._gvid end
    function go:force_set_position(v)
        self._pos = vector():set(v.x, v.y, v.z)
        -- sync back to se_obj
        self._se.position = self._pos
    end
    function go:set_npc_position(v)   self:force_set_position(v) end
    function go:body_state()          return self._body_state end
    function go:movement_type()       return self._move_type end
    function go:set_body_yaw(h)       self._heading = h end
    function go:set_body_state(bs)    self._body_state = bs end
    function go:set_movement_type(mt) self._move_type = mt end
    function go:set_mental_state(ms)  end
    function go:play_cycle(anim)      self._last_anim = anim end
    return go
end

-- ============================================================================
-- alife() singleton
-- ============================================================================

local _registry = {}      -- id -> se_obj
local _online   = {}      -- id -> game_object (set by test helpers)
local _next_id  = 1000    -- incrementing ID counter

-- The alife object — methods live in a table so mp_alife_guard can patch them
local _alife_methods = {
    set_mp_client_mode = function(self, flag)
        self._mp_client_mode = flag
    end,

    mp_client_mode = function(self)
        return self._mp_client_mode or false
    end,

    object = function(self, id)
        return _registry[id]
    end,

    create = function(self, section, pos, lvid, gvid, parent_id)
        local id = _next_id
        _next_id = _next_id + 1

        -- Determine clsid from section name heuristic
        local clsid_val = CLSID_STALKER
        if section:find("bloodsucker") or section:find("boar") or section:find("pseudodog")
            or section:find("flesh") or section:find("snork") or section:find("zombie_mutant")
            or section:find("chimera") or section:find("burer") or section:find("cat")
            or section:find("controller") or section:find("fracture") or section:find("poltergeist")
            or section:find("psysucker") or section:find("lurker") then
            clsid_val = CLSID_MONSTER
        elseif not (section:find("stalker") or section:find("bandit") or section:find("military")
            or section:find("ecolog") or section:find("freedom") or section:find("duty")
            or section:find("mercenary") or section:find("monolith") or section:find("zombied")) then
            clsid_val = CLSID_ITEM
        end

        local se_obj = make_se_obj(id, section, pos, lvid, gvid, parent_id, clsid_val)
        _registry[id] = se_obj

        -- Fire server_entity_on_register SYNCHRONOUSLY (matches engine behavior)
        fire_callback("server_entity_on_register", se_obj, nil)

        return se_obj
    end,

    release = function(self, se_obj, force)
        if not se_obj then return end
        local id = se_obj.id
        _online[id] = nil
        _registry[id] = nil
        fire_callback("server_entity_on_unregister", se_obj)
    end,

    kill_entity = function(self, se_obj, killer_se)
        if not se_obj then return end
        se_obj._alive = false
        local go = _online[se_obj.id]
        if go then go._alive = false end

        local clsid = se_obj:clsid()
        local killer_go = killer_se and (_online[killer_se.id] or killer_se) or nil

        if clsid == CLSID_STALKER then
            fire_callback("npc_on_death_callback", go or se_obj, killer_go)
        else
            fire_callback("monster_on_death_callback", go or se_obj, killer_go)
        end
    end,

    teleport_object = function(self, id, gvid, lvid, pos)
        local se_obj = _registry[id]
        if not se_obj then return end
        se_obj.m_game_vertex_id   = gvid
        se_obj.m_level_vertex_id  = lvid
        se_obj.position           = vector():set(pos.x, pos.y, pos.z)
        local go = _online[id]
        if go then
            go._pos  = vector():set(pos.x, pos.y, pos.z)
            go._gvid = gvid
        end
    end,

    set_switch_online  = function(self, id, flag) end,
    set_switch_offline = function(self, id, flag) end,
}

-- Save originals BEFORE the table is exposed so reset_alife() can restore them
local _orig_create_fn  = _alife_methods.create
local _orig_release_fn = _alife_methods.release

-- The actual alife singleton — has _alife_methods as its metatable __index TABLE
-- mp_alife_guard Branch 2 requires __index to be a table.
local _alife_mt = { __index = _alife_methods }
local _alife_instance = setmetatable({ _mp_client_mode = false }, _alife_mt)

function alife()
    return _alife_instance
end

-- TEST HELPERS for alife state
function alife_set_online(id)
    local se_obj = _registry[id]
    if not se_obj then return nil end
    local go = make_game_object(se_obj)
    _online[id] = go
    return go
end

function alife_set_offline(id)
    _online[id] = nil
end

function alife_prepopulate(count, section, base_pos)
    -- Add `count` entities directly to registry (bypass callbacks)
    base_pos = base_pos or { x = 0, y = 0, z = 0 }
    section  = section or "stalker_bandit"
    local ids = {}
    for i = 1, count do
        local id = _next_id
        _next_id = _next_id + 1
        local pos = { x = base_pos.x + i, y = base_pos.y, z = base_pos.z }
        _registry[id] = make_se_obj(id, section, pos, i, i, 65535, CLSID_STALKER)
        ids[i] = id
    end
    return ids
end

function alife_get_registry()
    return _registry
end

function reset_alife()
    _registry = {}
    _online   = {}
    _next_id  = 1000
    _alife_instance._mp_client_mode = false

    -- Restore original create/release (mp_alife_guard may have replaced them)
    -- We use the upvalues saved before any patching could occur.
    _alife_methods.create  = _orig_create_fn
    _alife_methods.release = _orig_release_fn

    -- Restore the metatable __index to the (now-restored) methods table.
    -- mp_alife_guard's function-wrapper branch replaces __index itself; put it back.
    _alife_mt.__index = _alife_methods
end

-- ============================================================================
-- level.*
-- ============================================================================

local _current_weather  = "default"
local _time_hours       = 12
local _time_minutes     = 0
local _time_factor      = 1.0
local _level_name       = "l01_escape"
local _level_id         = 1

level = {
    object_by_id = function(id)
        return _online[id]
    end,
    get_weather = function()
        return _current_weather
    end,
    set_weather = function(preset, force)
        _current_weather = preset
    end,
    get_time_hours = function()
        return _time_hours
    end,
    get_time_minutes = function()
        return _time_minutes
    end,
    get_time_factor = function()
        return _time_factor
    end,
    set_time_factor = function(f)
        _time_factor = f
    end,
    set_game_time = function(h, m, s)
        _time_hours   = h
        _time_minutes = m
    end,
    change_game_time = function(d, h, m)
        _time_hours   = _time_hours + h
        _time_minutes = _time_minutes + m
        if _time_minutes >= 60 then
            _time_hours   = _time_hours + math.floor(_time_minutes / 60)
            _time_minutes = _time_minutes % 60
        end
        _time_hours = _time_hours % 24
    end,
    name = function()
        return _level_name
    end,
}

-- TEST HELPERS
function set_level_weather(w) _current_weather = w end
function set_level_time(h, m)
    _time_hours   = h
    _time_minutes = m
end
function set_level_name(n)   _level_name = n end
function set_level_id(id)    _level_id   = id end

function reset_level()
    _current_weather  = "default"
    _time_hours       = 12
    _time_minutes     = 0
    _time_factor      = 1.0
    _level_name       = "l01_escape"
    _level_id         = 1
end

-- ============================================================================
-- db.*
-- ============================================================================

local _actor_go = nil  -- set by tests via set_mock_actor()

db = {
    actor = nil,
}

function set_mock_actor(id, pos)
    pos = pos or { x = 0, y = 0, z = 0 }
    id  = id  or 0
    local se = make_se_obj(id, "actor", pos, 0, 0, 65535, CLSID_STALKER)
    _registry[id] = se
    local go = make_game_object(se)
    _online[id] = go
    db.actor = go
    return go
end

function reset_db()
    db.actor = nil
end

-- ============================================================================
-- game_graph()
-- ============================================================================

local _current_level_id = 1

local _gg_vertex_mt = {}
_gg_vertex_mt.__index = _gg_vertex_mt
function _gg_vertex_mt:level_id() return _current_level_id end

local _game_graph_obj = {
    valid_vertex_id = function(self, gvid)
        return type(gvid) == "number" and gvid >= 0 and gvid < 100000
    end,
    vertex = function(self, gvid)
        return setmetatable({}, _gg_vertex_mt)
    end,
}

function game_graph()
    return _game_graph_obj
end

function set_graph_level_id(id)
    _current_level_id = id
end

-- ============================================================================
-- SIMBOARD
-- ============================================================================

SIMBOARD = {
    _smarts       = {},
    _assignments  = {},
    get_smart_by_name = function(self, name)
        return self._smarts[name]
    end,
    assign_squad_to_smart = function(self, squad, smart)
        self._assignments[#self._assignments + 1] = { squad = squad, smart = smart }
    end,
    add_smart = function(self, name, obj)
        self._smarts[name] = obj or { name = name }
    end,
    get_assignments = function(self)
        return self._assignments
    end,
    reset = function(self)
        self._smarts      = {}
        self._assignments = {}
    end,
}

-- ============================================================================
-- Global reset (call between tests)
-- ============================================================================

function reset_engine()
    reset_alife()
    reset_level()
    reset_db()
    reset_callbacks()
    SIMBOARD:reset()
    _current_level_id = 1
end
