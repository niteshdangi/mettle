# Platform and feature contracts

Status: selected profiles and qualification gates. Support evidence is recorded
in [implementation-plan.md](../process/implementation-plan.md).

## 1. Target profile selection

| Profile | Initial environment direction | Required validation |
| --- | --- | --- |
| Linux x86-64 | GNU/Linux ELF and system C ABI; first execution target | Startup, C calls, layout, arithmetic, debug and unwind |
| Linux ARM64 | GNU/Linux ELF and AArch64 C ABI | Atomics, alignment, TLS, cross-language calls |
| Windows x86-64 | MSVC-compatible C ABI and PE/COFF | CRT integration, stack/unwind, DLLs, TLS, debugger |
| macOS ARM64 | Apple platform ABI and Mach-O | SDK link, unwind, dynamic loading, debugger |
| Android ARM64 | NDK platform ABI and Bionic | API-level symbols, startup/library integration, JNI bridge |
| WebAssembly hosted | wasm32 WASI profile, beginning with Preview 1 | Imports, memory, supported I/O and panic behavior |
| WebAssembly non-hosted | wasm32 core/alloc with explicit embedder imports | No accidental OS/runtime dependency |
| Freestanding | Core without OS or required allocator | Startup, panic handler, linker layout and volatile operations |

These choices select the supported-profile obligations, not every target triple
recognized by the backend.
WASI is not a promise of browser DOM APIs or native process/thread facilities.
Browser embedding and WASI services have separate imports. Unsupported target
capabilities need explicit diagnostics and profile applicability in the matrix.

