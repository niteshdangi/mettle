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
                               Core CodeGen MC Passes Instrumentation X86 AArch64
                               WebAssembly ARM)

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

# Documented macOS baseline (docs/spec/platform-contracts.md) for the runtime and
# for the objects the compiler emits, so linking never sees the host kernel
# version. The compiler itself is built for the host and is not affected.
set(METTLE_MACOS_DEPLOYMENT_TARGET "15.0" CACHE STRING
    "Minimum macOS version of the Darwin ARM64 runtime and emitted objects")
set(METTLE_RUNTIME_SOURCES runtime/panic.cpp runtime/panic.h
  runtime/alloc.cpp runtime/alloc.h runtime/sys.cpp runtime/sys.h
  runtime/thread.cpp runtime/thread.h)
add_library(mettle_runtime STATIC ${METTLE_RUNTIME_SOURCES})
set_target_properties(mettle_runtime PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(APPLE)
  target_compile_options(mettle_runtime PRIVATE
    "-mmacosx-version-min=${METTLE_MACOS_DEPLOYMENT_TARGET}")
endif()
target_compile_options(mettle_runtime PRIVATE -Wall -Wextra -Wpedantic -Werror)
function(add_mettle_runtime_variant target sanitizer)
  add_library(${target} STATIC ${METTLE_RUNTIME_SOURCES})
  set_target_properties(${target} PROPERTIES POSITION_INDEPENDENT_CODE ON)
  if(APPLE)
    target_compile_options(${target} PRIVATE
      "-mmacosx-version-min=${METTLE_MACOS_DEPLOYMENT_TARGET}")
  endif()
  # Override the compiler's own ASan/UBSan mode so these archives contain only
  # the instrumentation selected by their name.
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror
    -fno-sanitize=address,undefined -fsanitize=${sanitizer}
    -fno-sanitize-recover=all -fno-omit-frame-pointer)
endfunction()
add_mettle_runtime_variant(mettle_runtime_asan address)
add_mettle_runtime_variant(mettle_runtime_tsan thread)
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

find_package(Python3 3.9 REQUIRED COMPONENTS Interpreter)
function(mettle_component name kind directory)
  file(GLOB_RECURSE files CONFIGURE_DEPENDS
       "${PROJECT_SOURCE_DIR}/bootstrap/${directory}/*.c"
       "${PROJECT_SOURCE_DIR}/bootstrap/${directory}/*.cc"
       "${PROJECT_SOURCE_DIR}/bootstrap/${directory}/*.cpp"
       "${PROJECT_SOURCE_DIR}/bootstrap/${directory}/*.cxx"
       "${PROJECT_SOURCE_DIR}/bootstrap/${directory}/*.h"
       "${PROJECT_SOURCE_DIR}/bootstrap/${directory}/*.hpp")
  if(kind STREQUAL "EXECUTABLE")
    add_executable(mettle ${files})
    set(target mettle)
  else()
    add_library(mettle_${name} ${kind} ${files})
    set(target mettle_${name})
  endif()
  if(kind STREQUAL "INTERFACE")
    target_include_directories(${target} INTERFACE "${PROJECT_SOURCE_DIR}/bootstrap")
  else()
    target_include_directories(${target} PUBLIC "${PROJECT_SOURCE_DIR}/bootstrap")
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
  endif()
endfunction()

mettle_component(support INTERFACE support)
mettle_component(source STATIC source)
mettle_component(diagnostics INTERFACE diagnostics)
mettle_component(syntax STATIC syntax)
mettle_component(expansion STATIC expansion)
mettle_component(documentation STATIC documentation)
mettle_component(resolution STATIC resolution)
mettle_component(types STATIC types)
mettle_component(metadata STATIC metadata)
mettle_component(places STATIC places)
mettle_component(consteval STATIC consteval)
mettle_component(semantics STATIC semantics)
mettle_component(ir STATIC ir)
mettle_component(lowering STATIC lowering)
mettle_component(analysis STATIC analysis)
mettle_component(instances STATIC instances)
mettle_component(pipeline STATIC pipeline)
mettle_component(lint STATIC lint)
mettle_component(lsp STATIC lsp)
mettle_component(cleanup STATIC cleanup)
mettle_component(backend_llvm STATIC backend/llvm)
mettle_component(packages STATIC packages)
mettle_component(driver EXECUTABLE driver)

