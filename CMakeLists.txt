cmake_minimum_required(VERSION 3.30 FATAL_ERROR)
project(cpp_fortran_project LANGUAGES C CXX Fortran)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FortranCInterface)
FortranCInterface_VERIFY(CXX)

# ---------------- Fortran library ----------------
add_library(fortran)
target_sources(fortran
    PRIVATE
    src/fortran_example.f90
)

set_target_properties(fortran PROPERTIES
    Fortran_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/mod"
    Fortran_PREPROCESS ON
)

target_compile_options(fortran PRIVATE

    # --- Always on: zero runtime cost, pure warnings/behavior ---
    -Wall
    -Wextra
    -Wuninitialized
    -fimplicit-none
    -ffree-line-length-none
    -fbacktrace # cheap: only formats a trace on crash

    # --- Debug only: real runtime cost, don't ship in Release ---
    $<$<CONFIG:Debug>:-fcheck=all>
    $<$<CONFIG:Debug>:-ffpe-trap=invalid,zero,overflow>
    $<$<CONFIG:Debug>:-finit-real=snan>
)

# ---------------- C++ executable ----------------
add_executable(${PROJECT_NAME})
target_sources(${PROJECT_NAME}
    PRIVATE
    main.cpp
    src/cpp_example.cpp
)

target_include_directories(${PROJECT_NAME} PRIVATE
    include
    "${CMAKE_BINARY_DIR}/mod"
)

target_link_libraries(${PROJECT_NAME} PRIVATE fortran)

target_compile_options(${PROJECT_NAME} PRIVATE

    # --- Always on ---
    -Wall
    -Wextra
    -Wpedantic
    -Warray-bounds

    # --- Debug only ---
    # -Werror in Debug keeps dev builds warning-clean, but not in Release
    # (so a new warning from a header bump doesn't block production builds).
    $<$<CONFIG:Debug>:-Werror>
)