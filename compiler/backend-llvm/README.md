# Scalar LLVM backend

`emit_ir(verified, checks)` returns a complete textual LLVM module for a
`VerifiedProgram` with an entry point. Function IDs are local to the artifact;
the only exported symbol is hosted `main`. Calls preserve instruction order,
use `i32` and `i1` for scalar values, and erase `Unit` operands without erasing
the calls that produced them. Non-`Unit` block parameters become phi nodes;
guarded predecessors enter those phis from their final continuation. Ordered
comparisons are signed for `i32`, unsigned for `bool`, and treat `Unit` as
equal to itself.

With `OverflowChecks.Off`, add, subtract and multiply wrap at 32 bits.
With `OverflowChecks.On`, signed overflow panics. Signed division and
remainder panic on zero or `i32.MIN / -1` (including remainder) in either mode.
Artifacts with panic paths require `mettle_rt_panic` and `mettle_rt_main`
from `libmettle_runtime.a`, linked with the C++ driver for exception support.
Uncaught numeric panics abort (`SIGABRT`), as in the bootstrap backend.
Entryless programs are not supported.

`link_executable(clang, input, output, runtime)` compiles staged textual LLVM IR
and links a hosted Linux x86-64 executable. Pass the pinned Clang path (with
`ld.lld` next to it), staged input and output paths, and `libmettle_runtime.a`.
The Clang invocation uses C++ linkage and inherits tool diagnostics. A failed
tool exit or signal returns `LinkError.Failed(ExitStatus)`; path and process
errors (including a missing Clang executable or runtime archive) return
`LinkError.Io(io.Error)`. The caller owns staging and publication.