target_link_libraries(mettle_diagnostics INTERFACE mettle_source mettle_support)
target_link_libraries(mettle_syntax PUBLIC mettle_source mettle_diagnostics mettle_support)
target_link_libraries(mettle_expansion PUBLIC mettle_syntax mettle_source mettle_diagnostics mettle_support)
target_link_libraries(mettle_documentation PUBLIC mettle_syntax mettle_source mettle_diagnostics mettle_support)
target_link_libraries(mettle_resolution PUBLIC mettle_syntax mettle_expansion mettle_source mettle_diagnostics mettle_support)
target_link_libraries(mettle_types PUBLIC mettle_support)
target_link_libraries(mettle_metadata PUBLIC mettle_types mettle_source mettle_support)
target_link_libraries(mettle_places PUBLIC mettle_types)
target_link_libraries(mettle_consteval PUBLIC mettle_syntax mettle_types mettle_diagnostics mettle_source mettle_support)
target_link_libraries(mettle_semantics PUBLIC mettle_syntax mettle_resolution mettle_types mettle_metadata mettle_places mettle_consteval mettle_diagnostics mettle_support)
target_link_libraries(mettle_ir PUBLIC mettle_source mettle_types mettle_metadata mettle_places mettle_diagnostics mettle_support)
target_link_libraries(mettle_lowering PUBLIC mettle_semantics mettle_ir mettle_types mettle_diagnostics mettle_support)
target_link_libraries(mettle_analysis PUBLIC mettle_ir mettle_places mettle_support mettle_diagnostics)
target_link_libraries(mettle_instances PUBLIC mettle_ir mettle_types mettle_diagnostics mettle_support)
target_link_libraries(mettle_pipeline PUBLIC mettle_syntax mettle_resolution mettle_semantics mettle_ir mettle_types mettle_lowering mettle_analysis mettle_instances mettle_cleanup mettle_diagnostics)
target_link_libraries(mettle_lint PUBLIC mettle_semantics mettle_syntax mettle_types mettle_source mettle_support)
target_link_libraries(mettle_lsp PUBLIC mettle_syntax mettle_expansion mettle_resolution mettle_pipeline mettle_types mettle_source mettle_diagnostics mettle_support)
target_link_libraries(mettle_cleanup PUBLIC mettle_ir mettle_types mettle_places mettle_support)
target_link_libraries(mettle_backend_llvm PUBLIC mettle_ir mettle_cleanup mettle_types mettle_source mettle_support)
target_link_libraries(mettle_packages PUBLIC mettle_source mettle_diagnostics mettle_support)
target_compile_definitions(mettle_packages PRIVATE METTLE_VERSION="${PROJECT_VERSION}")
target_link_libraries(mettle PUBLIC mettle_source mettle_diagnostics mettle_syntax mettle_expansion mettle_documentation mettle_resolution mettle_packages mettle_ir mettle_types mettle_semantics mettle_lint mettle_pipeline mettle_lsp mettle_backend_llvm mettle_support)
target_include_directories(mettle_backend_llvm SYSTEM PUBLIC ${LLVM_INCLUDE_DIRS})
target_link_libraries(mettle_backend_llvm PUBLIC ${METTLE_LLVM_LIBRARIES})
# The pinned Linux LLVM release is built without RTTI; its integration
# boundary (driver and LLVM adapter) must match it to link LLVM vtables.
if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(mettle_backend_llvm PRIVATE -fno-rtti)
  target_compile_options(mettle PRIVATE -fno-rtti)
endif()
if(APPLE)
  target_compile_definitions(mettle_backend_llvm PRIVATE
    METTLE_DARWIN_DEPLOYMENT_TARGET="${METTLE_MACOS_DEPLOYMENT_TARGET}")
endif()
target_compile_definitions(mettle PRIVATE METTLE_VERSION="${PROJECT_VERSION}"
  METTLE_CXX_PATH="${CMAKE_CXX_COMPILER}" METTLE_SYSROOT_PATH="${CMAKE_OSX_SYSROOT}"
  METTLE_LIBRARY_PATH="${PROJECT_SOURCE_DIR}/library"
  METTLE_RUNTIME_PATH="$<TARGET_FILE:mettle_runtime>"
  METTLE_RUNTIME_ASAN_PATH="$<TARGET_FILE:mettle_runtime_asan>"
  METTLE_RUNTIME_TSAN_PATH="$<TARGET_FILE:mettle_runtime_tsan>"
  METTLE_RUNTIME_TARGET="${METTLE_RUNTIME_TARGET}"
  METTLE_RUNTIME_SANITIZED=$<BOOL:${METTLE_ENABLE_SANITIZERS}>)
