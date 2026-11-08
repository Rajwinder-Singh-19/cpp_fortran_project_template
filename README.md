# cpp_fortran_project

A minimal CMake template for **hybrid C++20 / Fortran** projects. The
executable is C++ and calls into a Fortran static library through a
`bind(C)` / `extern "C"` interop boundary. Compiler compatibility is verified
at configure time.

---

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| CMake | **3.30+** | enforced via `cmake_minimum_required(... FATAL_ERROR)` |
| C++ compiler | C++20 | GCC, Clang, or AppleClang |
| Fortran compiler | GNU-compatible | GCC's `gfortran` is the reference |

The C++ and Fortran compilers must be **ABI-compatible** (e.g. both from GCC,
both from the same Clang/LLVM toolchain). This is checked automatically at
configure time via `FortranCInterface_VERIFY`.

The compile flags are GCC/Clang-style. On MSVC you would need to translate or
guard them with generator expressions.

---

## Project layout

```
.
├── CMakeLists.txt
├── include/
│   ├── cpp_example.h        # C++ interface(s)
│   └── fortran_example.h    # extern "C" declarations for Fortran
├── src/
│   ├── cpp_example.cpp      # C++ implementation
│   └── fortran_example.f90  # Fortran implementation (bind(C))
└── main.cpp                 # C++ entry point
```

Two targets are produced:

| Target | Language | Type | Purpose |
|--------|----------|------|---------|
| `fortran` | Fortran | `STATIC` library | All Fortran code |
| `cpp_fortran_project` | C++20 | executable | Entry point; links `fortran` |

`.mod` files land in `${CMAKE_BINARY_DIR}/mod` and are on the executable's
include path. Fortran sources are preprocessed (`#include`, `#define` work).

---

## Building

### Single-config generators (Unix Makefiles, plain Ninja)

CMake bakes the build type into the cache at **configure** time. Use one build
directory per configuration:

```bash
# Debug (default if you omit -DCMAKE_BUILD_TYPE)
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build

# Release
cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release

# RelWithDebInfo (optimized, keeps symbols - good for profiling)
cmake -S . -B build-prof -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build-prof
```

### Multi-config generators (Ninja Multi-Config, Visual Studio, Xcode)

Configure once, pick the config at build time:

```bash
cmake -S . -B build -G "Ninja Multi-Config"
cmake --build build --config Release
cmake --build build --config Debug
```

### Running

```bash
./build/cpp_fortran_project
```

Expected output (order depends on `main.cpp`):

```
===================================================
This is an example c++/fortran hybrid project (CPP)
===================================================
=======================================================
This is an example c++/fortran hybrid project (FORTRAN)
=======================================================
```

---

## How the interop works

This template uses **`iso_c_binding` + `bind(C)`** — the recommended approach
for new code. The Fortran subroutine:

```fortran
subroutine example_fortran() bind(c, name="example_fortran")
    ...
end subroutine example_fortran
```

is declared on the C++ side as an ordinary C function:

```cpp
// include/fortran_example.h
extern "C"
{
    void example_fortran();
}
```

`bind(C, name="...")` forces the exported symbol name to `example_fortran`
with C calling convention — no name mangling, no need for compiler-specific
wrapper headers, and it works with any C++ compiler.

To call Fortran from C++ with **arguments**, use C-compatible types on both
sides (`integer(c_int)`, `real(c_double)`, `type(c_ptr)`, `character(c_char)`).

---

## What the template gives you

### Compiler verification

```cmake
include(FortranCInterface)
FortranCInterface_VERIFY(CXX)
```

Fails early at configure time if the C++ and Fortran compilers can't produce
mutually-callable code — instead of letting you hit a mysterious link error or
runtime crash later.

### Fortran module directory

```cmake
set_target_properties(fortran PROPERTIES
    Fortran_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/mod")
target_include_directories(${PROJECT_NAME} PRIVATE "${CMAKE_BINARY_DIR}/mod")
```

`.mod` files live in a single, predictable directory and are visible to the
C++ target.

### Fortran preprocessing

```cmake
set_target_properties(fortran PROPERTIES Fortran_PREPROCESS ON)
```

Enables `#include` / `#define` in `.f90` sources at no meaningful cost.

### Flags

Split into **always-on** and **Debug-only** using generator expressions
(`$<$<CONFIG:Debug>:...>`). The template never hardcodes `-O0` / `-g` /
`-DNDEBUG` — CMake supplies those per build type.

**Fortran — always on**

| Flag | Why |
|------|-----|
| `-Wall -Wextra` | baseline warnings |
| `-Wuninitialized` | catch use-before-set |
| `-fimplicit-none` | require `implicit none` — non-negotiable for new code |
| `-ffree-line-length-none` | allow long free-form lines |
| `-fbacktrace` | stack trace on crash (cheap) |

**Fortran — Debug only**

| Flag | Cost |
|------|------|
| `-fcheck=all` | bounds, pointer, array-temp, recursion checks |
| `-ffpe-trap=invalid,zero,overflow` | trap invalid FP ops (**not** `underflow`) |
| `-finit-real=snan` | initialize reals to signaling NaN |

**C++ — always on:** `-Wall -Wextra -Wpedantic -Warray-bounds`

**C++ — Debug only:** `-Werror` (keeps dev builds clean without blocking
release builds when a compiler update adds a new warning).

---

## Adding code

### A new Fortran source file

```cmake
target_sources(fortran PRIVATE
    src/fortran_example.f90
    src/mymodule.f90      # <- add here
)
```

### A new C++ source file

```cmake
target_sources(${PROJECT_NAME} PRIVATE
    main.cpp
    src/cpp_example.cpp
    src/myutil.cpp        # <- add here
)
```

### A new public header

Put it in `include/` — it's already on the executable's include path.

---

## Tips

- **Sanitizers** (C++ side) follow the same generator-expression pattern:

  ```cmake
  target_compile_options(${PROJECT_NAME} PRIVATE
      $<$<CONFIG:Debug>:-fsanitize=address,undefined>
      $<$<CONFIG:Debug>:-fno-omit-frame-pointer>)
  target_link_options(${PROJECT_NAME} PRIVATE
      $<$<CONFIG:Debug>:-fsanitize=address,undefined>)
  ```

  Sanitizers on the Fortran side are much less mature — usually you sanitize
  the C++ side and rely on Fortran's `-fcheck=all`.

- **Preprocessor defines** belong in `target_compile_definitions`, not
  `target_compile_options`:

  ```cmake
  target_compile_definitions(${PROJECT_NAME} PRIVATE
      $<$<CONFIG:Debug>:MYAPP_DEBUG>)
  ```

- **`underflow` in `-ffpe-trap` is deliberately excluded.** Underflow is
  routine in floating-point and trapping it will crash legitimate numerical
  code.

- **`-Werror` is Debug-only.** A new warning from a compiler update or a
  third-party header shouldn't block a production build.

- **`C` is listed in `project(... LANGUAGES C CXX Fortran)`** because
  `FortranCInterface_VERIFY(CXX)` compiles a small C helper to probe the
  mangling.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.