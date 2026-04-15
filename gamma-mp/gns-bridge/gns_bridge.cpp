/*
 * GAMMA Multiplayer — GNS Bridge DLL Implementation
 *
 * Wraps Valve's GameNetworkingSockets into a flat C API for Lua consumption.
 * This is a thin pipe — all game logic lives in Lua.
 *
 * Build requirements:
 *   - Visual Studio 2022
 *   - GameNetworkingSockets (via vcpkg or NuGet)
 *   - Link: GameNetworkingSockets.lib, ws2_32.lib
 */

#define GNS_BRIDGE_EXPORTS
#include "gns_bridge.h"

#include <steam/steamnetworkingsockets.h>
#include <steam/isteamnetworkingsockets.h>
#include <steam/isteamnetworkingutils.h>

#include <vector>
#include <mutex>
#include <string>
#include <cstring>
#include <cstdio>

// ============================================================================
// Internal State
// ============================================================================

static ISteamNetworkingSockets* g_pInterface = nullptr;
static HSteamListenSocket       g_hListenSocket = k_HSteamListenSocket_Invalid;
static HSteamNetPollGroup        g_hPollGroup = k_HSteamNetPollGroup_Invalid;
static HSteamNetConnection       g_hClientConnection = k_HSteamNetConnection_Invalid;

static bool g_bIsHost = false;
static bool g_bIsClient = false;
static bool g_bInitialized = false;

// Track connected clients (host mode)
struct ClientConnection {
    HSteamNetConnection hConn;
    std::string description;
};
static std::vector<ClientConnection> g_vecClients;
static std::mutex g_clientsMutex;

// Connection event queue
static std::vector<gns_connection_event_t> g_vecConnectionEvents;
static std::mutex g_eventsMutex;

// ============================================================================
// Helper: Push connection event
// ============================================================================

static void PushConnectionEvent(int type, int32_t conn_id, const char* info)
{
    gns_connection_event_t evt = {};
    evt.event_type = type;
    evt.conn_id = conn_id;
    if (info)
        strncpy_s(evt.info, sizeof(evt.info), info, _TRUNCATE);

    std::lock_guard<std::mutex> lock(g_eventsMutex);
    g_vecConnectionEvents.push_back(evt);
}

// ============================================================================
// GNS Callback: Connection status changed
// ============================================================================

static void OnConnectionStatusChanged(SteamNetConnectionStatusChangedCallback_t* pInfo)
{
    HSteamNetConnection hConn = pInfo->m_hConn;
    SteamNetConnectionInfo_t& info = pInfo->m_info;
    ESteamNetworkingConnectionState oldState = pInfo->m_eOldState;
    ESteamNetworkingConnectionState newState = info.m_eState;

    if (g_bIsHost)
    {
        // HOST MODE: handle incoming client connections
        if (newState == k_ESteamNetworkingConnectionState_Connecting)
        {
            // Accept the connection
            if (g_pInterface->AcceptConnection(hConn) != k_EResultOK)
            {
                g_pInterface->CloseConnection(hConn, 0, "Failed to accept", false);
                return;
            }

            // Add to poll group
            if (!g_pInterface->SetConnectionPollGroup(hConn, g_hPollGroup))
            {
                g_pInterface->CloseConnection(hConn, 0, "Failed to set poll group", false);
                return;
            }

            // Track client
            {
                std::lock_guard<std::mutex> lock(g_clientsMutex);
                ClientConnection cc;
                cc.hConn = hConn;
                cc.description = info.m_szConnectionDescription;
                g_vecClients.push_back(cc);
            }

            char buf[256];
            snprintf(buf, sizeof(buf), "Client connected: %s", info.m_szConnectionDescription);
            PushConnectionEvent(GNS_EVENT_CONNECTED, (int32_t)hConn, buf);
        }
        else if (newState == k_ESteamNetworkingConnectionState_ClosedByPeer ||
                 newState == k_ESteamNetworkingConnectionState_ProblemDetectedLocally)
        {
            // Remove from tracking
            {
                std::lock_guard<std::mutex> lock(g_clientsMutex);
                for (auto it = g_vecClients.begin(); it != g_vecClients.end(); ++it)
                {
                    if (it->hConn == hConn)
                    {
                        g_vecClients.erase(it);
                        break;
                    }
                }
            }

            char buf[256];
            snprintf(buf, sizeof(buf), "Client disconnected: %s (reason: %d)",
                     info.m_szConnectionDescription, info.m_eEndReason);
            PushConnectionEvent(GNS_EVENT_DISCONNECTED, (int32_t)hConn, buf);

            g_pInterface->CloseConnection(hConn, 0, nullptr, false);
        }
    }
    else if (g_bIsClient)
    {
        // CLIENT MODE: handle connection to host
        if (newState == k_ESteamNetworkingConnectionState_Connected)
        {
            PushConnectionEvent(GNS_EVENT_CONNECTED, (int32_t)hConn, "Connected to host");
        }
        else if (newState == k_ESteamNetworkingConnectionState_ClosedByPeer ||
                 newState == k_ESteamNetworkingConnectionState_ProblemDetectedLocally)
        {
            char buf[256];
            snprintf(buf, sizeof(buf), "Disconnected from host: %s (reason: %d)",
                     info.m_szEndDebug, info.m_eEndReason);
            PushConnectionEvent(GNS_EVENT_DISCONNECTED, (int32_t)hConn, buf);

            g_pInterface->CloseConnection(hConn, 0, nullptr, false);
            g_hClientConnection = k_HSteamNetConnection_Invalid;
        }
        else if (newState == k_ESteamNetworkingConnectionState_None)
        {
            if (oldState == k_ESteamNetworkingConnectionState_Connecting)
            {
                PushConnectionEvent(GNS_EVENT_REJECTED, (int32_t)hConn, "Connection rejected");
                g_hClientConnection = k_HSteamNetConnection_Invalid;
            }
        }
    }
}