add_dependencies(mettle mettle_runtime mettle_runtime_asan mettle_runtime_tsan)
target_compile_options(mettle PRIVATE -Wall -Wextra -Wpedantic -Werror)

# Like Rust's test harness, tests are never killed for running long;
# only CI job limits bound a run.
set(DART_TESTING_TIMEOUT 0)
include(CTest)
if(BUILD_TESTING)
  cmake_host_system_information(RESULT METTLE_HOST_TEST_JOBS QUERY NUMBER_OF_LOGICAL_CORES)
  math(EXPR METTLE_DEFAULT_TEST_SHARDS "2 * ${METTLE_HOST_TEST_JOBS}")
  set(METTLE_TEST_SHARDS ${METTLE_DEFAULT_TEST_SHARDS} CACHE STRING
      "Independent CTest units per fixture suite")
  if(NOT "${METTLE_TEST_SHARDS}" MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "METTLE_TEST_SHARDS must be a positive integer")
  endif()
  function(mettle_add_sharded_test name runner)
    math(EXPR last_shard "${METTLE_TEST_SHARDS} - 1")
    foreach(shard RANGE ${last_shard})
      add_test(NAME "${name}.${shard}"
               COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/${runner}" ${ARGN}
                       --shard-index ${shard} --shard-count ${METTLE_TEST_SHARDS} -j 1)
      set_tests_properties("${name}.${shard}" PROPERTIES PROCESSORS 1)
    endforeach()
  endfunction()
  add_executable(mettle-library-declaration-tests tests/semantics/library_test.cpp)
  target_link_libraries(mettle-library-declaration-tests PRIVATE mettle_pipeline mettle_metadata)
  target_compile_options(mettle-library-declaration-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.library-declarations COMMAND mettle-library-declaration-tests)
  add_executable(mettle-ir-codec-tests tests/ir/codec_test.cpp)
  target_link_libraries(mettle-ir-codec-tests PRIVATE mettle_ir mettle_metadata)
  target_compile_options(mettle-ir-codec-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME ir.codec COMMAND mettle-ir-codec-tests)
  add_executable(mettle-library-archive-tests
    tests/packages/library_archive.cpp bootstrap/driver/library_archive.cpp
    bootstrap/driver/library_cache.cpp)
  target_link_libraries(mettle-library-archive-tests PRIVATE mettle_metadata mettle_packages mettle_diagnostics)
  target_compile_options(mettle-library-archive-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.library-archive COMMAND mettle-library-archive-tests)
  add_executable(mettle-type-graph-tests tests/types/type_graph.cpp)
  target_link_libraries(mettle-type-graph-tests PRIVATE mettle_metadata)
  target_compile_options(mettle-type-graph-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.type-graph COMMAND mettle-type-graph-tests)
  if(UNIX)
    add_executable(mettle-runtime-tests tests/runtime/panic.cpp)
    target_link_libraries(mettle-runtime-tests PRIVATE mettle_runtime)
    target_compile_options(mettle-runtime-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_test(NAME runtime.panic COMMAND mettle-runtime-tests)
    add_executable(mettle-thread-tests tests/runtime/thread.cpp)
    find_package(Threads REQUIRED)
    target_link_libraries(mettle-thread-tests PRIVATE mettle_runtime Threads::Threads)
    target_compile_options(mettle-thread-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      target_link_options(mettle-thread-tests PRIVATE
        "LINKER:--wrap=nanosleep"
        "LINKER:--wrap=clock_gettime"
        "LINKER:--wrap=accept4"
        "LINKER:--wrap=socket"
        "LINKER:--wrap=pipe"
        "LINKER:--wrap=pipe2"
        "LINKER:--wrap=poll"
        "LINKER:--wrap=pthread_mutex_init"
        "LINKER:--wrap=pthread_mutex_destroy"
        "LINKER:--wrap=pthread_condattr_init"
        "LINKER:--wrap=pthread_condattr_setclock"
        "LINKER:--wrap=pthread_condattr_destroy"
        "LINKER:--wrap=pthread_cond_init"
        "LINKER:--wrap=pthread_cond_destroy"
        "LINKER:--wrap=pthread_cond_timedwait")
    endif()
    add_test(NAME runtime.thread COMMAND mettle-thread-tests)
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
    mettle_add_sharded_test(backend.machine-interop tests/backend/machine.py
                     "$<TARGET_FILE:mettle>" "${CMAKE_CXX_COMPILER}"
                     "$<TARGET_FILE:mettle_runtime>" "$<TARGET_FILE:mettle_machine_callbacks>"
                     "${PROJECT_BINARY_DIR}/machine-evidence" ${METTLE_MACHINE_TEST_FLAGS})
    add_test(NAME backend.machine-memory-model
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/backend/memory.py"
                     "$<TARGET_FILE:mettle>" "${CMAKE_CXX_COMPILER}"
                     "${PROJECT_BINARY_DIR}/memory-model-evidence"
                     ${METTLE_MACHINE_TEST_FLAGS})
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
  add_executable(mettle-macro-library-tests tests/expansion/macro_library.cpp)
  target_link_libraries(mettle-macro-library-tests PRIVATE mettle_expansion)
  target_compile_options(mettle-macro-library-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.macro-library COMMAND mettle-macro-library-tests)
  add_executable(mettle-module-tests tests/modules.cpp)
  target_link_libraries(mettle-module-tests PRIVATE mettle_pipeline mettle_resolution)
  target_compile_options(mettle-module-tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME compiler.modules-memory COMMAND mettle-module-tests)
  add_test(NAME compiler.modules-source
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/modules.py"
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/module-evidence")
  mettle_add_sharded_test(packages.resolution tests/packages.py
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/packages-evidence"
                   "${PROJECT_SOURCE_DIR}/tests/packages")
  mettle_add_sharded_test(library.alloc tests/alloc.py
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/alloc-evidence"
                   "${PROJECT_SOURCE_DIR}/tests/alloc")
  mettle_add_sharded_test(library.std tests/std.py
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/std-evidence"
                   "${PROJECT_SOURCE_DIR}/tests/std")
  mettle_add_sharded_test(library.core tests/modules.py
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/library-evidence" library)
  foreach(kind run fail)
    mettle_add_sharded_test(source.${kind} tests/source.py
                     ${kind} "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/source-evidence")
  endforeach()
  foreach(mode syntax fast-math broken-pipe sanitizers)
    add_test(NAME probe.${mode}
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/probes.py"
                     "${mode}" "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/probe-evidence")
  endforeach()
  add_test(NAME tooling.contracts
           COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tools/test_tooling.py"
                   "$<TARGET_FILE:mettle>" "${PROJECT_BINARY_DIR}/tooling-evidence")
  if(METTLE_ENABLE_SANITIZERS)
    add_test(NAME foundation.sanitizers
             COMMAND Python3::Interpreter "${PROJECT_SOURCE_DIR}/tests/foundation.py"
                     sanitizers "$<TARGET_FILE:mettle>" "${CMAKE_CXX_COMPILER}"
                     ${METTLE_LINKER_FLAGS})
  endif()
  # Test builds never use the user's build cache.
  get_property(METTLE_TESTS DIRECTORY PROPERTY TESTS)
  set_property(TEST ${METTLE_TESTS} APPEND PROPERTY ENVIRONMENT
               "METTLE_CACHE_DIR=${PROJECT_BINARY_DIR}/test-cache")
  set(METTLE_TEST_CACHE_LIMIT_KIB 2097152 CACHE STRING
      "Shared fixture cache budget in KiB")
  if(NOT "${METTLE_TEST_CACHE_LIMIT_KIB}" MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "METTLE_TEST_CACHE_LIMIT_KIB must be a positive integer")
  endif()
  set(METTLE_SHARED_CACHE_TESTS ${METTLE_TESTS})
  list(FILTER METTLE_SHARED_CACHE_TESTS EXCLUDE REGEX "^packages\\.resolution\\.")
  set_property(TEST ${METTLE_SHARED_CACHE_TESTS} APPEND PROPERTY ENVIRONMENT
               "METTLE_CACHE_LIMIT_KIB=${METTLE_TEST_CACHE_LIMIT_KIB}")
endif()
