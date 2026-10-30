# Native library surface and signature translation

Status: normative design. The frozen operation manifests enumerate contracts,
not implementations or compiled native declarations.

## 1. What specifies an operation

Each record in baseline/operations.jsonl.gz specifies a public exposure, associated
operation, or implementation relation. Its reference declaration, source span,
receiver/implementation context, runtime/const stability and target conditions
are part of the requirement. Translation below is recursive over that declaration;
it is not a request for the native parser to accept Rust source.

For unchanged operations the linked versioned contract supplies semantics,
complexity, panics, unsafe preconditions and allocation/invalidation guarantees.
The native mapping supplies the names, types, ownership and calling conventions.
An unimplemented operation is an implementation failure, not an unspecified API.
An actual contradiction is a specification defect and reopens the gate.

Source-keyed canonical IDs share definition evidence and implementation context.
They are not type-layout hashes. Public reexports of one declaration must refer
to the same native identity, not independently defined lookalike types.
Transparent source aliases remain aliases; newtypes remain distinct.
Macro-generated declarations retain their generated name/signature and owner/
implementation context, not merely the macro definition's source line.

## 2. Recursive translation rules

The manifest records the applicable rule IDs. T01 applies to every declaration;
the other IDs identify additional shapes present, not exclusive alternatives.

| ID | Native declaration contract |
| --- | --- |
| T01 | Preserve module/item identity, generic arity/defaults, visibility, tuple/array/product/variant structure, associated equalities, where obligations and return alternatives. Resolve all reexports before assigning type identity. Preserve explicit operator/constructor roles rather than interpreting their diagnostic names as functions. |
| T02 | Translate `&`/`&mut` and each source lifetime to read/mut views and named regions. Translate outlives and higher-ranked dependencies without collapsing independent regions. A by-value reference parameter consumes/reborrows a view as appropriate; it never consumes the backing owner. |
| T03 | Box/Arc/Rc/Weak/Pin map to heap/shared/local shared/weak/pinned owners or views. Preserve allocator identity, payload access, weak failure and pin projection rules. Explicit shared-owner Clone maps to retain; it never makes owner handles Copy. |
| T04 | Option/Result map recursively to optional/stored outcome; source unit maps to native `Unit`, with `()` as its value, and source never maps to native `Never`. Unit/Never and nested alternatives remain distinct. Preserve mapping, transpose, extraction and iteration operations. A throwing convenience wrapper cannot replace the stored-outcome operation. |
| T05 | Translate a callable's parameter access modes, output, failure and regions; native result annotations use `: Type`, including `: Unit`. Callable types/bodyless declarations keep explicit results; inferred definitions must resolve to the same contract. Fn/FnMut/FnOnce become read/mutate/consume-callable capabilities. By-value non-Copy parameters are explicitly consuming, not silently borrowed under the native default. |
| T06 | Concrete impl-Trait parameters become independently inferred generics; opaque returns have declaration identity. Dyn values become explicitly erased interface values with the same associated bindings/regions; no implicit allocation is added. |
| T07 | Translate `for<'r>` to `for<region r>` with fresh rigid universes and leak checks. No monomorphization-time ownership privileges. |
| T08 | Preserve const item/parameter identity and stable const-callability independently from runtime stability. Required evaluation uses target constants and checked arithmetic, not host execution or release wrapping. |
| T09 | Preserve unsafe-call requirements, pointer mutability/provenance, initialized validity, unions and manual destruction. A safe reference API cannot become an unsafe raw-pointer workaround. |
| T10 | Preserve the named foreign ABI, safety, variadic cursor/call contracts, callbacks and compatible-unwind requirements. C-compatible layout is not by itself a calling-ABI guarantee. |
| T11 | Copy is an explicit verified native opt-in. Sized/Unpin/thread/unwind properties retain structural and unsafe-implementation obligations. Do not equate reference counting with thread-safe payload access. |
| T12 | Preserve interface/associated type and const families, iterator item modes, projections and operator implementation relations. Default methods remain callable under their original bounds; unstable extension methods do not become stable because their trait is stable. |
| T13 | Preserve unsized tails, slices, text, alignment and metadata-bearing views/owners. `?Sized` becomes an unsized native bound, not an erased or heap-allocated type. |
| T14 | Retain target/feature conditions and instruction semantics. Architecture intrinsics map to native machine operations; they are not made universally callable or silently emulated with weaker performance guarantees. |
| T15 | Map declarative/procedural macros, derives, compiler attributes and documented keywords by the facility rules below. A reserved Rust keyword is not an implemented-language capability. |
| T16 | Translate each implementation relation with its implementing type, interface, substitutions and where constraints. Generated auto-property relations remain compiler-derived evidence; they do not create an ordinary user method or permit overlapping implementations. |

