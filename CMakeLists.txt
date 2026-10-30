cmake_minimum_required(VERSION 3.31.6)
project(Mettle VERSION 0.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
option(METTLE_ENABLE_SANITIZERS "Instrument project C++ with ASan and UBSan" OFF)

file(READ "${PROJECT_SOURCE_DIR}/docs/toolchain-pins.json" METTLE_PINS)
string(JSON METTLE_LLVM_TAG GET "${METTLE_PINS}" sources 0 tag)
string(REPLACE "llvmorg-" "" METTLE_LLVM_VERSION "${METTLE_LLVM_TAG}")
string(JSON METTLE_CMAKE_TAG GET "${METTLE_PINS}" sources 1 tag)
string(SUBSTRING "${METTLE_CMAKE_TAG}" 1 -1 METTLE_CMAKE_VERSION)
string(JSON METTLE_NINJA_TAG GET "${METTLE_PINS}" sources 2 tag)
string(SUBSTRING "${METTLE_NINJA_TAG}" 1 -1 METTLE_NINJA_VERSION)

if(NOT CMAKE_VERSION VERSION_EQUAL METTLE_CMAKE_VERSION)
  message(FATAL_ERROR "Use pinned CMake ${METTLE_CMAKE_VERSION}; see tools/bootstrap.py")
endif()
if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang"
   OR NOT CMAKE_CXX_COMPILER_VERSION VERSION_EQUAL METTLE_LLVM_VERSION
   OR NOT CMAKE_C_COMPILER_ID STREQUAL "Clang"
   OR NOT CMAKE_C_COMPILER_VERSION VERSION_EQUAL METTLE_LLVM_VERSION)
  message(FATAL_ERROR "Use pinned Clang ${METTLE_LLVM_VERSION}; see tools/build.py")
endif()
if(NOT CMAKE_GENERATOR STREQUAL "Ninja")
  message(FATAL_ERROR "The foundation build requires the Ninja generator")
endif()
execute_process(COMMAND "${CMAKE_MAKE_PROGRAM}" --version
                OUTPUT_VARIABLE METTLE_ACTUAL_NINJA OUTPUT_STRIP_TRAILING_WHITESPACE
                COMMAND_ERROR_IS_FATAL ANY)
if(NOT METTLE_ACTUAL_NINJA STREQUAL METTLE_NINJA_VERSION)
  message(FATAL_ERROR "Use pinned Ninja ${METTLE_NINJA_VERSION}")
endif()

find_package(LLVM ${METTLE_LLVM_VERSION} EXACT REQUIRED CONFIG)
llvm_map_components_to_libnames(METTLE_LLVM_LIBRARIES
                               Core CodeGen MC Passes X86 AArch64 WebAssembly ARM)

if(METTLE_ENABLE_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all
                      -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined -fno-sanitize-recover=all)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(METTLE_LINKER_FLAGS -fuse-ld=lld)
  add_link_options(${METTLE_LINKER_FLAGS}
                   "LINKER:--thinlto-cache-dir=${PROJECT_BINARY_DIR}/../llvm-thinlto-cache")
elseif(APPLE)
  set(METTLE_LINKER_FLAGS "--sysroot=${CMAKE_OSX_SYSROOT}")
endif()

# Documented macOS baseline (docs/reference-profiles.md) for the runtime and
# for the objects the compiler emits, so linking never sees the host kernel
# version. The compiler itself is built for the host and is not affected.
set(METTLE_MACOS_DEPLOYMENT_TARGET "15.0" CACHE STRING
    "Minimum macOS version of the Darwin ARM64 runtime and emitted objects")
add_library(mettle_runtime STATIC runtime/panic.cpp runtime/panic.h
  runtime/alloc.cpp runtime/alloc.h runtime/sys.cpp runtime/sys.h
  runtime/thread.cpp runtime/thread.h)
if(APPLE)
  target_compile_options(mettle_runtime PRIVATE
    "-mmacosx-version-min=${METTLE_MACOS_DEPLOYMENT_TARGET}")