[Reference profiles](#8-reference-profiles) select OS/SDK/API baselines, WASI
runtime, CPU baselines, linker policy and a concrete freestanding board model.
Support/reproducibility claims require installed hashes and build/execution probes.

For each profile record endianness, pointer width, scalar/aggregate alignment,
calling convention, register/stack passing, stack alignment, atomics available,
TLS, unwind strategy, object/debug format, entry point, allocator, library layers,
linker/sysroot identity, and positive/negative integration fixtures.

## 2. ABI contract gates

C interoperability requires round trips in both directions for scalars, small and
large structs, nested aggregates, pointers, callbacks/context pointers, and
ownership-bearing opaque handles. Layout tests alone do not validate calling
conventions. Include booleans, narrow integer extension, floats, and zero-sized
language values whose C boundary needs an explicit representation.

No unwinding crosses an ordinary incompatible foreign boundary. Translate typed
errors into declared foreign results. A compatible unwind ABI needs a separately
validated contract; abort is not interchangeable with cleanup.

Specify who allocates/frees, callback lifetime, reentrancy, thread affinity,
buffer length/capacity, and ownership on every failure path. Generated adapters
must not imply safety beyond these conditions.

Compare bridges with Rust performing the same ownership/type translation.

## 3. Generic/interface contract gate

Before implementing broad interfaces, define:

- Constraint satisfaction and declared generic-body checking.
- Associated type/constant equality and generic associated views.
- Coherence and explicit adapter identity for foreign pairs.
- Receiver mode and dispatchability of each erased method.
- Sized/unsized results, generic methods, and opaque return identity.
- Concrete versus erased async return storage and explicit allocation.

Concrete calls monomorphize by default; explicit `any` uses runtime dispatch.
Ownership mode selection uses no runtime type tests.

## 4. Outcomes and optionals contract gate

Native optional presence and tagged outcomes must preserve nested alternatives,
including an outcome whose success payload is another outcome and an optional
whose present payload is absent. Specify match modes, extraction, mutation, and
cleanup without implicit retention.

Throwing calls and stored outcomes may share representation but remain different
source contracts. Define local handling, propagation, capture, explicit mapping,
generic callbacks, function pointers, and async construction versus execution.
Do not introduce dynamic error erasure, stack traces, or allocations by default.

## 5. Memory and unsafe contract gate

Write explicit validity, initialization, alignment, provenance, aliasing,
interior mutation, and atomic rules before emitting corresponding optimizer
assumptions. Include references to zero-sized values, packed storage, raw-pointer
round trips, allocation reuse, and manual initialization/destruction.

Safe wrappers must remain sound when ordinary safe code forgets a value.
Use independent interpreter/model cases where feasible; sanitizer success alone
does not establish the memory model.

No mandatory runtime borrow checker substitutes for the selected static model.

## 6. Async and concurrency contract gate

Specify poll states, completion, wake registration/races, pinning, cancellation
outcomes, and ownership of suspended fields. A future constructs state first;
ordinary body effects happen when driven. Synchronous destruction cannot promise
asynchronous cleanup.

Borrowed spawned scopes require an explicit state machine covering child access
on another worker while the enclosing future is dropped, cancellation requested
but unfinished, panic, forgotten handles, and parent storage destruction. Do not
publish a safe API based solely on a destructor guard.

Define Transferable/Shareable derivation, unsafe implementations, negative
declarations, guard affinity, atomic orders, and local/shared reference counting.
Do not silently upgrade local counting or lock every shared payload.

Concrete futures require no per-await allocation; erased/spawned futures may
allocate. Compare matched executors, concurrency, I/O, cancellation and storage.

## 7. Library and tooling contract gate

Core must not import allocation, an executor, OS services, or a collector by
default. Allocated and hosted facilities declare their dependencies.

Collections need per-operation ownership, invalidation, allocation/failure, and
iteration guarantees. Package resolution needs identities, features, checksums,
lockfiles, offline behavior, and generated-input invalidation. Macro and build
execution must be visible; sandboxing/hermetic execution remain optional.

LSP and compiler share syntax/analysis representations, but error recovery does
not authorize execution of invalid programs. Formatter preservation includes
newline boundaries, block-tail values, modes, and comment placement.

## 8. Reference profiles

Design/test selections, not support claims or installed-artifact locks.
Source IDs: toolchain-pins.json. Reproducible execution also requires immutable
SDK/sysroot/package digests.

### Initial profile choices

| Profile | Reference environment | CPU / ABI / format | Initial panic policy |
| --- | --- | --- | --- |
| linux-x64 | Maintained Linux userland; record the installed distribution and libc identity per run | x86_64-unknown-linux-gnu; x86-64 baseline, no AVX requirement; SysV; ELF/DWARF | unwind and abort |
| linux-arm64 | Maintained Linux userland; record the installed distribution and libc identity per run | aarch64-unknown-linux-gnu; ARMv8-A baseline; AAPCS64; ELF/DWARF | unwind and abort |
| windows-x64 | Windows 11 24H2; Windows SDK 10.0.26100.0 | x86_64-pc-windows-msvc; Windows x64 C ABI; PE/COFF, CodeView/PDB | platform unwind and abort |
| macos-arm64 | macOS 15 deployment baseline; Xcode 16.2 SDK bundle | aarch64-apple-darwin; Apple ARM64 C ABI; Mach-O/DWARF | platform unwind and abort |
| android-arm64 | Android API 28 deployment baseline; NDK r27c | aarch64-linux-android; Bionic C ABI; ELF/DWARF | unwind and abort for compatible native boundaries |
| wasi32 | WASI Preview 1; wasi-sdk-25; Wasmtime 29.0.1 | wasm32-wasip1; single-threaded baseline; Wasm | abort/trap |
| wasm32-core | Explicit embedding; no WASI imports by default | wasm32-unknown-unknown; core plus optional allocator | embedder abort/trap |
| cortex-m3 | QEMU 9.2.0 lm3s6965evb model | thumbv7m-none-eabi; soft-float AAPCS32; ELF/DWARF | user panic handler, no hosted unwind |

Minimum interfaces do not assure later-OS compatibility. Validate maintained
installations with exact patch/build identities. Owner decision (2026-11-09):
Linux uses the installed host, recording distribution/libc/kernel; no Ubuntu or
glibc version mandate or inferred cross-distribution compatibility.
QEMU qualifies emulation, not physical hardware.

Use the platform's C ABI specifications for argument classification and aggregate
layout. Pointer widths are 64 bits for the five native hosted profiles and 32
bits for the Wasm and Cortex-M3 profiles. All selected profiles are little-endian.
Do not extrapolate big-endian support from these selections.

Baseline compiler invocations must not use host-native CPU tuning. Optional
target features are explicit and require dispatch or caller guarantees.
The list of native lock-free atomic widths is produced by profile probes and
the target ABI; the language cannot assume that every integer width is lock-free.

### Runtime and linkage selections

ELF profiles use LLD by default with the target sysroot's C startup and runtime.
Windows uses COFF LLD where compatible and the selected SDK/CRT interfaces;
record the actual redistributable/runtime package identity separately.
macOS uses its selected platform SDK/linker. WASI uses its explicit SDK startup
and imports. Freestanding uses a project-provided vector/startup object, linker
script and panic handler.

Hosted std requires platform services, not an implicit executor. Core-only
profiles exclude files/processes/hosted threads; record feature applicability
in the capability audit.

Compatible unwinding is a capability to implement and probe, not permission to
unwind through an ordinary C boundary. Early abort-only compiler milestones do
not fulfill the final native hosted unwind requirement.

### Required profile-lock fields

For every run record exact OS build/kernel, SDK/sysroot file hashes, compiler
and linker revisions, CRT/libc identity, startup objects, CPU feature mask,
allocator, panic mode, debug format, target libraries and command-line flags.
Compiler source revisions alone cannot substitute for this environment lock.

Missing artifact digests block reproducibility, not design selection. Do not
invent hashes or download SDKs just to complete a planning record.

### Sources

- https://learn.microsoft.com/en-us/windows/apps/windows-sdk/downloads
- https://developer.apple.com/documentation/xcode-release-notes/xcode-16_2-release-notes
- https://github.com/android/ndk/releases/tag/r27c
- https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-25
- https://github.com/bytecodealliance/wasmtime/releases/tag/v29.0.1
- https://github.com/qemu/qemu/tree/v9.2.0/docs/system/arm