Literal by-value Copy inputs may be duplicated explicitly where the native take
rule would otherwise invalidate their source. That is the accepted source-mode
difference, not an extra payload clone or retain inserted by the implementation.

Type references in these rules resolve through the same canonical public type
table. Defaulted unstable allocator parameters do not turn an otherwise stable
default-allocator API into a promise of every nightly instantiation.

## 3. Unsized values, properties and explicit owners

Ordinary type parameters implicitly require Sized unless the unsized bound
removes it. Unsized values cannot be ordinary by-value local/parameter slots;
they are accessed through views or supporting owners. A product may have one
unsized tail field in last position. Its metadata and alignment derive from that
field. Slice metadata is element count; text metadata is byte count; erased
interface metadata supplies its dispatch/layout/drop contract.

Unsizing preserves a live allocation and appropriate pointer metadata. Safe
coercions include fixed arrays to slices and eligible concrete views/owners to
erased interfaces. Struct-tail coercions preserve every preceding field and
the owner's destruction/allocation contract. They cannot fabricate a larger
allocation or implicitly retain an owner.

Unpin is structurally derived unless an explicit negative declaration or field
prevents it. Unsafe manual implementations establish that moving the value
cannot invalidate the pinned contract. UnwindSafe/RefUnwindSafe-like properties
track logical recovery invariants; they do not make undefined behavior permitted
on a panic path. An explicit assertion wrapper can bypass the recovery heuristic,
not memory validity requirements.

Union fields have no automatic active-tag tracking or field destruction.
Fields must be Copy or use explicit manual-drop storage; reading a field is
unsafe unless the compiler can establish that exact initialized interpretation.

### Allocation-free cells and pin properties

The compiler-owned `core::cell::Cell<T>` provides `new`, Copy-only `get`,
`set`, `replace`, `swap`, `get_mut`, `into_inner` and `as_ptr`.
`RefCell<T>` provides `new`, `replace`, `swap`, `get_mut`, `into_inner`,
`as_ptr`, `borrow`, `borrow_mut`, `try_borrow` and `try_borrow_mut`.
These operations allocate nothing and require no OS or executor.
`get_mut` requires exclusive access to the cell; other non-consuming cell
operations accept a shared handle. Obtaining `as_ptr` is safe, but using it
retains the ordinary unsafe raw-pointer obligations.

`Ref<T>` and `RefMut<T>` are non-Copy, lifetime-bearing guards.
Both provide `get_ref`; `RefMut` additionally provides `get_mut`, requiring
exclusive access to the guard. `Ref.clone()` acquires another counted read
guard, without cloning the payload. A guard stored in a nominal type declares
its cell lifetime, for example `guard: core::cell::RefMut<T> from r`.
Returned payload views borrow their guard, not merely its backing cell.
The guards cannot be moved, forgotten or destroyed while such views remain
live. A surviving guard keeps its cell immovable and alive until cleanup,
including the interval between its last explicit use and destruction.

Read guards coexist; an exclusive guard conflicts with every other guard.
`borrow`/`borrow_mut`, conflicting `RefCell.replace`/`swap`, and read-counter
exhaustion panic. Swapping a RefCell with itself also panics.
Try-borrow operations return a native outcome: success contains the guard;
failure contains the zero-sized `BorrowError` or `BorrowMutError`.
Failure neither acquires nor releases a borrow. Dropping a guard releases its
count once, including partial paths and unwind; it never destroys the payload.
Forgetting it intentionally leaves the counter occupied, without extending the
authority of any surviving reference. The state is not thread synchronization.

Cell replacement returns the old owner or views and records the new value's
view dependencies. `set` installs the replacement before dropping the old
value, so an old destructor's panic or re-entry observes initialized new storage.
Interior mutation does not manufacture ordinary mutable authority from a
shared view: only a dynamically checked exclusive guard exposes RefCell payload
mutation. Cells remain invariant in their contained view regions.

