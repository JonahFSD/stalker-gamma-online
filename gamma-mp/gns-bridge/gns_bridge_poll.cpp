/*
 * GAMMA Multiplayer — GNS Poll Function (raw Lua C API)
 *
 * gns.poll() and gns.poll_events() need to return Lua tables of messages.
 * luabind doesn't handle this well, so we register raw Lua C functions.
 *
 * Add this file to xrGame.vcxproj alongside gns_bridge_luabind.cpp.
 */

#include "stdafx.h"
#include <windows.h>

extern "C" {
#include <lua/lua.h>
#include <lua/lauxlib.h>
}

// Import from gns_bridge.dll (loaded dynamically)
#pragma pack(push, 1)
struct gns_message_t {
    int      conn_id;
    unsigned size;
    unsigned char data[64 * 1024];
    int      reliable;
};

struct gns_connection_event_t {
    int  event_type;
    int  conn_id;
    char info[256];
};
#pragma pack(pop)

typedef int (*pfn_gns_poll)(gns_message_t* messages, int max_messages);
typedef int (*pfn_gns_poll_connection_events)(gns_connection_event_t* events, int max_events);
typedef int (*pfn_gns_get_status)(int conn_id, void* status);

static pfn_gns_poll                    p_poll = nullptr;
static pfn_gns_poll_connection_events  p_poll_events = nullptr;

static void EnsureLoaded()
{
    if (p_poll) return;

    HMODULE hDll = GetModuleHandleA("gns_bridge.dll");
    if (!hDll) return;

    p_poll = (pfn_gns_poll)GetProcAddress(hDll, "gns_poll");
    p_poll_events = (pfn_gns_poll_connection_events)GetProcAddress(hDll, "gns_poll_connection_events");
}

/*
 * gns.poll() -> table of {conn_id=N, data="...", size=N}
 *
 * Called from Lua like:
 *   local messages = gns.poll()
 *   for i, msg in ipairs(messages) do
 *       process_message(msg.conn_id, msg.data, msg.size)
 *   end
 */
static int l_gns_poll(lua_State* L)
{
    EnsureLoaded();
    if (!p_poll)
    {
        lua_newtable(L);
        return 1;
    }

    // Allocate message buffer on stack (up to 16 messages per poll)
    static const int MAX_MSGS = 16;
    static gns_message_t msgs[MAX_MSGS]; // static to avoid 1MB+ stack alloc

    int count = p_poll(msgs, MAX_MSGS);

    lua_newtable(L);
    for (int i = 0; i < count; i++)
    {
        lua_pushinteger(L, i + 1);  // Lua 1-indexed
        lua_newtable(L);

        lua_pushstring(L, "conn_id");
        lua_pushinteger(L, msgs[i].conn_id);
        lua_settable(L, -3);

        lua_pushstring(L, "size");
        lua_pushinteger(L, msgs[i].size);
        lua_settable(L, -3);

        lua_pushstring(L, "data");
        lua_pushlstring(L, (const char*)msgs[i].data, msgs[i].size);
        lua_settable(L, -3);

        lua_settable(L, -3);  // messages[i+1] = msg
    }

    return 1;
}

/*
 * gns.poll_events() -> table of {event_type=N, conn_id=N, info="..."}
 *
 * event_type: 1=connected, 2=disconnected, 3=rejected
 */
static int l_gns_poll_events(lua_State* L)
{
    EnsureLoaded();
    if (!p_poll_events)
    {
        lua_newtable(L);
        return 1;
    }

    static const int MAX_EVENTS = 16;
    static gns_connection_event_t events[MAX_EVENTS];

    int count = p_poll_events(events, MAX_EVENTS);

    lua_newtable(L);
    for (int i = 0; i < count; i++)
    {
        lua_pushinteger(L, i + 1);
        lua_newtable(L);

        lua_pushstring(L, "event_type");
        lua_pushinteger(L, events[i].event_type);
        lua_settable(L, -3);

        lua_pushstring(L, "conn_id");
        lua_pushinteger(L, events[i].conn_id);
        lua_settable(L, -3);

        lua_pushstring(L, "info");
        lua_pushstring(L, events[i].info);
        lua_settable(L, -3);

        lua_settable(L, -3);
    }

    return 1;
}

/*
 * Register raw Lua functions into the existing "gns" table.
 * Call AFTER gns_bridge_script_register() which creates the "gns" table via luabind.
 */
void gns_bridge_poll_register(lua_State* L)
{
    lua_getglobal(L, "gns");
    if (!lua_istable(L, -1))
    {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_setglobal(L, "gns");
        lua_getglobal(L, "gns");
    }

    lua_pushcfunction(L, l_gns_poll);
    lua_setfield(L, -2, "poll");

    lua_pushcfunction(L, l_gns_poll_events);
    lua_setfield(L, -2, "poll_events");

    lua_pop(L, 1); // pop gns table
}
