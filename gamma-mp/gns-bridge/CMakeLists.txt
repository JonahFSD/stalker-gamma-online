cmake_minimum_required(VERSION 3.15)
project(gns_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

# Find GameNetworkingSockets (via vcpkg)
find_package(GameNetworkingSockets CONFIG REQUIRED)

add_library(gns_bridge SHARED
    gns_bridge.cpp
    gns_bridge.h
)

target_compile_definitions(gns_bridge PRIVATE GNS_BRIDGE_EXPORTS)

target_link_libraries(gns_bridge PRIVATE
    GameNetworkingSockets::GameNetworkingSockets
    ws2_32
)

# Output to bin directory
set_target_properties(gns_bridge PROPERTIES
    OUTPUT_NAME "gns_bridge"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Copy GNS runtime DLLs next to our DLL
add_custom_command(TARGET gns_bridge POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        $<TARGET_FILE:GameNetworkingSockets::GameNetworkingSockets>
        $<TARGET_FILE_DIR:gns_bridge>
)