Unsafe manual Unpin implementations may use interface, associated-item,
generic and region requirements supported by the interface solver. Failed or
recursive requirements do not prove Unpin. Function-local where assumptions
are not global type facts. Native pin operations retain proof requests through
lowering; instantiation and IR admission revalidate them rather than promoting
an unresolved conditional property into an unconditional type flag.

The default heap/shared constructors select the global allocator. Explicit
allocator-bearing owner/container types carry their allocator value and use
that same compatible allocator for deallocation. `into_raw`/reconstruction APIs
state whether allocator state is returned/transferred; losing it does not
authorize freeing through a different allocator. Allocation control is an
accepted native requirement even where the reference's similarly named generic
API is nightly-only.

## 4. Derives and compiler facilities

Required built-in derives: Copy, Clone, Debug, Default, PartialEq, Eq, PartialOrd,
Ord and Hash. Each uses declared fields/variants and generates only the bounds
needed by its documented operation; no borrow or retain is hidden in assignment.
Deriving Copy is an explicit named-type opt-in equivalent to copy type and still
checks the no-destructor/eligible-field rules.

Clone is an explicit duplication protocol, not a universal deep-copy theorem:
cloning a shared/weak owner retains that owner; cloning a String duplicates its
owned bytes. User implementations can have their documented behavior.

Required native attribute families include the previously selected layout,
alignment, export/link, cfg, target-feature, derive and diagnostics, plus:

| Native facility | Contract |
| --- | --- |
| @inline / @inline(always) / @inline(never) | Optimization hints; not a source-level execution guarantee |
| @cold | Cold-path hint, with no change to valid behavior |
| @deprecated(since, note) | Version/note metadata and use-site diagnostic |
| @must_use(message) | Diagnostic for discarded annotated values/results |
| @track_caller | Propagate the caller-location contract through supported direct/indirect calls; do not promise every adapter preserves its original source location |
| @link_section(name), @used | Explicit object-section/retention intent under target linker rules; incorrect placement is an unsafe obligation |
| @test, @ignore(reason), @should_panic(message) | Test-harness collection and expected-result metadata; normal library compilation does not execute tests |
| @global_allocator | One linked allocator provider satisfying the allocation interface |
| @panic_handler | One required panic entry point for profiles needing a user handler |
| @no_std, @no_main | Select library/startup layers explicitly; do not erase unresolved dependencies |
| @doc(text), documentation comments | Documentation input; no runtime effect |
| Extension declarations | Versioned token-stream registration for function-like, derive and item-transforming extensions |

Rust allow/warn/deny/forbid/expect controls map to native diagnostic controls.
Forbid is an inherited non-overridable deny; expect records an expected diagnostic
and warns when absent. Diagnostic identifiers are native, not Rust-code aliases.
Source export without mangling maps to export_name using the declared identifier.

These attributes have fixed attachment roles: codegen hints on functions;
deprecated/doc on documentable declarations; must_use on value-producing types
or functions; caller tracking on supported function definitions; storage/link
attributes on their corresponding emitted symbols; harness attributes on test
functions; allocator/panic providers on their corresponding definitions; startup/
library-layer attributes at package-root configuration.
Reject duplicates/conflicting singleton choices rather than relying on order.

Rust's named keyword documentation maps to the native grammar or an equivalent
operation. crate/mod/use/struct/trait/dyn/move/ref are covered by native package/
module/import/type/interface/any/take/view operations. `become` is reserved
reference vocabulary, not a stable tail-call capability to implement.
Language keyword/attribute documentation records are kept separate from stable
library APIs in the audit counts.

## 5. Layout and foreign completion

`@layout(transparent)` is supported for a struct or single-variant enum with at
most one field whose size is nonzero or whose alignment exceeds one; all other
fields are size-zero/alignment-one. Its layout and calling ABI match that field,
or unit when no such field exists. It cannot combine with C/integer layout,
packed or explicit alignment. This preserves scalar/newtype interoperability
without requiring an adapter with different calling cost.

