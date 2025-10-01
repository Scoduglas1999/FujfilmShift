cmake_minimum_required(VERSION 3.19)
project(fuji_stitcher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(BUILD_SHARED_LIBS "Build shared library" ON)

# Dependencies: OpenCV and LibRaw (prefer vcpkg CONFIG; fallback to pkg-config)
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

set(HAVE_LIBRAW FALSE)
set(LIBRAW_TARGET "")
set(LIBRAW_INCLUDE_DIRS "")

# Prefer vcpkg target name
find_package(unofficial-libraw CONFIG QUIET)
if(TARGET unofficial-libraw::libraw)
  set(HAVE_LIBRAW TRUE)
  set(LIBRAW_TARGET unofficial-libraw::libraw)
else()
  # Fallback to pkg-config only
  find_package(PkgConfig QUIET)
  if(PKG_CONFIG_FOUND)
    pkg_check_modules(LIBRAW QUIET libraw)
    if(LIBRAW_FOUND)
      set(HAVE_LIBRAW TRUE)
      # LIBRAW_INCLUDE_DIRS and LIBRAW_LIBRARIES provided by pkg-config
    endif()
  endif()
endif()

if(NOT HAVE_LIBRAW)
  # Fallback: manual locate within vcpkg installed tree
  if(DEFINED VCPKG_INSTALLED_DIR AND DEFINED VCPKG_TARGET_TRIPLET)
    set(_VCPKG_INC "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include")
    set(_VCPKG_LIB "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")
    find_path(LIBRAW_INCLUDE_DIR libraw/libraw.h PATHS ${_VCPKG_INC})
    find_library(LIBRAW_LIBRARY NAMES raw_r raw libraw PATHS ${_VCPKG_LIB})
    if(LIBRAW_INCLUDE_DIR AND LIBRAW_LIBRARY)
      set(HAVE_LIBRAW TRUE)
      set(LIBRAW_FOUND TRUE)
      set(LIBRAW_INCLUDE_DIRS ${LIBRAW_INCLUDE_DIR})
      set(LIBRAW_LIBRARIES ${LIBRAW_LIBRARY})
    endif()
  endif()
endif()

if(NOT HAVE_LIBRAW)
  message(FATAL_ERROR "LibRaw not found. Install with vcpkg (vcpkg install libraw:x64-windows opencv:x64-windows) or provide pkg-config libraw.")
endif()

add_library(fuji_stitcher SHARED
  src/fuji_stitcher.cpp
  src/fuji_stitcher.h
)

# Ensure Windows export macro is set when building the DLL
target_compile_definitions(fuji_stitcher PRIVATE FUJI_STITCHER_EXPORTS)

target_include_directories(fuji_stitcher PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(fuji_stitcher PRIVATE ${OpenCV_LIBS})

if(LIBRAW_TARGET)
  target_link_libraries(fuji_stitcher PRIVATE ${LIBRAW_TARGET})
  # Ensure include dirs are visible to this target even if the imported
  # target does not propagate them as expected on some setups
  get_target_property(_LIBRAW_IFACE_INCLUDES ${LIBRAW_TARGET} INTERFACE_INCLUDE_DIRECTORIES)
  if(_LIBRAW_IFACE_INCLUDES)
    target_include_directories(fuji_stitcher PRIVATE ${_LIBRAW_IFACE_INCLUDES})
  endif()
elseif(LIBRAW_FOUND)
  target_include_directories(fuji_stitcher PRIVATE ${LIBRAW_INCLUDE_DIRS})
  target_link_libraries(fuji_stitcher PRIVATE ${LIBRAW_LIBRARIES})
endif()

if(WIN32)
  set_target_properties(fuji_stitcher PROPERTIES OUTPUT_NAME "fuji_stitcher")
elseif(APPLE)
  set_target_properties(fuji_stitcher PROPERTIES OUTPUT_NAME "libfuji_stitcher")
else()
  set_target_properties(fuji_stitcher PROPERTIES OUTPUT_NAME "libfuji_stitcher")
endif()


