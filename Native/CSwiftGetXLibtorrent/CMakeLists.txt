cmake_minimum_required(VERSION 3.20)
project(CSwiftGetXLibtorrent LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SWIFTGETX_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build libtorrent as a static library" FORCE)
set(deprecated-functions OFF CACHE BOOL "Disable deprecated libtorrent APIs" FORCE)
set(logging OFF CACHE BOOL "Disable libtorrent logging" FORCE)

add_subdirectory("${SWIFTGETX_ROOT}/Vendor/libtorrent" "${CMAKE_BINARY_DIR}/libtorrent-build")

add_library(CSwiftGetXLibtorrent STATIC
    "${SWIFTGETX_ROOT}/Sources/CSwiftGetXLibtorrent/src/CSwiftGetXLibtorrent.cpp"
)

target_include_directories(CSwiftGetXLibtorrent PUBLIC
    "${SWIFTGETX_ROOT}/Sources/CSwiftGetXLibtorrent/include"
)

target_link_libraries(CSwiftGetXLibtorrent PUBLIC torrent-rasterbar)