// ============================================================================
// Initialization
// ============================================================================

GNS_API int gns_init(void)
{
    if (g_bInitialized)
        return 0;

    SteamNetworkingErrMsg errMsg;
    if (!GameNetworkingSockets_Init(nullptr, errMsg))
        return -1;

    g_pInterface = SteamNetworkingSockets();
    if (!g_pInterface)
    {
        GameNetworkingSockets_Kill();
        return -1;
    }

    g_bInitialized = true;
    return 0;
}

GNS_API void gns_shutdown(void)
{
    if (!g_bInitialized)
        return;

    if (g_bIsHost)
        gns_stop_host();
    if (g_bIsClient)
        gns_disconnect();

    GameNetworkingSockets_Kill();
    g_pInterface = nullptr;
    g_bInitialized = false;
}

// ============================================================================
// Host API
// ============================================================================

GNS_API int gns_host(uint16_t port)
{
    if (!g_bInitialized || g_bIsHost || g_bIsClient)
        return -1;

    SteamNetworkingIPAddr serverLocalAddr;
    serverLocalAddr.Clear();
    serverLocalAddr.m_port = port;

    SteamNetworkingConfigValue_t opt;
    opt.SetPtr(k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged,
               (void*)OnConnectionStatusChanged);

    g_hListenSocket = g_pInterface->CreateListenSocketIP(serverLocalAddr, 1, &opt);
    if (g_hListenSocket == k_HSteamListenSocket_Invalid)
        return -1;

    g_hPollGroup = g_pInterface->CreatePollGroup();
    if (g_hPollGroup == k_HSteamNetPollGroup_Invalid)
    {
        g_pInterface->CloseListenSocket(g_hListenSocket);
        g_hListenSocket = k_HSteamListenSocket_Invalid;
        return -1;
    }

    g_bIsHost = true;
    return 0;
}

GNS_API void gns_stop_host(void)
{
    if (!g_bIsHost)
        return;

    // Close all client connections
    {
        std::lock_guard<std::mutex> lock(g_clientsMutex);
        for (auto& cc : g_vecClients)
            g_pInterface->CloseConnection(cc.hConn, 0, "Server shutting down", true);
        g_vecClients.clear();
    }

    if (g_hPollGroup != k_HSteamNetPollGroup_Invalid)
    {
        g_pInterface->DestroyPollGroup(g_hPollGroup);
        g_hPollGroup = k_HSteamNetPollGroup_Invalid;
    }

    if (g_hListenSocket != k_HSteamListenSocket_Invalid)
    {
        g_pInterface->CloseListenSocket(g_hListenSocket);
        g_hListenSocket = k_HSteamListenSocket_Invalid;
    }

    g_bIsHost = false;
}

