# Scalar LLVM backend

`emit_ir(verified, checks)` returns a complete textual LLVM module for a
`VerifiedProgram` with an entry point. Function IDs are local to the artifact;
the only exported symbol is hosted `main`. Calls preserve instruction order,
use `i32` and `i1` for scalar values, and erase `Unit` operands without erasing
the calls that produced them.

With `OverflowChecks.Off`, add, subtract and multiply wrap at 32 bits.
`OverflowChecks.On` rejects these operations until checked lowering exists.
Division and remainder are rejected in both modes. These errors retain the
instruction span. Entryless programs are not supported. Target selection,
LLVM verification, object emission and linking are not part of this API.

From the repository root, run the focused rejection and native artifact tests
on Linux with the bootstrap compiler and pinned LLVM:

```sh
export METTLE=/path/to/mettle LLVM_BIN=/path/to/pinned/llvm/bin
sh compiler/backend-llvm/tests/run.sh debug
sh compiler/backend-llvm/tests/run.sh release
```