Static native initialization is required constant evaluation. Mutable global
access requires explicit unsafe access or a safe synchronized wrapper.
Thread-local storage has its library-defined initialization/destruction and
affinity contract; it is not an implicitly synchronized global.

Foreign variadic calls apply the target C default integer/float promotions.
Non-C-compatible native owners/closures/outcomes cannot be passed directly.
Foreign definitions may receive a named VarArgs cursor tied to that call frame.
Cursor reads are unsafe and require the actual promoted next type; copy uses
the target va_copy operation, and ordinary owned cleanup performs va_end.
Cursors cannot outlive or cross threads away from their backing call frame.
The target's actual register/save-area/stack classification is normative, not a
generic sequence of native T objects.

The initial source interface spells a definition's cursor `args: ...` after at
least one fixed parameter. `args.arg::<T>()` is unsafe and requests the actual
promoted C argument type: request `i32` rather than `i8`/`bool`, and `f64`
rather than `f32`. C-compatible Copy aggregates retain their aggregate ABI;
their fields do not undergo scalar default promotions individually.
`args.copy()` initializes independent cursor state. Bind a cursor copy with
`var` to advance it. `args.end()` consumes that cursor; otherwise scope/unwind
cleanup ends it once. Moving a cursor transfers that obligation, not its backing
call frame. Safe forgetting may omit that cleanup but never extends the backing
frame's lifetime. The initial implementation rejects aggregate/closure storage,
raw-storage exposure and cross-function cursor transfers that it cannot safely
represent; these restrictions do not redefine the language's general transfer
or forgetting contracts.
The physical variadic entry captures its incoming ABI state before invoking
any logical body or cleanup callback. A hidden context is not a named source
parameter and does not change source argument counts or result-source contracts.

Static declarations use `static NAME: Type = constant;` or
`static mut NAME: Type = constant;`; foreign blocks admit the same declaration
without an initializer. Module visibility, imports and local shadowing apply
normally. Static storage has program lifetime, cannot be moved out, and is not
implicitly scope-dropped. Immutable storage containing native interior mutation
remains writable memory. Mutable-static access requires unsafe even when its
value is Copy. Constant initialization admits typed scalar literals, required
integer expressions, structural products/arrays/variants/unions, selected native
storage constructors and resolved function/static addresses. Address constants
retain relocation identity and slice length; ordinarily aligned views cannot
refer to unaligned packed fields. Required value-dependency cycles and reads of
mutable/unknown foreign storage are rejected. This does not execute user
functions, macros or hosted startup hooks.

`@export_name("symbol")` names a definition and `@link_name("symbol")` names an
import. Declarations of one external static symbol share one storage identity;
conflicting type/mutability contracts or duplicate definitions are errors.
`@link("library")` on an imported function/static or foreign block records an
explicit native library dependency for executable linking. Object-only emission
does not supply a linker or implicitly load those libraries. Selecting an
external name alone does not give a native-layout value a stable C calling ABI.

### Initial assembly and architecture mechanisms

The I06 implementation uses compiler-owned target facts for Linux x86-64
(SSE/SSE2 baseline) and Darwin ARM64 (NEON baseline); it never selects host-native
CPU tuning. This is an initial implementation inventory, not I13's complete
per-operation/per-profile closure or a target-qualification receipt.

`asm!` and `core::arch::asm!` implement the annex's ordered inputs, early/late
outputs, split/same-place inouts, typed full-width/generic integer constants,
resolved function/static symbols,
register classes/aliases/modifiers, C/system clobbers and options. Linux also
accepts the SysV64 clobber name. The x86 classes are `reg`, `reg_abcd`,
`reg_byte`, `xmm_reg`, `ymm_reg`, `zmm_reg`, `kreg`, and the explicit-register
clobber-only classes; ARM64 provides `reg`, `vreg`, `vreg_low16`, and explicit
predicate-register clobbers. Reserved registers, conflicting aliases,
incompatible types/features and invalid options diagnose before emission.
Memory and flags are conservative unless the unsafe declaration explicitly
narrows their effects. Ordinary assembly has no unwind permission.

Module-scope `global_asm!` accepts const/sym operands. `@naked` requires an
unsafe, non-generic, non-variadic physical C ABI definition containing exactly `naked_asm!`,
with no defaults, parameter patterns, ordinary body, hidden frame or implicit
return. Naked unwind metadata is not implemented and is diagnosed unsupported.
The assembly author implements the declared ABI, including returning and
preserving registers. The physical entry is never inlined into framed code.
Function symbol IDs survive specialization; both function and static symbols
use the backend's physical symbol/mangling and retain their referenced storage.

