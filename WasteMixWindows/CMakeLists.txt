cmake_minimum_required(VERSION 3.20)
project(WasteMix VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find DirectX 12
find_path(D3D12_INCLUDE_DIR d3d12.h PATHS "$ENV{WindowsSdkDir}/Include/$ENV{WindowsSDKVersion}/um")

# ImGui sources (download separately or use vcpkg)
set(IMGUI_DIR "${CMAKE_SOURCE_DIR}/libs/imgui")

# Source files
set(SOURCES
    src/main.cpp
    src/rendering/dx12_context.cpp
    src/rendering/dx12_context.h
    src/rendering/render_engine.cpp
    src/rendering/render_engine.h
    src/rendering/compositor.cpp
    src/rendering/compositor.h
    src/input/camera_source.cpp
    src/input/camera_source.h
    src/input/media_source.cpp
    src/input/media_source.h
    src/input/audio_engine.cpp
    src/input/audio_engine.h
    src/ui/mixer_ui.cpp
    src/ui/mixer_ui.h
)

# ImGui sources (if present)
if(EXISTS "${IMGUI_DIR}/imgui.cpp")
    list(APPEND SOURCES
        ${IMGUI_DIR}/imgui.cpp
        ${IMGUI_DIR}/imgui_draw.cpp
        ${IMGUI_DIR}/imgui_tables.cpp
        ${IMGUI_DIR}/imgui_widgets.cpp
        ${IMGUI_DIR}/backends/imgui_impl_win32.cpp
        ${IMGUI_DIR}/backends/imgui_impl_dx12.cpp
    )
    include_directories(${IMGUI_DIR} ${IMGUI_DIR}/backends)
endif()

add_executable(WasteMix WIN32 ${SOURCES})

target_include_directories(WasteMix PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/src
)

target_link_libraries(WasteMix PRIVATE
    d3d12
    dxgi
    d3dcompiler
    dxguid
    mfplat
    mfreadwrite
    mfuuid
    ole32
    windowscodecs
)

# Copy shaders to build directory
file(GLOB SHADER_FILES "${CMAKE_SOURCE_DIR}/src/shaders/*.hlsl" "${CMAKE_SOURCE_DIR}/src/shaders/*.hlsli")
foreach(SHADER ${SHADER_FILES})
    get_filename_component(SHADER_NAME ${SHADER} NAME)
    configure_file(${SHADER} "${CMAKE_BINARY_DIR}/shaders/${SHADER_NAME}" COPYONLY)
endforeach()
