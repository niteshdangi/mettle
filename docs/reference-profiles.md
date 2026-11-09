# Selected reference profiles

These are fixed design/test-environment selections, not supported-platform
claims, recommendations of the latest releases, or verified installed artifacts.
The compiler/backend/build-tool source IDs are in toolchain-pins.json.
An execution manifest must add immutable SDK/sysroot/package digests before a
result can count as reproducible evidence.

## Initial profile choices

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

These identify minimum requested interfaces, not an assurance that every later
OS remains compatible. Production validation uses maintained installations with
exact patch/build identities; a version-family label is not an immutable lock.
Owner decision (2026-11-09): Linux qualification uses the installed host and
records its actual distribution, libc and kernel. No Ubuntu release or glibc
version is mandated, and no distro-specific compatibility claim follows from a
passing run on another environment.
QEMU tests are emulated-board evidence, not proof on physical hardware.

Use the platform's C ABI specifications for argument classification and aggregate
layout. Pointer widths are 64 bits for the five native hosted profiles and 32
bits for the Wasm and Cortex-M3 profiles. All selected profiles are little-endian.
Do not extrapolate big-endian support from these selections.

Baseline compiler invocations must not use host-native CPU tuning. Optional
target features are explicit and require dispatch or caller guarantees.
The list of native lock-free atomic widths is produced by profile probes and
the target ABI; the language cannot assume that every integer width is lock-free.

## Runtime and linkage selections

ELF profiles use LLD by default with the target sysroot's C startup and runtime.
Windows uses COFF LLD where compatible and the selected SDK/CRT interfaces;
record the actual redistributable/runtime package identity separately.
macOS uses its selected platform SDK/linker. WASI uses its explicit SDK startup
and imports. Freestanding uses a project-provided vector/startup object, linker
script and panic handler.

Hosted std requires those platform services, not an implicit async runtime.
Core-only profiles do not pretend to support files, processes or hosted thread
facilities. Feature-specific applicability is recorded in the capability audit.

Compatible unwinding is a capability to implement and probe, not permission to
unwind through an ordinary C boundary. Early abort-only compiler milestones do
not fulfill the final native hosted unwind requirement.

## Required profile-lock fields

For every run record exact OS build/kernel, SDK/sysroot file hashes, compiler
and linker revisions, CRT/libc identity, startup objects, CPU feature mask,
allocator, panic mode, debug format, target libraries and command-line flags.
Compiler source revisions alone cannot substitute for this environment lock.

A missing installed artifact digest blocks reproducibility claims, not the
selection of a documented target design. Do not invent SDK hashes or download
large SDKs solely to make a planning document look tested.

## Sources

- https://learn.microsoft.com/en-us/windows/apps/windows-sdk/downloads
- https://developer.apple.com/documentation/xcode-release-notes/xcode-16_2-release-notes
- https://github.com/android/ndk/releases/tag/r27c
- https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-25
- https://github.com/bytecodealliance/wasmtime/releases/tag/v29.0.1
- https://github.com/qemu/qemu/tree/v9.2.0/docs/system/arm