// ============================================================================
// Client API
// ============================================================================

GNS_API int gns_connect(const char* ip, uint16_t port)
{
    if (!g_bInitialized || g_bIsHost || g_bIsClient)
        return -1;

    SteamNetworkingIPAddr serverAddr;
    serverAddr.Clear();
    if (!serverAddr.ParseString(ip))
        return -1;
    serverAddr.m_port = port;

    SteamNetworkingConfigValue_t opt;
    opt.SetPtr(k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged,
               (void*)OnConnectionStatusChanged);

    g_hClientConnection = g_pInterface->ConnectByIPAddress(serverAddr, 1, &opt);
    if (g_hClientConnection == k_HSteamNetConnection_Invalid)
        return -1;

    g_bIsClient = true;
    return 0;
}

GNS_API void gns_disconnect(void)
{
    if (!g_bIsClient)
        return;

    if (g_hClientConnection != k_HSteamNetConnection_Invalid)
    {
        g_pInterface->CloseConnection(g_hClientConnection, 0, "Client disconnecting", true);
        g_hClientConnection = k_HSteamNetConnection_Invalid;
    }

    g_bIsClient = false;
}

// ============================================================================
// Messaging
// ============================================================================

static int SendToConnection(HSteamNetConnection hConn, const void* data, uint32_t size, int flags)
{
    if (hConn == k_HSteamNetConnection_Invalid)
        return -1;

    EResult result = g_pInterface->SendMessageToConnection(
        hConn, data, size, flags, nullptr);

    return (result == k_EResultOK) ? 0 : -1;
}

GNS_API int gns_send_reliable(int32_t conn_id, const void* data, uint32_t size)
{
    if (!g_bInitialized || !data || size == 0)
        return -1;

    int flags = k_nSteamNetworkingSend_Reliable;

    if (g_bIsClient)
    {
        // Client always sends to host
        return SendToConnection(g_hClientConnection, data, size, flags);
    }
    else if (g_bIsHost)
    {
        if (conn_id == -1)
        {
            // Broadcast to all clients
            std::lock_guard<std::mutex> lock(g_clientsMutex);
            int result = 0;
            for (auto& cc : g_vecClients)
            {
                if (SendToConnection(cc.hConn, data, size, flags) != 0)
                    result = -1;
            }
            return result;
        }
        else
        {
            return SendToConnection((HSteamNetConnection)conn_id, data, size, flags);
        }
    }

    return -1;
}

GNS_API int gns_send_unreliable(int32_t conn_id, const void* data, uint32_t size)
{
    if (!g_bInitialized || !data || size == 0)
        return -1;

    int flags = k_nSteamNetworkingSend_Unreliable;

    if (g_bIsClient)
    {
        return SendToConnection(g_hClientConnection, data, size, flags);
    }
    else if (g_bIsHost)
    {
        if (conn_id == -1)
        {
            std::lock_guard<std::mutex> lock(g_clientsMutex);
            int result = 0;
            for (auto& cc : g_vecClients)
            {
                if (SendToConnection(cc.hConn, data, size, flags) != 0)
                    result = -1;
            }
            return result;
        }
        else
        {
            return SendToConnection((HSteamNetConnection)conn_id, data, size, flags);
        }
    }

    return -1;
}

// ============================================================================
// Polling
// ============================================================================