Native vector aliases retain element/lane shape, alignment and Copy semantics:
x86 `__m128{,d,i}`, `__m256{,d,i}`, `__m512{,d,i}` and ARM64
integer/unsigned/floating 64- and 128-bit vector aliases; x86 mask aliases retain
their fixed unsigned scalar widths. Vectors preserve their native identity
through generic and region substitution, not an empty structural product.
They do not introduce
owners or portable SIMD. The initial operation mechanism covers x86 128/256-bit
integer set/set1/add/sub, float set/set1/add/sub/mul, and integer
and/or/xor/unaligned load/store; ARM64 covers the corresponding stable
dup/add/sub/mul/bitwise/load/store/lane operations on their applicable element
types. The checked operation table in `types/target.cpp` is authoritative;
unimplemented operations are explicitly unsupported, not unchecked instructions.

`@target_feature("feature",...)` records recognized function requirements.
Calls, architecture operations and feature-sensitive assembly require the
baseline, a function requirement or a supported dominating dispatch predicate.
The initial predicates are direct positive `if
is_x86_feature_detected!("feature")` / `is_aarch64_feature_detected!("feature")`
conditions, including nested conditions. Requirements cannot be erased through
a thin callable coercion. LLVM receives the same feature metadata; optional
operation/assembly helpers pass storage rather than feature-dependent vector
ABIs so a guarded operation cannot enable instructions in an unguarded caller
prologue. Native vector physical entries require their ABI feature contract.
Calls across feature-dependent vector ABIs use storage bridges, including
indirect and generic calls. Foreign code must select the matching physical ABI;
the independent wide-vector C probe uses an isolated `-mavx` translation unit
rather than enabling optional instructions in all baseline fixtures.

Core x86 detection uses CPUID and gates XGETBV on XSAVE/OSXSAVE/AVX; AVX and
AVX-512 require their OS-enabled XCR0 state. Darwin ARM64 core detection supports
the guaranteed baseline only; optional hosted detection is diagnosed unsupported
rather than introducing sysctl, allocator or runtime dependencies.

## 6. Applicability, aliases and exclusions

Runtime stability and const-callability are independent fields. Source unstable
attributes override absent rendered badges, including inherited/default trait
methods. Implementation members inherit their interface member's instability,
even when their implementation omits its badge/attribute. A stable trait's
header does not incorporate its experimental children. Deprecated stable
contracts remain required.

Target applicability is the frozen source declaration plus its enclosing module/
macro cfg graph, and the displayed availability conditions. Source-constraints
retains the actual cfg/cfg_attr/target-feature forms, not an English approximation.
Do not conjoin every cfg in a source file: declarations and expansion context
determine which predicate applies. Actual target support is established later
by compiling/probing the native implementation under the same conditions.

The public library inventory does not include unrelated third-party types merely
because rustdoc lists a dependency's implementation of a standard trait.
Those records are explicitly retained as external_implementation, not silently
deleted or incorrectly promised as stable std APIs.

Experimental APIs are inventoried but not automatically committed. Explicitly
accepted native allocator control, negative thread properties and borrowed
scopes remain required independently of the reference's nightly register.

## 7. What this does not certify

The manifests and rules finish the design's operation inventory and translation
obligations. They do not prove a generated declaration typechecks, an unsafe
implementation is sound, every cfg branch has been executed, or runtime parity.
Those are mandatory implementation acceptance checks, not results produced by
copying a reference URL or assigning a rule ID.

## 8. Conditional supporting protocols

A stable callable can have a defaulted, sealed or compiler-controlled protocol
whose explicit reference-language declaration is experimental. Rejecting that
call would lose a stable capability; exposing every experimental implementation
would expand the agreed baseline. The native translation preserves the callable
and its exact eligible substitutions, not unrestricted implementation rights.
The machine-readable family register is
[supporting-protocols.json](baseline/supporting-protocols.json).

