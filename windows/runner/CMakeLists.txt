cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)
enable_language(C)
add_subdirectory("${CMAKE_SOURCE_DIR}/../third_party/qrc_codec" "${CMAKE_CURRENT_BINARY_DIR}/qrc_codec")

if(EXISTS "${CMAKE_SOURCE_DIR}/../tooling/system_fonts_probe.cpp")
  add_executable(system_fonts_probe EXCLUDE_FROM_ALL
    "${CMAKE_SOURCE_DIR}/../tooling/system_fonts_probe.cpp" "system_fonts.cpp")
  apply_standard_settings(system_fonts_probe)
  target_compile_definitions(system_fonts_probe PRIVATE NOMINMAX)
  target_link_libraries(system_fonts_probe PRIVATE dwrite)
  set_target_properties(system_fonts_probe PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/../temp/font-diagnostics")
endif()

add_library(cover_layers_gpu SHARED "cover_layers_gpu.cpp" "cover_gpu_resources.rc")
set_source_files_properties("cover_gpu_resources.rc" PROPERTIES
  OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cover_gpu_compute.hlsl")
set_target_properties(cover_layers_gpu PROPERTIES
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/native_imports")
apply_standard_settings(cover_layers_gpu)
target_compile_definitions(cover_layers_gpu PRIVATE NOMINMAX)
target_include_directories(cover_layers_gpu SYSTEM PRIVATE
  "${CMAKE_SOURCE_DIR}/../third_party/onnxruntime/include"
  "${CMAKE_SOURCE_DIR}/../third_party/cover_gpu/include")
target_link_libraries(cover_layers_gpu PRIVATE d3d12 dxgi dxcore d3dcompiler)

add_library(cover_layers_gpu_dev SHARED EXCLUDE_FROM_ALL
  "cover_layers_gpu.cpp" "cover_gpu_resources.rc")
apply_standard_settings(cover_layers_gpu_dev)
target_compile_definitions(cover_layers_gpu_dev PRIVATE NOMINMAX COVER_DEV_DISCRETE_DRAFTS=1)
target_include_directories(cover_layers_gpu_dev SYSTEM PRIVATE
  "${CMAKE_SOURCE_DIR}/../third_party/onnxruntime/include"
  "${CMAKE_SOURCE_DIR}/../third_party/cover_gpu/include")
target_link_libraries(cover_layers_gpu_dev PRIVATE d3d12 dxgi dxcore d3dcompiler)
set_target_properties(cover_layers_gpu_dev PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/../temp/cover-gpu-development"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/../temp/cover-gpu-development/imports")
set(_cover_models_default OFF)
if(EXISTS "${CMAKE_SOURCE_DIR}/../third_party/cover_gpu/u2netp.onnx")
  set(_cover_models_default ON)
endif()
option(MD3_BUNDLE_COVER_MODELS "Bundle optional cover-layer backend and models" ${_cover_models_default})
if(MD3_BUNDLE_COVER_MODELS)
  install(TARGETS cover_layers_gpu RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
  install(DIRECTORY "${CMAKE_SOURCE_DIR}/../third_party/cover_gpu/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/runtime/cover_gpu" COMPONENT Runtime
    PATTERN "include" EXCLUDE)
endif()






add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "system_fonts.cpp"
  "system_performance_monitor.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)



apply_standard_settings(${BINARY_NAME})


target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_DISPLAY=\"${FLUTTER_VERSION_MAJOR}.${FLUTTER_VERSION_MINOR}.${FLUTTER_VERSION_PATCH}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")


target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")



target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "pdh.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "dwrite.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")


add_dependencies(${BINARY_NAME} flutter_assemble)



if(EXISTS "${MUSIC_FETCHER_SOURCE}")
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${MUSIC_FETCHER_SOURCE}"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/MusicFetcher.exe"
    COMMENT "Copying framework-dependent MusicFetcher"
  )
endif()