endif()
target_compile_options(mettle_runtime PRIVATE -Wall -Wextra -Wpedantic -Werror)
set(METTLE_RUNTIME_TARGET_FLAGS "")
if(CMAKE_CXX_COMPILER_TARGET)
  list(APPEND METTLE_RUNTIME_TARGET_FLAGS "--target=${CMAKE_CXX_COMPILER_TARGET}")
endif()
execute_process(COMMAND "${CMAKE_CXX_COMPILER}" ${METTLE_RUNTIME_TARGET_FLAGS} -dumpmachine
                OUTPUT_VARIABLE METTLE_RUNTIME_TARGET OUTPUT_STRIP_TRAILING_WHITESPACE
                COMMAND_ERROR_IS_FATAL ANY)
if(APPLE)
  # -dumpmachine reports the host kernel version, not the deployment target.
  string(REGEX REPLACE "-apple-.*$" "-apple-macosx${METTLE_MACOS_DEPLOYMENT_TARGET}"
         METTLE_RUNTIME_TARGET "${METTLE_RUNTIME_TARGET}")
endif()

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
             "${PROJECT_SOURCE_DIR}/compiler/modules.json")
find_package(Python3 3.9 REQUIRED COMPONENTS Interpreter)
execute_process(COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/tools/check_modules.py"
                        "${PROJECT_SOURCE_DIR}" COMMAND_ERROR_IS_FATAL ANY)
add_custom_target(mettle-module-check
  COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/tools/check_modules.py"
          "${PROJECT_SOURCE_DIR}"
  COMMENT "Checking compiler component boundaries")
file(READ "${PROJECT_SOURCE_DIR}/compiler/modules.json" METTLE_MODULES)
string(JSON METTLE_MODULE_COUNT LENGTH "${METTLE_MODULES}" modules)
math(EXPR METTLE_MODULE_LAST "${METTLE_MODULE_COUNT} - 1")
foreach(index RANGE ${METTLE_MODULE_LAST})
  string(JSON name GET "${METTLE_MODULES}" modules ${index} name)
  string(JSON kind GET "${METTLE_MODULES}" modules ${index} kind)
  string(JSON count LENGTH "${METTLE_MODULES}" modules ${index} files)
  math(EXPR last "${count} - 1")
  set(files "")
  foreach(file_index RANGE ${last})
    string(JSON source GET "${METTLE_MODULES}" modules ${index} files ${file_index})
    list(APPEND files "compiler/${source}")
  endforeach()
  if(kind STREQUAL "EXECUTABLE")
    add_executable(mettle ${files})
    set(target mettle)
  else()
    add_library(mettle_${name} ${kind} ${files})
    set(target mettle_${name})
  endif()
  set(METTLE_TARGET_${name} ${target})
  add_dependencies(${target} mettle-module-check)
  if(kind STREQUAL "INTERFACE")
    target_include_directories(${target} INTERFACE "${PROJECT_SOURCE_DIR}/compiler")
  else()
    target_include_directories(${target} PUBLIC "${PROJECT_SOURCE_DIR}/compiler")
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
  endif()
endforeach()
foreach(index RANGE ${METTLE_MODULE_LAST})
  string(JSON name GET "${METTLE_MODULES}" modules ${index} name)
  string(JSON kind GET "${METTLE_MODULES}" modules ${index} kind)
  set(target "${METTLE_TARGET_${name}}")
  if(kind STREQUAL "INTERFACE")
    set(visibility INTERFACE)
  else()
    set(visibility PUBLIC)
  endif()
  string(JSON count LENGTH "${METTLE_MODULES}" modules ${index} dependencies)
  if(count GREATER 0)
    math(EXPR last "${count} - 1")
    foreach(dep_index RANGE ${last})
      string(JSON dependency GET "${METTLE_MODULES}" modules ${index} dependencies ${dep_index})
      if(NOT DEFINED METTLE_TARGET_${dependency})
        message(FATAL_ERROR "Unknown dependency ${dependency} for ${name}")
      endif()
      target_link_libraries(${target} ${visibility} "${METTLE_TARGET_${dependency}}")
    endforeach()
  endif()