| Family | Native contract and boundary |
| --- | --- |
| Allocators | Preserve default Global construction and allocator identity through every owner; custom allocator operations are also an explicitly accepted native facility. Default parameters never imply a hidden payload clone or different deallocator. |
| Sequence/index helpers | Concat/Join and slice-pattern protocols retain eligible inputs and associated outputs. Checked disjoint indexing validates all ranges/overlap before lending exclusive results; the unsafe alternative retains its preconditions. |
| Text patterns | Provide sealed pattern/search capabilities for the frozen character, character-set, text and callable shapes. Forward, reverse and double-ended searching are distinct capabilities; positions remain valid UTF-8 boundaries. Do not promise arbitrary user searcher implementations. |
| Initialization clone | Clone-to-uninitialized storage tracks which components have become valid. Panic cleans only initialized components; it cannot expose an invalid safe reference. This does not stabilize unrelated experimental clone entry points. |
| Numeric helpers | Compiler-derived float/integer conversion, numeric-buffer and zero-valid primitive predicates preserve exact eligible widths/types. Unchecked conversions still require their range/NaN preconditions; zeroability is not inferred for references or enums from size alone. |
| Range helpers | Sealed stepping and one-sided-range capabilities retain the frozen eligible scalar/range families, end-point treatment, overflow and iteration contracts. Custom unrestricted Step implementations are not part of the automatic baseline. |
| Compiler properties | Tuple, function-pointer, pointee/metadata-size and discriminant predicates are compiler-known constraints, not unsafe user-forgeable layout assertions. Unsized/metadata rules follow section 3; distinct property predicates must not all collapse to Sized. |
| Async calls | Read/mutate/consume callable modes can construct concrete futures under their capture/region contracts. This does not expose experimental explicit call methods or associated future families as stable public APIs. |
| Short circuit | Sealed output/residual/branch capabilities support the frozen optional, outcome, control-flow and poll combinations. Preserve residual identity and each operation's early-stop/cleanup behavior. This is library generic dispatch, not permission for `try expression` to silently convert errors or add new effects. |
| Uninhabited values | Native `Never` expresses uninhabited results and divergence; no value may be fabricated to satisfy it. |
| Atomic aliases | Stable bool/integer/pointer aliases retain their operations and target conditions even if the reference implements them through experimental generic Atomic. Unsupported payload instantiations remain unavailable. |
| Variadic arguments | Compiler-known VarArgs eligibility retains the frozen promoted scalar/pointer shapes and target C ABI. It does not permit arbitrary owner/aggregate reads or relax the actual-next-argument unsafe precondition. |
| Raw OS errors | Native target error-code identity preserves the stable raw-code constructor/accessor round trip. A private/experimental source alias does not require user casts with information loss. |

For these sealed families, the exact eligible substitutions, associated
identities and operational preconditions are incorporated from the pinned
declaration/source contracts, translated recursively by T01-T16. No additional
public implementation rights arise by naming a helper. Native diagnostics
describe the failed capability, not a requirement to enable a Rust nightly flag.
Inherent implementation headers group operations; an experimental child cannot
become stable merely because its container type/header is stable.

The validator requires every remaining stable-to-experimental supporting
reference to name one of these families. It separately rejects a stable
implementation member whose interface member is experimental. Thus Error
provider/Request, experimental buffered-reader cursors and experimental Windows
process-attribute methods are not smuggled in as supporting-protocol exceptions.

## F1 formatted output (implemented, unverified)

- `f"text {expr} text"` is an f-string; `{{`/`}}` are literal braces. It is accepted only as an argument to a `format` parameter (type must be `core::fmt::Message`).
- `format` parameters are read-only, cannot be bound, returned, captured or passed to ordinary parameters; they may only be forwarded to another `format` parameter or used as a method receiver. Functions with a `format` parameter cannot be used as values.
- A non-f-string argument at a `format` position is lifted to a one-hole message (any `core::fmt::Hole` type: integers, bool, char, Text, String).
- `Message` is shape-independent (borrowed field array plus tail), so forwarders have one instantiation. Holes are raw-pointer based; region tracking of hole loans is a known gap.
- `Write::write`/`write_line` render a message; `io::print`/`io::eprint` take `format` parameters, no implicit newline. EPIPE on `print` exits quietly with 141; other failures panic.
- Known gaps: no float holes; build/tests for this lane were not run.