GNS_API int gns_poll(gns_message_t* messages, int max_messages)
{
    if (!g_bInitialized || !messages || max_messages <= 0)
        return 0;

    // Run callbacks first (processes connection state changes)
    g_pInterface->RunCallbacks();

    SteamNetworkingMessage_t* pIncomingMsgs[GNS_MAX_POLL_MESSAGES];
    int numMsgs = 0;

    if (g_bIsHost && g_hPollGroup != k_HSteamNetPollGroup_Invalid)
    {
        int limit = (max_messages < GNS_MAX_POLL_MESSAGES) ? max_messages : GNS_MAX_POLL_MESSAGES;
        numMsgs = g_pInterface->ReceiveMessagesOnPollGroup(g_hPollGroup, pIncomingMsgs, limit);
    }
    else if (g_bIsClient && g_hClientConnection != k_HSteamNetConnection_Invalid)
    {
        int limit = (max_messages < GNS_MAX_POLL_MESSAGES) ? max_messages : GNS_MAX_POLL_MESSAGES;
        numMsgs = g_pInterface->ReceiveMessagesOnConnection(g_hClientConnection, pIncomingMsgs, limit);
    }

    if (numMsgs < 0)
        return 0;

    int count = 0;
    for (int i = 0; i < numMsgs && count < max_messages; i++)
    {
        SteamNetworkingMessage_t* pMsg = pIncomingMsgs[i];

        if (pMsg->m_cbSize > 0 && (uint32_t)pMsg->m_cbSize <= GNS_MAX_MESSAGE_SIZE)
        {
            messages[count].conn_id = (int32_t)pMsg->m_conn;
            messages[count].size = (uint32_t)pMsg->m_cbSize;
            memcpy(messages[count].data, pMsg->m_pData, pMsg->m_cbSize);
            // GNS doesn't directly tell us channel in the message,
            // but we can infer from send flags if needed
            messages[count].reliable = 0; // Default; protocol layer handles this
            count++;
        }

        pMsg->Release();
    }

    return count;
}

GNS_API int gns_poll_connection_events(gns_connection_event_t* events, int max_events)
{
    if (!events || max_events <= 0)
        return 0;

    // Also run callbacks in case poll() hasn't been called
    if (g_bInitialized && g_pInterface)
        g_pInterface->RunCallbacks();

    std::lock_guard<std::mutex> lock(g_eventsMutex);

    int count = 0;
    int available = (int)g_vecConnectionEvents.size();
    int to_copy = (available < max_events) ? available : max_events;

    for (int i = 0; i < to_copy; i++)
    {
        events[i] = g_vecConnectionEvents[i];
        count++;
    }

    // Remove copied events
    if (to_copy > 0)
        g_vecConnectionEvents.erase(g_vecConnectionEvents.begin(),
                                     g_vecConnectionEvents.begin() + to_copy);

    return count;
}

// ============================================================================
// Status
// ============================================================================

GNS_API int gns_get_status(int32_t conn_id, gns_status_t* status)
{
    if (!g_bInitialized || !status)
        return -1;

    memset(status, 0, sizeof(gns_status_t));

    HSteamNetConnection hConn = k_HSteamNetConnection_Invalid;
    if (g_bIsClient)
        hConn = g_hClientConnection;
    else if (g_bIsHost && conn_id > 0)
        hConn = (HSteamNetConnection)conn_id;

    if (hConn == k_HSteamNetConnection_Invalid)
        return -1;

    SteamNetConnectionRealTimeStatus_t rtStatus;
    if (g_pInterface->GetConnectionRealTimeStatus(hConn, &rtStatus, 0, nullptr) != k_EResultOK)
        return -1;

    status->ping_ms = (float)rtStatus.m_nPing;
    status->packet_loss_pct = 0.0f; // GNS 1.4.x removed per-field loss; use quality metrics instead
    status->bandwidth_kbps = (float)(rtStatus.m_nSendRateBytesPerSecond * 8 / 1000);

    switch (rtStatus.m_eState)
    {
    case k_ESteamNetworkingConnectionState_Connecting:
        status->connection_state = 1;
        break;
    case k_ESteamNetworkingConnectionState_Connected:
        status->connection_state = 2;
        break;
    case k_ESteamNetworkingConnectionState_ClosedByPeer:
    case k_ESteamNetworkingConnectionState_ProblemDetectedLocally:
        status->connection_state = 3;
        break;
    default:
        status->connection_state = 0;
        break;
    }

    return 0;
}

GNS_API int gns_get_client_count(void)
{
    if (!g_bIsHost)
        return 0;

    std::lock_guard<std::mutex> lock(g_clientsMutex);
    return (int)g_vecClients.size();
}

GNS_API int gns_is_host(void) { return g_bIsHost ? 1 : 0; }
GNS_API int gns_is_client(void) { return g_bIsClient ? 1 : 0; }
