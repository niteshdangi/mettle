# Scalar LLVM backend

`emit_ir(verified, checks)` returns a complete textual LLVM module for a
`VerifiedProgram` with an entry point. Function IDs are local to the artifact;
the only exported symbol is hosted `main`. Calls preserve instruction order,
use `i32` and `i1` for scalar values, and erase `Unit` operands without erasing
the calls that produced them.

With `OverflowChecks.Off`, add, subtract and multiply wrap at 32 bits.
With `OverflowChecks.On`, signed overflow panics. Signed division and
remainder panic on zero or `i32.MIN / -1` (including remainder) in either mode.
Artifacts with panic paths require `mettle_rt_panic` and `mettle_rt_main`
from `libmettle_runtime.a`, linked with the C++ driver for exception support.
Uncaught numeric panics abort (`SIGABRT`), as in the bootstrap backend.
Entryless programs are not supported. Target selection, LLVM verification,
object emission and linking are not part of this API.

From the repository root, run the cross-module artifact smoke test on Linux
with the bootstrap compiler and pinned LLVM:

```sh
export METTLE=/path/to/mettle LLVM_BIN=/path/to/pinned/llvm/bin
sh compiler/backend-llvm/tests/run.sh debug
sh compiler/backend-llvm/tests/run.sh release
```
