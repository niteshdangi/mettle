# Decision register and readiness

## Accepted by the user or inherited from the accepted blueprint

| ID | Decision |
| --- | --- |
| D01 | Language name: Mettle |
| D02 | Full agreed Rust baseline capability in V1, not Rust source/ABI compatibility |
| D03 | C++/LLVM V1; substantive self-hosting V1.1; own production backend V1.2 |
| D04 | Static borrowing, explicit ownership, native syntax, no compulsory GC/sandbox |
| D05 | Rust-aligned configurable integer-overflow profile defaults |
| D06 | Shared handles move by default; additional owners require explicit retention |
| D07 | Known copyable ordinary parameters receive values; non-copy resources borrow |
| D08 | Generic defaults use declaration-known constraints; unconstrained T borrows |
| D09 | Named structs/enums explicitly opt into Copy; built-in aggregates are structural |
| D10 | Runtime must match or beat Rust per agreed workload; measure builds/memory separately |
| D11 | Routine decisions are delegated; do not stop for approval after every item |
| D12 | Every material comparison explains Rust behavior, likely faster option and uncertainty |
| D13 | Function results use optional `: Type`, not `->`; omission infers from body returns/tails, not callers. Explicit annotations remain checked contracts, including for public definitions. |
| D14 | `Unit` is a predeclared type name, not a keyword; `()` is its sole value, not a second type spelling. Omitted results may infer Unit but do not default to it. |
| D15 | `Never` is the predeclared uninhabited type, replacing the lowercase built-in spelling; it remains distinct from Unit. Prefer `let _ = expression` for intentional non-Unit discard; semicolon semantics remain unchanged. |

The shared-assignment rule supersedes the original v0.21 implicit-retain rule.
The runtime gate supersedes its greater-than-10-percent investigation trigger.
The finalized Word blueprint predates the detailed parameter and copyability
decisions; these source documents carry those subsequent refinements.

## Routine selections made under delegation

- Explicit take invalidates its source even for Copy; ordinary Copy passing
  leaves the source usable. No runtime byte clearing is implied.
- let/var, declaration-known access modes, static initialization, and
  destructor-constrained partial moves follow the documented core rules.
- Result inference solves recursive dependencies or requests annotations;
  callable types/bodyless declarations retain explicit results. Error effects
  and ambiguous borrow-source relationships are not inferred from bodies.
  The result delimiter applies consistently to methods, closures and foreign
  signatures. These refinements supersede the earlier mandatory-arrow grammar.
- Operand and assignment sequencing preserve the Rust-aligned model, including
  the initial primitive/overloaded compound-assignment distinction.
- `.mt`, `copy type`, `Copy`, and labeled `Type(...)` calls are working grammar
  conventions, not public compatibility promises.
- Single-file scalar native execution on Linux x86-64 is the first source
  compilation milestone (I02); products, ownership and generics follow without
  shrinking V1.
- C++20, CMake, Ninja, Clang, and fixture-driven tests are the initial toolchain
  direction. toolchain-pins.json selects immutable source commits; I01 adds
  archive locks, installed artifact identities and verified native macOS
  Debug/Release builds with Linux target execution.
- specification-annex.md selects numeric conversions, higher-ranked solving,
  closure/pattern cleanup, macro phases, layouts, assembly and dispatch rules.
- memory-and-concurrency.md selects validity/provenance/atomic contracts and
  poll-scoped borrowed-task execution epochs, without claiming a safety proof.
- language-grammar.md composes the extended productions; reference-profiles.md
  selects deployment/SDK, ABI, linker, Wasm and freestanding design baselines.
- library-surface.md and its source-backed operation inventory specify native
  library contracts, including sealed/default/compiler-controlled protocols.
- tooling-and-packages.md selects manifest/resolver, cache, test/doctest,
  formatting, editor and debugger contracts.
- performance.md selects paired log-ratio intervals, family-wise error control,
  a 0.5-percent precision target and separate pilot/release samples.

## Implementation and product gates

| Work | Blocks | Resolution |
| --- | --- | --- |
| Grammar conflict/separator validation | Claim of parser-ready full grammar | I02-I05 check implemented scalar, product, composition and generic syntax; future constructs remain gated by their owning milestones |
| Scalar lowering | Full scalar operation matrix | I02 executes the selected i32/bool/Unit subset and profile failures; other widths/floats remain I06 |
| CFG joins, loans, temporary/drop table | Sound ownership compiler | I03-I05 check implemented move/loan/drop transitions and exceptional paths; passing cases are not a full soundness proof |
| Exceptional replacement and recovery | Safe panic catch around resources | I03 native cleanup probes validate replacement restoration before resumed access; public panic APIs remain later work |
| Native declarations and full source cfg expansion | Implemented library parity | Typecheck/execute each applicable native contract, including source branches absent from rendered docs |
| LLVM/compiler/sysroot artifact locks | Reproducible native build | I01 records archive/tool/sysroot identities and same-environment clean rebuilds; cross-machine/release reproducibility remains later work |
| Linux x86-64 runner | First-target execution evidence | I01-I05 cross-emitted source and cleanup objects link and execute under the actual Linux kernel; Linux-host compiler qualification remains separate |
| Generic/interface/region checker | Advanced type-system claims | I05 solver, coherence, region and dispatch cases pass native/sanitized and Linux target qualification within the recorded scope |
| Memory/provenance and async containment | Unsafe/async safety claim | Model/review and execute the selected mechanisms |
| OS/SDK/WASI/board execution | Supported-target claims | Probe selected reference profiles and publish release evidence |
| Benchmark pilot and fixed release experiment | Runtime release verdict | Apply the specified plan with actual controlled measurements |
| Project license | Public open-source licensing/distribution | Separate owner decision; no invented approval |
| Registry governance and public stabilization | Public service/compatibility promises | Owner decisions before launch; selected pre-implementation syntax is not a public stability guarantee |

## Documentation and implementation boundary

The specification pack covers core and advanced rules, composed grammar,
examples, all 107 capability owners, the pinned library operation contracts,
toolchain/profile selections, tooling and the measurement/release plan.
[specification-status.md](specification-status.md) defines the completion gate
and binds its evidence to the current validation result.

The original documentation task closed before implementation was authorized.
I01 implements the compiler foundation; I02 qualifies a scalar source compiler
with native macOS and Linux target execution/diagnostic evidence. Closing the documentation
gate does not prove a parser conflict-free, declarations coherent, the memory
model sound, targets supported or runtime competitive. Nor does it choose the
project license or revive a rejected language-identity proposal.

No arbitrary calendar dates or staffing estimates are included. Estimate from
measured prototype progress and actual team capacity. Do not create a public
repository, install tools, choose a legal license, or reserve domains merely
because a planning document lists them.