endforeach()
target_include_directories(mettle_backend_llvm SYSTEM PUBLIC ${LLVM_INCLUDE_DIRS})
target_link_libraries(mettle_backend_llvm PUBLIC ${METTLE_LLVM_LIBRARIES})
if(APPLE)
  target_compile_definitions(mettle_backend_llvm PRIVATE
    METTLE_DARWIN_DEPLOYMENT_TARGET="${METTLE_MACOS_DEPLOYMENT_TARGET}")
endif()
target_compile_definitions(mettle PRIVATE METTLE_VERSION="${PROJECT_VERSION}"
  METTLE_CXX_PATH="${CMAKE_CXX_COMPILER}" METTLE_SYSROOT_PATH="${CMAKE_OSX_SYSROOT}"
  METTLE_LIBRARY_PATH="${PROJECT_SOURCE_DIR}/library"
  METTLE_RUNTIME_PATH="$<TARGET_FILE:mettle_runtime>"
  METTLE_RUNTIME_TARGET="${METTLE_RUNTIME_TARGET}"
  METTLE_RUNTIME_SANITIZED=$<BOOL:${METTLE_ENABLE_SANITIZERS}>)
add_dependencies(mettle mettle_runtime)
target_compile_options(mettle PRIVATE -Wall -Wextra -Wpedantic -Werror)

