/*
 * GAMMA Multiplayer — GNS Bridge Lua Registration
 *
 * Adds to the engine fork (xrGame project). Loads gns_bridge.dll at runtime
 * and exposes all functions to Lua under the "gns" namespace.
 *
 * Add this file to the xrGame VS project and add a call to
 * gns_bridge_script_register(L) in the script registration chain.
 *
 * This file goes in: src/xrGame/gns_bridge_luabind.cpp
 */

#include "stdafx.h"
#include <luabind/luabind.hpp>
#include <windows.h>

// ============================================================================
// Dynamic loading of gns_bridge.dll
// ============================================================================

static HMODULE g_hGnsDll = nullptr;

// Function pointer types matching gns_bridge.h
typedef int    (*pfn_gns_init)(void);
typedef void   (*pfn_gns_shutdown)(void);
typedef int    (*pfn_gns_host)(unsigned short port);
typedef void   (*pfn_gns_stop_host)(void);
typedef int    (*pfn_gns_connect)(const char* ip, unsigned short port);
typedef void   (*pfn_gns_disconnect)(void);
typedef int    (*pfn_gns_send_reliable)(int conn_id, const void* data, unsigned int size);
typedef int    (*pfn_gns_send_unreliable)(int conn_id, const void* data, unsigned int size);
typedef int    (*pfn_gns_is_host)(void);
typedef int    (*pfn_gns_is_client)(void);
typedef int    (*pfn_gns_get_client_count)(void);

// Function pointers
static pfn_gns_init             p_gns_init = nullptr;
static pfn_gns_shutdown         p_gns_shutdown = nullptr;
static pfn_gns_host             p_gns_host = nullptr;
static pfn_gns_stop_host        p_gns_stop_host = nullptr;
static pfn_gns_connect          p_gns_connect = nullptr;
static pfn_gns_disconnect       p_gns_disconnect = nullptr;
static pfn_gns_send_reliable    p_gns_send_reliable = nullptr;
static pfn_gns_send_unreliable  p_gns_send_unreliable = nullptr;
static pfn_gns_is_host          p_gns_is_host = nullptr;
static pfn_gns_is_client        p_gns_is_client = nullptr;
static pfn_gns_get_client_count p_gns_get_client_count = nullptr;

static bool LoadGnsBridge()
{
    if (g_hGnsDll)
        return true;

    g_hGnsDll = LoadLibraryA("gns_bridge.dll");
    if (!g_hGnsDll)
    {
        Msg("! [GAMMA MP] Failed to load gns_bridge.dll");
        return false;
    }

    #define LOAD_PROC(name) \
        p_##name = (pfn_##name)GetProcAddress(g_hGnsDll, #name); \
        if (!p_##name) { Msg("! [GAMMA MP] Missing export: " #name); return false; }

    LOAD_PROC(gns_init)
    LOAD_PROC(gns_shutdown)
    LOAD_PROC(gns_host)
    LOAD_PROC(gns_stop_host)
    LOAD_PROC(gns_connect)
    LOAD_PROC(gns_disconnect)
    LOAD_PROC(gns_send_reliable)
    LOAD_PROC(gns_send_unreliable)
    LOAD_PROC(gns_is_host)
    LOAD_PROC(gns_is_client)
    LOAD_PROC(gns_get_client_count)

    #undef LOAD_PROC

    Msg("* [GAMMA MP] gns_bridge.dll loaded successfully");
    return true;
}

// ============================================================================
// Lua wrapper functions
// ============================================================================

// These adapt the C API to Lua-friendly signatures.
// For messaging, Lua passes strings which have embedded length.

static int lua_gns_init()
{
    if (!LoadGnsBridge())
        return -1;
    return p_gns_init();
}

static void lua_gns_shutdown()
{
    if (p_gns_shutdown) p_gns_shutdown();
}

static int lua_gns_host(int port)
{
    if (!p_gns_host) return -1;
    return p_gns_host((unsigned short)port);
}

static void lua_gns_stop_host()
{
    if (p_gns_stop_host) p_gns_stop_host();
}

static int lua_gns_connect(LPCSTR ip, int port)
{
    if (!p_gns_connect) return -1;
    return p_gns_connect(ip, (unsigned short)port);
}

static void lua_gns_disconnect()
{
    if (p_gns_disconnect) p_gns_disconnect();
}

// Send a Lua string as reliable data
static int lua_gns_send_reliable(int conn_id, LPCSTR data)
{
    if (!p_gns_send_reliable || !data) return -1;
    return p_gns_send_reliable(conn_id, data, (unsigned int)xr_strlen(data));
}

// Send a Lua string as unreliable data
static int lua_gns_send_unreliable(int conn_id, LPCSTR data)
{
    if (!p_gns_send_unreliable || !data) return -1;
    return p_gns_send_unreliable(conn_id, data, (unsigned int)xr_strlen(data));
}

static bool lua_gns_is_host()
{
    return p_gns_is_host && p_gns_is_host() != 0;
}

static bool lua_gns_is_client()
{
    return p_gns_is_client && p_gns_is_client() != 0;
}

static int lua_gns_get_client_count()
{
    if (!p_gns_get_client_count) return 0;
    return p_gns_get_client_count();
}

// ============================================================================
// Poll is special — returns a Lua table of messages
// We handle this with a custom Lua function since luabind can't easily
// return arrays of structs. This gets called from a Lua wrapper.
// ============================================================================

// For poll, we expose a raw Lua C function instead of luabind
// See the Lua-side mp_network.lua which calls this

// ============================================================================
// Registration
// ============================================================================

void gns_bridge_script_register(lua_State* L)
{
    using namespace luabind;

    module(L, "gns")
    [
        def("init",             &lua_gns_init),
        def("shutdown",         &lua_gns_shutdown),
        def("host",             &lua_gns_host),
        def("stop_host",        &lua_gns_stop_host),
        def("connect",          &lua_gns_connect),
        def("disconnect",       &lua_gns_disconnect),
        def("send_reliable",    &lua_gns_send_reliable),
        def("send_unreliable",  &lua_gns_send_unreliable),
        def("is_host",          &lua_gns_is_host),
        def("is_client",        &lua_gns_is_client),
        def("get_client_count", &lua_gns_get_client_count)
    ];
}

/*
 * INTEGRATION NOTES:
 *
 * 1. Add this file to xrGame.vcxproj
 *
 * 2. In the script registration chain (likely script_engine.cpp or wherever
 *    other module registrations happen), add:
 *
 *    extern void gns_bridge_script_register(lua_State* L);
 *    gns_bridge_script_register(L);
 *
 * 3. For gns.poll(), we need a raw Lua C function because luabind doesn't
 *    handle returning arrays of variable-length structs well. The Lua sync
 *    layer (mp_network.lua) handles poll via a C function registered separately,
 *    OR we do the polling in C++ and push results as a Lua table.
 *
 *    For Phase 1, the Lua layer can just call gns.poll() in a tight loop
 *    from actor_on_update callback.
 */
