cmake_minimum_required(VERSION 3.12)
project(hesiod-root VERSION 0.6.0)

set(EXECUTABLE_OUTPUT_PATH ${CMAKE_BINARY_DIR}/bin)

# Version info
add_compile_definitions(
  HESIOD_VERSION_MAJOR=${hesiod-root_VERSION_MAJOR}
  HESIOD_VERSION_MINOR=${hesiod-root_VERSION_MINOR}
  HESIOD_VERSION_PATCH=${hesiod-root_VERSION_PATCH}
  $<$<CONFIG:Release,RelWithDebInfo>:RELEASE_BUILD>
  $<$<CONFIG:Debug>:DEBUG_BUILD>)

# ------------------------------
# Options
# ------------------------------
# AppImage is a Linux packaging format: disabled by default elsewhere.
if(UNIX AND NOT APPLE)
  set(_appimage_default ON)
else()
  set(_appimage_default OFF)
endif()

option(HESIOD_ENABLE_GENERATE_APP_IMAGE "Enable AppImage generation"
       ${_appimage_default})

option(HESIOD_ENABLE_UI_TESTS
       "Build the interface scale / node palette regression tests" ON)

option(HESIOD_MINIMAL_NODE_SET
       "Use a minimal set of nodes (ADVANCED DEV ONLY!!!)" OFF)

option(HESIOD_ENABLE_TESTS "Build Hesiod integration tests" OFF)
if(HESIOD_ENABLE_TESTS)
  enable_testing()
endif()

option(HESIOD_ENABLE_LTO "Enable LTO and unused-function detection" OFF)
option(HESIOD_UNUSED_FUNCTIONS "Detect unused static functions" OFF)
option(HESIOD_PROFILE_BUILD "Enable build time profiling (-ftime-trace)" OFF)
option(HESIOD_ENABLE_PCH "Enable Precompiled Headers (PCH)" OFF)

# ------------------------------
# Modules
# ------------------------------
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(HesiodCompilerOptions)
include(HesiodPlatform)
include(HesiodQtLoggingRules)
include(HesiodGitVersion)

# ------------------------------
# Dependencies
# ------------------------------
find_package(spdlog REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Widgets OpenGL OpenGLWidgets
                                     WebEngineWidgets)
find_package(nlohmann_json REQUIRED)
find_package(ZLIB REQUIRED)

# macOS does not expose the OpenCL C/C++ headers in the default SDK paths.
if(APPLE)
  if(NOT DEFINED HOMEBREW_PREFIX)
    execute_process(
      COMMAND brew --prefix
      OUTPUT_VARIABLE HOMEBREW_PREFIX
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET)
  endif()

  foreach(_keg opencl-headers opencl-clhpp-headers)
    if(EXISTS "${HOMEBREW_PREFIX}/opt/${_keg}/include")
      include_directories("${HOMEBREW_PREFIX}/opt/${_keg}/include")
    endif()
  endforeach()
endif()

add_compile_definitions(
  CL_HPP_MINIMUM_OPENCL_VERSION=120 CL_HPP_TARGET_OPENCL_VERSION=120
  HSD_DEFAULT_GPU_MODE=true)

# ------------------------------
# Status output
# ------------------------------
message(STATUS "┌─ Hesiod configuration ──────────────")
message(
  STATUS
    "│ HESIOD_ENABLE_GENERATE_APP_IMAGE:   ${HESIOD_ENABLE_GENERATE_APP_IMAGE}")
message(
  STATUS "│ HESIOD_MINIMAL_NODE_SET:            ${HESIOD_MINIMAL_NODE_SET}")
message(STATUS "│ HESIOD_ENABLE_LTO:                  ${HESIOD_ENABLE_LTO}")
message(
  STATUS "│ HESIOD_UNUSED_FUNCTIONS:            ${HESIOD_UNUSED_FUNCTIONS}")
message(STATUS "│ HESIOD_PROFILE_BUILD:               ${HESIOD_PROFILE_BUILD}")
message(STATUS "│ HESIOD_ENABLE_PCH:                  ${HESIOD_ENABLE_PCH}")
message(STATUS "│ CMAKE_BUILD_TYPE:                   ${CMAKE_BUILD_TYPE}")
message(STATUS "│ CMAKE_CXX_COMPILER_ID:              ${CMAKE_CXX_COMPILER_ID}")
message(STATUS "│ QT_VERSION:                         ${Qt6_VERSION}")
message(STATUS "│ QT_DIR:                             ${Qt6_DIR}")
message(STATUS "└─────────────────────────────────────")

# ------------------------------
# Subdirectories
# ------------------------------
add_subdirectory(external)
add_subdirectory(Hesiod)
add_subdirectory(bridges)

if(HESIOD_ENABLE_UI_TESTS)
  add_subdirectory(tests)
endif()

# The upstream Meta snapshot used by current Hesiod declares std::ostringstream
# in a public trait header without including <sstream>. libc++ does not pull it
# in transitively, so force-include it for Meta and, through PUBLIC usage
# requirements, for every target that consumes Meta's headers (hesiod_core,
# the tests, the bridges) on AppleClang until the dependency fixes its header.
if(APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND TARGET meta)
  target_compile_options(
    meta PUBLIC "$<$<COMPILE_LANGUAGE:CXX>:SHELL:-include sstream>")
endif()

if(HESIOD_ENABLE_GENERATE_APP_IMAGE)
  add_subdirectory(scripts/generate_appimage)
endif()
