-- mock/gns.lua: Mock GNS bridge for Lua 5.1 test harness
-- Captures sent messages, allows injecting events/messages for testing

local _reliable_sent   = {}  -- { conn_id, payload }
local _unreliable_sent = {}
local _event_queue     = {}  -- queued connection events
local _msg_queue       = {}  -- queued incoming messages
local _client_count    = 0
local _is_host         = false
local _is_connected    = false

gns = {

    -- Lifecycle
    init = function()
        return 0
    end,

    shutdown = function()
        _reliable_sent   = {}
        _unreliable_sent = {}
        _event_queue     = {}
        _msg_queue       = {}
        _client_count    = 0
        _is_host         = false
        _is_connected    = false
    end,

    host = function(port)
        _is_host = true
        return 0
    end,

    stop_host = function()
        _is_host      = false
        _client_count = 0
    end,

    connect = function(ip, port)
        _is_connected = true
        return 0
    end,

    disconnect = function()
        _is_connected = false
    end,

    -- Poll (returns queued events/messages, then clears queues)
    poll_events = function()
        local evts = _event_queue
        _event_queue = {}
        return evts
    end,

    poll = function()
        local msgs = _msg_queue
        _msg_queue = {}
        return msgs
    end,

    get_client_count = function()
        return _client_count
    end,

    -- Send (capture for assertions)
    send_reliable = function(conn_id, payload)
        _reliable_sent[#_reliable_sent + 1] = { conn_id = conn_id, payload = payload }
    end,

    send_unreliable = function(conn_id, payload)
        _unreliable_sent[#_unreliable_sent + 1] = { conn_id = conn_id, payload = payload }
    end,
}

-- ============================================================================
-- TEST HELPERS
-- ============================================================================

function gns._inject_event(event_type, info, conn_id)
    _event_queue[#_event_queue + 1] = {
        event_type = event_type,
        info       = info or "",
        conn_id    = conn_id or 1,
    }
end

function gns._inject_message(conn_id, data, size)
    _msg_queue[#_msg_queue + 1] = {
        conn_id = conn_id,
        data    = data,
        size    = size or #data,
    }
end

function gns._get_sent_reliable()
    return _reliable_sent
end

function gns._get_sent_unreliable()
    return _unreliable_sent
end

function gns._clear_sent()
    _reliable_sent   = {}
    _unreliable_sent = {}
end

function gns._set_client_count(n)
    _client_count = n
end

function gns._get_client_count()
    return _client_count
end

function reset_gns()
    gns.shutdown()
    -- shutdown already resets everything
end