include(CTest)
if(BUILD_TESTING)
  if(UNIX)
    add_executable(mettle-runtime-tests tests/runtime/panic.cpp)
    target_link_libraries(mettle-runtime-tests PRIVATE mettle_runtime)
    target_compile_options(mettle-runtime-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_test(NAME runtime.panic COMMAND mettle-runtime-tests)
    set_tests_properties(runtime.panic PROPERTIES TIMEOUT 120)
    add_executable(mettle-thread-tests tests/runtime/thread.cpp)
    find_package(Threads REQUIRED)
    target_link_libraries(mettle-thread-tests PRIVATE mettle_runtime Threads::Threads)
    target_compile_options(mettle-thread-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_test(NAME runtime.thread COMMAND mettle-thread-tests)
    set_tests_properties(runtime.thread PROPERTIES TIMEOUT 120)
    add_executable(mettle-cleanup-frame-tests tests/backend/cleanup_frame.cpp)
    target_link_libraries(mettle-cleanup-frame-tests PRIVATE mettle_backend_llvm)
    target_compile_options(mettle-cleanup-frame-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_dependencies(mettle-cleanup-frame-tests mettle_runtime)
    set(METTLE_CLEANUP_TEST_FLAGS "--target=${METTLE_RUNTIME_TARGET}" ${METTLE_LINKER_FLAGS})
    if(METTLE_ENABLE_SANITIZERS)
      list(APPEND METTLE_CLEANUP_TEST_FLAGS -fsanitize=address,undefined
                  -fno-sanitize-recover=all -fno-omit-frame-pointer)
    endif()
    add_test(NAME backend.cleanup-frame
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/backend/cleanup_frame.py"
                     "$<TARGET_FILE:mettle-cleanup-frame-tests>" "${CMAKE_CXX_COMPILER}"
                     "${PROJECT_SOURCE_DIR}/tests/backend/cleanup_frame_callbacks.cpp"
                     "$<TARGET_FILE:mettle_runtime>"
                     "${PROJECT_BINARY_DIR}/backend-cleanup-evidence"
                     ${METTLE_CLEANUP_TEST_FLAGS})
    add_executable(mettle-cleanup-program-tests tests/backend/cleanup_program.cpp)
    target_link_libraries(mettle-cleanup-program-tests PRIVATE mettle_backend_llvm mettle_pipeline)
    target_compile_options(mettle-cleanup-program-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_dependencies(mettle-cleanup-program-tests mettle_runtime)
    add_test(NAME backend.cleanup-program
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/backend/cleanup_frame.py"
                     --state-file
                     "$<TARGET_FILE:mettle-cleanup-program-tests>" "${CMAKE_CXX_COMPILER}"
                     "${PROJECT_SOURCE_DIR}/tests/backend/cleanup_program_callbacks.cpp"
                     "$<TARGET_FILE:mettle_runtime>"
                     "${PROJECT_BINARY_DIR}/backend-cleanup-program-evidence"
                     ${METTLE_CLEANUP_TEST_FLAGS})
    add_executable(mettle-cleanup-source-tests tests/backend/cleanup_source.cpp)
    target_link_libraries(mettle-cleanup-source-tests PRIVATE mettle_backend_llvm mettle_pipeline)
    target_compile_options(mettle-cleanup-source-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_dependencies(mettle-cleanup-source-tests mettle_runtime)
    add_test(NAME backend.cleanup-source
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/backend/cleanup_frame.py"
                     --source-trace
                     "$<TARGET_FILE:mettle-cleanup-source-tests>" "${CMAKE_CXX_COMPILER}"
                     "${PROJECT_SOURCE_DIR}/tests/backend/cleanup_source_callbacks.cpp"
                     "$<TARGET_FILE:mettle_runtime>"
                     "${PROJECT_BINARY_DIR}/backend-cleanup-source-evidence"
                     ${METTLE_CLEANUP_TEST_FLAGS})
    set_tests_properties(backend.cleanup-frame backend.cleanup-program backend.cleanup-source
                         PROPERTIES TIMEOUT 240)
    if(METTLE_ENABLE_SANITIZERS)
      set_tests_properties(backend.cleanup-frame backend.cleanup-program backend.cleanup-source
        PROPERTIES ENVIRONMENT
        "ASAN_OPTIONS=halt_on_error=1:abort_on_error=0:exitcode=99;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1:exitcode=99")
    endif()
    add_library(mettle_machine_callbacks STATIC
                tests/backend/machine_callbacks.c tests/backend/machine_unwind.cpp)
    set_target_properties(mettle_machine_callbacks PROPERTIES C_STANDARD 11
                          C_STANDARD_REQUIRED YES C_EXTENSIONS NO)
    target_compile_options(mettle_machine_callbacks PRIVATE -Wall -Wextra -Wpedantic -Werror)
    set(METTLE_MACHINE_TEST_FLAGS "")
    if(APPLE)
      list(APPEND METTLE_MACHINE_TEST_FLAGS "--sysroot=${CMAKE_OSX_SYSROOT}")
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      list(APPEND METTLE_MACHINE_TEST_FLAGS "--link-arg=-fuse-ld=lld")
    endif()
    if(METTLE_ENABLE_SANITIZERS)
      list(APPEND METTLE_MACHINE_TEST_FLAGS --sanitizers)
    endif()
    add_test(NAME backend.machine-interop
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/backend/machine.py"
                     "$<TARGET_FILE:mettle>" "${CMAKE_CXX_COMPILER}"
                     "$<TARGET_FILE:mettle_runtime>" "$<TARGET_FILE:mettle_machine_callbacks>"
                     "${PROJECT_BINARY_DIR}/machine-evidence" ${METTLE_MACHINE_TEST_FLAGS})
    set_tests_properties(backend.machine-interop PROPERTIES TIMEOUT 180)
    add_test(NAME backend.machine-memory-model
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/backend/memory.py"
                     "$<TARGET_FILE:mettle>" "${CMAKE_CXX_COMPILER}"
                     "${PROJECT_BINARY_DIR}/memory-model-evidence"
                     ${METTLE_MACHINE_TEST_FLAGS})
    set_tests_properties(backend.machine-memory-model PROPERTIES TIMEOUT 240)
    if(METTLE_ENABLE_SANITIZERS)
      set_tests_properties(backend.machine-memory-model PROPERTIES ENVIRONMENT
        "ASAN_OPTIONS=halt_on_error=1:abort_on_error=0:exitcode=99;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1:exitcode=99")
    endif()
  endif()
  add_executable(mettle-object-smoke tests/backend/object_smoke.cpp)
  target_link_libraries(mettle-object-smoke PRIVATE mettle_backend_llvm)
  target_compile_options(mettle-object-smoke PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME foundation.cli
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/foundation.py"
                   cli "$<TARGET_FILE:mettle>")
  add_test(NAME foundation.object-link-run
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/foundation.py"
                   object "$<TARGET_FILE:mettle-object-smoke>" "${CMAKE_C_COMPILER}"
                   ${METTLE_LINKER_FLAGS})
  add_test(NAME foundation.backend-errors
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/foundation.py"
                   errors "$<TARGET_FILE:mettle-object-smoke>")
  add_executable(mettle-ir-tests tests/ir/verify.cpp)
  target_link_libraries(mettle-ir-tests PRIVATE mettle_ir mettle_analysis mettle_pipeline)
  target_compile_options(mettle-ir-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.boundaries COMMAND mettle-ir-tests)
  add_executable(mettle-consteval-tests tests/consteval/target_width.cpp)
  target_link_libraries(mettle-consteval-tests PRIVATE mettle_pipeline)
  target_compile_options(mettle-consteval-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.consteval-target COMMAND mettle-consteval-tests)
  set_tests_properties(compiler.consteval-target PROPERTIES TIMEOUT 120)
  add_executable(mettle-module-tests tests/modules.cpp)
  target_link_libraries(mettle-module-tests PRIVATE mettle_pipeline mettle_resolution)
  target_compile_options(mettle-module-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.modules-memory COMMAND mettle-module-tests)
  add_test(NAME compiler.modules-source
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/modules.py"
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/module-evidence")
  add_test(NAME packages.resolution
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/packages.py"
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/packages-evidence"
                   "${PROJECT_SOURCE_DIR}/tests/packages")
  set_tests_properties(packages.resolution PROPERTIES TIMEOUT 600)
  add_test(NAME library.alloc
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/alloc.py"
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/alloc-evidence"
                   "${PROJECT_SOURCE_DIR}/tests/alloc")
  set_tests_properties(library.alloc PROPERTIES TIMEOUT 900)
  add_test(NAME library.std
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/std.py"
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/std-evidence"
                   "${PROJECT_SOURCE_DIR}/tests/std")
  set_tests_properties(library.std PROPERTIES TIMEOUT 1800)
  add_test(NAME library.core
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/modules.py"
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/library-evidence" library)
  set_tests_properties(compiler.modules-memory PROPERTIES TIMEOUT 120)
  set_tests_properties(compiler.modules-source PROPERTIES TIMEOUT 600)
  set_tests_properties(library.core PROPERTIES TIMEOUT 3600)
  set_tests_properties(compiler.boundaries PROPERTIES TIMEOUT 120)
  set_tests_properties(foundation.cli foundation.object-link-run foundation.backend-errors
                       PROPERTIES TIMEOUT 120)
  # One file per case under tests/source, run by a parallel runner. Each test
  # reserves its worker count so `ctest -jN` does not oversubscribe the host.
  cmake_host_system_information(RESULT METTLE_SOURCE_TEST_JOBS QUERY NUMBER_OF_LOGICAL_CORES)
  foreach(kind run fail)
    add_test(NAME source.${kind}
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/source.py"
                     ${kind} "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/source-evidence"
                     -j ${METTLE_SOURCE_TEST_JOBS})
    set_tests_properties(source.${kind} PROPERTIES TIMEOUT 1800
                         PROCESSORS ${METTLE_SOURCE_TEST_JOBS})
  endforeach()
  foreach(mode syntax fast-math broken-pipe)
    add_test(NAME probe.${mode}
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/probes.py"
                     "${mode}" "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/probe-evidence")
    set_tests_properties(probe.${mode} PROPERTIES TIMEOUT 180)
  endforeach()
  if(METTLE_ENABLE_SANITIZERS)
    add_test(NAME foundation.sanitizers
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/foundation.py"
                     sanitizers "$<TARGET_FILE:mettle>" "${CMAKE_CXX_COMPILER}"
                     ${METTLE_LINKER_FLAGS})
    set_tests_properties(foundation.sanitizers PROPERTIES TIMEOUT 120)
  endif()
endif()
