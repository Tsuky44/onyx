# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
# Onyx : l'algorithme d'empreinte est un paramètre. Le libmpv s'épingle en
# SHA-256, l'empreinte que GitHub publie à côté de chaque asset de release de
# mpv : un changement de version se vérifie sur la page, sans recalcul.
function(download_and_verify url algo hash locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(${algo} "${locationForArchive}" ARCHIVE_HASH)

    # If the hash doesn't match, delete the archive to download again.
    if(NOT hash STREQUAL ARCHIVE_HASH)
      file(REMOVE "${locationForArchive}")
      message(STATUS "${algo} mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify the hash of the newly downloaded file.
    file(${algo} "${locationForArchive}" ARCHIVE_HASH)

    if(hash STREQUAL ARCHIVE_HASH)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# libmpv archive containing the pre-built shared libraries & headers.
#
# Onyx : le libmpv officiel de mpv, variante LGPL (ADR-0158, phase 1). Depuis la
# 0.42.0, mpv publie avec chaque release une libmpv Windows, signée (PGP, clé de
# Kacper Michajłow) : en-têtes, libmpv-2.dll et la bibliothèque d'import
# libmpv.dll.a que lie media_kit_video. Son FFmpeg est celui de BtbN, variante
# « lgpl » (--enable-version3) : l'ensemble est sous LGPLv3. Il a tout ce que le
# build de shinchiro apportait (TrueHD, DTS, E-AC-3, libass, libplacebo, libcurl
# pour le relais de l'ADR-0036), ce que check_libmpv.ps1 vérifie plus bas.
# Une release GitHub de mpv ne tourne pas : l'URL épinglée reste.
set(LIBMPV_VERSION "v0.42.0")
set(LIBMPV "libmpv-${LIBMPV_VERSION}-x86_64-w64-mingw32-lgpl.zip")

# Download URL & SHA-256 of the libmpv archive (the digest GitHub shows for the
# release asset).
set(LIBMPV_URL "https://github.com/mpv-player/mpv/releases/download/${LIBMPV_VERSION}/${LIBMPV}")
set(LIBMPV_SHA256 "8e5f77430efc53ef175804ba6618527e3af0448a0dcabf04d3cc72659d1a6fce")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_verify(
  ${LIBMPV_URL}
  SHA256
  ${LIBMPV_SHA256}
  ${LIBMPV_ARCHIVE}
)

# Onyx : extraction à la configuration, et refaite dès que le dossier ne
# correspond plus à l'archive épinglée. L'ancienne version n'extrayait que dans
# un dossier vide : un build existant gardait la DLL de l'archive précédente,
# si bien qu'un changement de libmpv (le FFmpeg complet, pour le TrueHD) n'avait
# jamais atteint les builds locaux. Le chemin reste ${CMAKE_BINARY_DIR}/libmpv,
# que media_kit_video lit en dur.
set(LIBMPV_STAMP "${LIBMPV_SRC}/onyx-libmpv.stamp")
set(LIBMPV_STAMP_CONTENT "${LIBMPV} ${LIBMPV_SHA256}")
set(LIBMPV_CURRENT_STAMP "")
if(EXISTS "${LIBMPV_STAMP}")
  file(READ "${LIBMPV_STAMP}" LIBMPV_CURRENT_STAMP)
endif()

if(NOT LIBMPV_CURRENT_STAMP STREQUAL LIBMPV_STAMP_CONTENT)
  message(STATUS "Extracting ${LIBMPV}...")
  file(REMOVE_RECURSE "${LIBMPV_SRC}")
  file(MAKE_DIRECTORY "${LIBMPV_SRC}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "${LIBMPV_ARCHIVE}"
    WORKING_DIRECTORY "${LIBMPV_SRC}"
    RESULT_VARIABLE LIBMPV_EXTRACT_RESULT
  )
  if(NOT LIBMPV_EXTRACT_RESULT EQUAL 0)
    message(FATAL_ERROR "Unable to extract ${LIBMPV_ARCHIVE}.")
  endif()

  # media_kit_video includes <client.h>, <render.h>…: headers straight in include/.
  file(GLOB LIBMPV_HEADERS "${LIBMPV_SRC}/include/mpv/*")
  file(COPY ${LIBMPV_HEADERS} DESTINATION "${LIBMPV_SRC}/include")
  file(REMOVE_RECURSE "${LIBMPV_SRC}/include/mpv")

  # Les fichiers Java de libbluray (menus BD-J) ne sont pas livrés : rien ne les
  # charge, l'app ne lit pas de disque.
  file(GLOB LIBMPV_JARS "${LIBMPV_SRC}/*.jar")
  if(LIBMPV_JARS)
    file(REMOVE ${LIBMPV_JARS})
  endif()

  foreach(LIBMPV_FILE libmpv-2.dll libmpv.dll.a include/client.h include/render.h include/render_gl.h)
    if(NOT EXISTS "${LIBMPV_SRC}/${LIBMPV_FILE}")
      message(FATAL_ERROR "${LIBMPV} does not contain ${LIBMPV_FILE}.")
    endif()
  endforeach()

  # Ce que l'app attend de la DLL, vérifié en la chargeant : un libmpv qui
  # perdrait le TrueHD ou libcurl se jouerait sinon sans erreur, en silence.
  execute_process(
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass
      -File "${CMAKE_CURRENT_SOURCE_DIR}/check_libmpv.ps1"
      -Dll "${LIBMPV_SRC}/libmpv-2.dll"
    RESULT_VARIABLE LIBMPV_CHECK_RESULT
    OUTPUT_VARIABLE LIBMPV_CHECK_OUTPUT
    ERROR_VARIABLE LIBMPV_CHECK_ERROR
  )
  if(NOT LIBMPV_CHECK_RESULT EQUAL 0)
    message(FATAL_ERROR "libmpv-2.dll check failed:\n${LIBMPV_CHECK_OUTPUT}${LIBMPV_CHECK_ERROR}")
  endif()
  message(STATUS "${LIBMPV_CHECK_OUTPUT}")

  file(WRITE "${LIBMPV_STAMP}" "${LIBMPV_STAMP_CONTENT}")
endif()

# ------------------------------------------------------------------------------

# ANGLE archive containing the pre-built shared libraries & headers.
set(ANGLE "ANGLE.7z")

# Download URL & MD5 hash of the ANGLE archive.
set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")

# Download location of the ANGLE archive.
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

download_and_verify(
  ${ANGLE_URL}
  MD5
  ${ANGLE_MD5}
  ${ANGLE_ARCHIVE}
)

check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)

# Extract the ANGLE archive.
if(NOT ANGLE_SRC_VALID)
  message(STATUS "Extracting ${ANGLE}...")
  make_directory("${ANGLE_SRC}")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${ANGLE_ARCHIVE}\""
    WORKING_DIRECTORY "${ANGLE_SRC}"
  )
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
