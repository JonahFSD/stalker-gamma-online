/*
 * GAMMA Multiplayer — GNS Bridge DLL
 *
 * Wraps Valve's GameNetworkingSockets library and exposes a flat C API
 * that can be called from X-Ray Monolith's Lua layer via luabind or FFI.
 *
 * This DLL is a thin pipe — no game logic. All multiplayer logic lives in Lua.
 *
 * Build: Visual Studio 2022, link against GameNetworkingSockets.lib
 * Output: gns_bridge.dll -> drop into Anomaly/bin/
 */

#pragma once

#ifdef GNS_BRIDGE_EXPORTS
#define GNS_API __declspec(dllexport)
#else
#define GNS_API __declspec(dllimport)
#endif

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Initialization
// ============================================================================

// Initialize GameNetworkingSockets library. Call once at startup.
// Returns 0 on success, -1 on failure.
GNS_API int gns_init(void);

// Shutdown GameNetworkingSockets library. Call once at exit.
GNS_API void gns_shutdown(void);

// ============================================================================
// Host (Server) API
// ============================================================================

// Start listening for connections on the given port.
// Returns 0 on success, -1 on failure.
GNS_API int gns_host(uint16_t port);

// Stop hosting and close all connections.
GNS_API void gns_stop_host(void);

// ============================================================================
// Client API
// ============================================================================

// Connect to a host at ip:port. ip is a string like "192.168.1.100".
// Returns 0 on success (connection initiated), -1 on failure.
GNS_API int gns_connect(const char* ip, uint16_t port);

// Disconnect from the host.
GNS_API void gns_disconnect(void);

// ============================================================================
// Messaging
// ============================================================================

// Send data reliably (ordered, guaranteed delivery). For events.
// Returns 0 on success, -1 on failure.
// conn_id: 0 = send to host (client mode), or specific connection (host mode)
//          -1 = broadcast to all connections (host mode)
GNS_API int gns_send_reliable(int32_t conn_id, const void* data, uint32_t size);

// Send data unreliably (unordered, may be dropped). For snapshots.
// Same conn_id semantics as gns_send_reliable.
GNS_API int gns_send_unreliable(int32_t conn_id, const void* data, uint32_t size);

// ============================================================================
// Polling
// ============================================================================

// Maximum message size we'll handle
#define GNS_MAX_MESSAGE_SIZE (1024 * 64)  // 64 KB
#define GNS_MAX_POLL_MESSAGES 64

// A received message
typedef struct {
    int32_t  conn_id;                        // Who sent it
    uint32_t size;                           // Data size in bytes
    uint8_t  data[GNS_MAX_MESSAGE_SIZE];     // Message payload
    int      reliable;                       // 1 if received on reliable channel
} gns_message_t;

// Poll for incoming messages. Returns the number of messages received.
// Messages are written into the provided array. Caller allocates.
GNS_API int gns_poll(gns_message_t* messages, int max_messages);

// ============================================================================
// Connection Events
// ============================================================================

#define GNS_EVENT_CONNECTED     1
#define GNS_EVENT_DISCONNECTED  2
#define GNS_EVENT_REJECTED      3

typedef struct {
    int      event_type;    // GNS_EVENT_*
    int32_t  conn_id;       // Connection ID
    char     info[256];     // Human-readable info (IP, reason, etc.)
} gns_connection_event_t;

// Poll for connection events (connects, disconnects).
// Returns number of events. Caller provides array.
GNS_API int gns_poll_connection_events(gns_connection_event_t* events, int max_events);

// ============================================================================
// Status
// ============================================================================

typedef struct {
    float    ping_ms;           // Round-trip time in milliseconds
    float    packet_loss_pct;   // Packet loss percentage (0-100)
    float    bandwidth_kbps;    // Estimated bandwidth in kbps
    int      connection_state;  // 0=none, 1=connecting, 2=connected, 3=disconnected
} gns_status_t;

// Get connection status. For clients, returns status of host connection.
// For hosts, pass a specific conn_id.
GNS_API int gns_get_status(int32_t conn_id, gns_status_t* status);

// Get number of connected clients (host mode only).
GNS_API int gns_get_client_count(void);

// ============================================================================
// Utility
// ============================================================================

// Returns 1 if currently hosting, 0 otherwise.
GNS_API int gns_is_host(void);

// Returns 1 if currently connected as client, 0 otherwise.
GNS_API int gns_is_client(void);

#ifdef __cplusplus
}
#endif
