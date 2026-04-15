/*
 * GAMMA Multiplayer — GNS Lua Binding Registration
 *
 * This file registers the GNS bridge functions into X-Ray Monolith's
 * Lua environment using luabind (the same system all Demonized exes use).
 *
 * This gets compiled INTO the engine fork (added to xrGame project),
 * NOT into the separate gns_bridge.dll. It loads gns_bridge.dll at runtime
 * and exposes its functions to Lua under the "gns" namespace.
 *
 * Alternative approach: If we want to avoid touching xrGame further,
 * we can use LuaJIT FFI from the Lua side to load the DLL directly.
 * See gns_ffi.lua for that approach (RECOMMENDED - zero engine changes).
 */

// ============================================================================
// OPTION A: luabind registration (requires adding this file to xrGame project)
// ============================================================================
/*
#include "stdafx.h"
#include "ai_space.h"
#include "script_engine.h"
#include <luabind/luabind.hpp>

// Forward declarations - these call into gns_bridge.dll via LoadLibrary/GetProcAddress
// ... (implementation would dynamically load the DLL)

// Registration
void gns_script_register(lua_State* L)
{
    using namespace luabind;
    module(L, "gns")
    [
        def("init", &gns_lua_init),
        def("host", &gns_lua_host),
        def("connect", &gns_lua_connect),
        // ... etc
    ];
}
*/

// ============================================================================
// OPTION B (RECOMMENDED): Pure LuaJIT FFI - see gns_ffi.lua
// No engine changes needed. Just drop gns_bridge.dll in bin/ and
// require("gns_ffi") from any Lua script.
// ============================================================================
