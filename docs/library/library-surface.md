# Native library surface and signature translation

Normative operation translation.

## 1. What specifies an operation

Each record in baseline/operations.jsonl.gz specifies a public exposure, associated
operation, or implementation relation. The catalog retains its reference
declaration, source span, receiver/implementation context, stability and target
conditions for scope and migration audit. Assigned operations have native
signatures and behavior in their owning specifications; unassigned operations
still require recursive translation of the retained declaration.

For operations assigned native authority in
[the mapping register](../process/baseline-mapping.md#7-native-operation-authority),
the owning native specification supplies semantics, complexity, panics, unsafe
preconditions and allocation/invalidation guarantees.
For unmigrated operations the linked versioned contract still supplies those
requirements; its removal is blocked until a complete native contract replaces it.
The native mapping supplies the names, types, ownership and calling conventions.
An in-scope unimplemented operation is an implementation failure, not an unspecified API.
An actual contradiction is a specification defect and reopens the gate.

Source-keyed canonical IDs share definition evidence and implementation context.
They are not type-layout hashes. Public reexports of one declaration must refer
to the same native identity, not independently defined lookalike types.
Transparent source aliases remain aliases; newtypes remain distinct.
Macro-generated declarations retain their generated name/signature and owner/
implementation context, not merely the macro definition's source line.

### Hosted panic recovery

`std.panic.catch_panic` consumes a one-shot closure and returns
`CatchResult.Returned(value)` or `CatchResult.Panicked(info)`. `PanicInfo`
owns the recovered payload; it exposes the panic code and a `Text` view of
the copied message, valid for the lifetime of that value. Runtime payload
storage is allocated for recovery and released when `PanicInfo` is dropped.
Source-level panic hooks receive the original borrowed message before
unwinding. `set_hook` replaces the custom hook; `take_hook` returns it as an
optional callback and restores the default reporter (`none` means the default
was active).
`reset_hook` restores that reporter without returning the previous callback.
A hook must not panic; doing so aborts. Recovery runs only after normal unwind
cleanup and replacement restoration, and does not roll back other closure side
effects. The hosted std API is unavailable in freestanding/abort execution;
an abort is not caught in-process.

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
| T06 | Interface-constrained opaque parameters become independently inferred generics; opaque returns have declaration identity. Dynamic interface values become explicitly erased interface values with the same associated bindings/regions; no implicit allocation is added. |
| T07 | Translate `for<'r>` to `for<region r>` with fresh rigid universes and leak checks. No monomorphization-time ownership privileges. |
| T08 | Preserve const item/parameter identity and stable const-callability independently from runtime stability. Required evaluation uses target constants and checked arithmetic, not host execution or release wrapping. |
| T09 | Preserve unsafe-call requirements, pointer mutability/provenance, initialized validity, unions and manual destruction. A safe reference API cannot become an unsafe raw-pointer workaround. |
| T10 | Preserve the named foreign ABI, safety, variadic cursor/call contracts, callbacks and compatible-unwind requirements. C-compatible layout is not by itself a calling-ABI guarantee. |
| T11 | Copy is an explicit verified native opt-in. Sized/Unpin/thread/unwind properties retain structural and unsafe-implementation obligations. Do not equate reference counting with thread-safe payload access. |
| T12 | Preserve interface/associated type and const families, iterator item modes, projections and operator implementation relations. Default methods remain callable under their original bounds; unstable extension methods do not become stable because their trait is stable. |
| T13 | Preserve unsized tails, slices, text, alignment and metadata-bearing views/owners. `?Sized` becomes an unsized native bound, not an erased or heap-allocated type. |
| T14 | Retain target/feature conditions and instruction semantics. Architecture intrinsics map to native machine operations; they are not made universally callable or silently emulated with weaker performance guarantees. |
| T15 | Map declarative/procedural macros, derives, compiler attributes and documented keywords by the facility rules below. A reserved reference keyword is not an implemented-language capability. |
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

The compiler-owned `core.cell.Cell<T>` provides `new`, Copy-only `get`,
`set`, `replace`, `swap`, `get_mut`, `into_inner` and `as_ptr`.
Source extensions add Copy-payload `update` and constant-callable `from_mut`,
`as_array_of_cells` and `as_slice_of_cells`; projections preserve the original
storage lifetime, extent and element layout without allocating.
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
its cell lifetime, for example `guard: core.cell.RefMut<T> from r`.
Both guard types provide consuming `map`, `filter_map` and `map_split`.
Callbacks return views tied to their input; exclusive split results must be
disjoint. Failed filtering returns the original guard. Successful projection
retains the original counter and payload metadata, and each split guard owns
one counted token; callback panic releases the original guard.
Returned payload views borrow their guard, not merely its backing cell.
The guards cannot be moved, forgotten or destroyed while such views remain
live. A surviving guard keeps its cell immovable and alive until cleanup,
including the interval between its last explicit use and destruction.

Read guards coexist; acquiring an exclusive borrow conflicts with any live guard.
`borrow`/`borrow_mut`, conflicting `RefCell.replace`/`swap`, and read-counter
exhaustion panic. Swapping a RefCell with itself also panics.
Try-borrow operations return a native outcome: success contains the guard;
failure contains the zero-sized `BorrowError` or `BorrowMutError`.
Failure neither acquires nor releases a borrow. Dropping a guard releases its
count once, including partial paths and unwind; it never destroys the payload.
Exclusive splits count each surviving exclusive guard separately; acquiring a
new shared or exclusive borrow remains forbidden until all are released.
Shared cloning and shared/exclusive splitting panic before counter overflow.
Forgetting it intentionally leaves the counter occupied, without extending the
authority of any surviving reference. The state is not thread synchronization.

Cell replacement returns the old owner or views and records the new value's
view dependencies. `set` installs the replacement before dropping the old
value, so an old destructor's panic or re-entry observes initialized new storage.
Interior mutation does not manufacture ordinary mutable authority from a
shared view: only a dynamically checked exclusive guard exposes RefCell payload
mutation. Cells remain invariant in their contained view regions.

Unsafe `RefCell.try_borrow_unguarded` returns a shared payload view or
`BorrowError` without acquiring a token. The view retains its cell lifetime;
the caller must prevent conflicting mutable access for its duration.

Source `OnceCell<T>` provides `new`, `get`, `get_mut`, `set`, `get_or_init`,
`take` and consuming `into_inner`, without allocation or OS services. It is not
Shareable; Transferable follows its payload. Shared access may initialize once;
removal needs exclusive
access. Failed `set` returns the rejected owner. Initialization callbacks run
only while empty; reentrant installation makes the outer initialization panic
without overwriting the installed payload. Clone delegates to the initialized
payload's Clone operation.

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

Native diagnostic controls provide allow/warn/deny/forbid/expect modes.
Forbid is an inherited non-overridable deny; expect records an expected diagnostic
and warns when absent. Diagnostic identifiers are native.
Source export without mangling maps to export_name using the declared identifier.

These attributes have fixed attachment roles: codegen hints on functions;
deprecated/doc on documentable declarations; must_use on value-producing types
or functions; caller tracking on supported function definitions; storage/link
attributes on their corresponding emitted symbols; harness attributes on test
functions; allocator/panic providers on their corresponding definitions; startup/
library-layer attributes at package-root configuration.
Reject duplicates/conflicting singleton choices rather than relying on order.

Package/module/import/type/interface/any/take/view operations are specified by
the native grammar. Reserved catalog vocabulary does not introduce an additional
language construct or a tail-call capability.
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
least one fixed parameter. `args.arg<T>()` is unsafe and requests the actual
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

Static declarations use `static NAME: Type = constant` or
`static mut NAME: Type = constant`; foreign blocks admit the same declaration
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

The [native machine contracts](native-machine-contracts.md) specify common
instruction access/feature rules and explicitly assigned helper operations.
The [authority register](../process/baseline-mapping.md#7-native-operation-authority)
distinguishes those assignments from remaining instruction-contract migration.

The initial mechanisms use compiler-owned Linux x86-64 SSE/SSE2 and Darwin
ARM64 NEON baselines, never host-native tuning. Full operation/profile
obligations remain subject to §6.

`asm!` and `core.arch.asm!` implement the annex's ordered inputs, early/late
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
header does not incorporate its experimental children. Owner amendment (2026-11-09): deprecated APIs, including records inheriting
deprecation from their context, are excluded from required scope. Keep their
reference provenance; do not delete or rewrite frozen declarations.

Target applicability is the frozen source declaration plus its enclosing module/
macro cfg graph, and the displayed availability conditions. Source-constraints
retains the actual cfg/cfg_attr/target-feature forms, not an English approximation.
Do not conjoin every cfg in a source file: declarations and expansion context
determine which predicate applies. Actual target support is established later
by compiling/probing the native implementation under the same conditions.

The public library inventory does not include unrelated third-party types merely
because the reference documentation lists a dependency's implementation of a
standard interface.
Those records are explicitly retained as external_implementation, not silently
deleted or incorrectly promised as stable std APIs.

Experimental APIs are inventoried but not automatically committed. Explicitly
accepted native allocator control, negative thread properties and borrowed
scopes remain required independently of the reference's nightly register.

### 6.1. V1 operation subset

By owner decision, V1 (I13/I14) requires only the following subset of the
stable inventory. Every other applicable non-deprecated stable record — including
architecture intrinsics beyond the A006 initial tables, OS
extension modules other than the selected Unix ones, and other rare types —
remains required, but it moves to I17. The capability rows, the
experience-track programs and the explicitly accepted items of section 6 remain
V1 obligations regardless of this subset.

Owner amendment (2026-11-09): all selected reference profiles remain required
for post-V1 applicability/qualification, without expanding the Linux-only V1
gate. The [reconciled worklist](../process/post-v1-worklist.md) separates independent
obligations, implementation members, shared declarations and exclusions.
Its counts are inventory scope, not implementation or target-qualification
receipts. Source-cfg applicability still requires review on each profile.

A record from the pinned inventory is in the V1 subset when it is stable, not
deprecated, applicable to the gated `linux-x64` profile and not under `arch` or a
non-Unix `os` module, and one of the following holds:

- It is the declaration of a selected type or trait, or a selected free
  function or macro.
- It is an inherent method, associated constant, variant or public field of a
  selected type.
- It is a required or provided member of a selected trait.
- It is an implementation of a selected trait for a selected type. Each
  (type, trait) pair is one obligation, covering every member and associated
  type of that implementation.

Integer widths, float widths and same-shape atomics are folded into one family
each, but the family must still be evidenced at every width. With this folding
the subset is about 2,900 operation families plus 1,760 trait/type pairs, out
of 106,125 canonical contracts.

Selected catalog type identities (native names follow section 9):

- **Scalars and core values:** `Option`, `Result`, the integer and float
  primitives, `bool`, `char`, `str`, slices, arrays, tuples, unit, `Range`,
  `RangeInclusive`, `ManuallyDrop`, `NonNull`, `PhantomData`, `Reverse`,
  `Wrapping`.
- **Collections and text:** `String`, `Vec`, `VecDeque`, `HashMap`,
  `HashSet`, `BTreeMap`, `BTreeSet`, `BinaryHeap`, and their `Entry`, `Iter`,
  `IterMut`, `IntoIter`, `Drain`, `Keys` and `Values` types.
- **Iterator adapters and text iterators:** `Map`, `Filter`, `Enumerate`, `Zip`,
  `Chain`, `Rev`, `Take`, `Skip`, `Peekable`, `StepBy`, `TakeWhile`,
  `SkipWhile`, `FlatMap`, `Flatten`, `Cloned`, `Copied`, `Windows`, `Chunks`,
  `Chars`, `CharIndices`, `Bytes`, `Split` and `SplitWhitespace`.
- **Owners and cells:** `Box`, `Rc`, `Arc`, `Weak`, `Cell`, `RefCell`, `Ref`,
  `RefMut`, `OnceCell`, `Pin`.
- **Synchronization:** `Mutex`, `RwLock` and their guards, `Condvar`, `Once`,
  `OnceLock`, `Barrier`, the bool/pointer/32-bit/64-bit/size atomics,
  `Ordering`, and the mpsc `Sender`, `SyncSender` and `Receiver`.
- **Hosted services:**
  - Time: `Duration`, `Instant`, `SystemTime`.
  - Formatting and errors: `Formatter`, `Arguments`, the io `Error` and
    `ErrorKind`.
  - Files and paths: `File`, `OpenOptions`, `Metadata`, `ReadDir`, `DirEntry`,
    `FileType`, `Permissions`, `Path`, `PathBuf`, `OsStr`, `OsString`, `CStr`,
    `CString`.
  - Standard streams and buffering: `Stdin`, `Stdout`, `Stderr`, `BufReader`,
    `BufWriter`, `Lines`, `Cursor`.
  - Processes: `Command`, `Child`, `Output`, `ExitStatus`, `Stdio`.
  - Networking: `TcpListener`, `TcpStream`, `UdpSocket`, `SocketAddr`,
    `IpAddr`, `Ipv4Addr`, `Ipv6Addr`.
  - Threads: `JoinHandle`, `Thread`, `Scope`, `ScopedJoinHandle`.
  - Async: `Poll`, `Context`, `Waker`.

Selected traits:

- **Iteration:** `Iterator`, `IntoIterator`, `DoubleEndedIterator`,
  `ExactSizeIterator`, `FromIterator`, `Extend`.
- **Value traits:** `Clone`, `Copy`, `Default`, `Debug`, `Display`, `Hash`,
  `Hasher`, `BuildHasher`, `PartialEq`, `Eq`, `PartialOrd`, `Ord`.
- **I/O:** the fmt and io `Write`, `Read`, `BufRead`, `Seek`.
- **Conversion:** `From`, `Into`, `TryFrom`, `TryInto`, `AsRef`, `AsMut`,
  `Borrow`, `ToOwned`, `ToString`, `FromStr`.
- **Operators:** the arithmetic, bitwise, negation and compound-assignment
  operators, `Index`, `IndexMut`, `Deref`, `DerefMut`.
- **Language and runtime:** `Drop`, `Fn`, `FnMut`, `FnOnce`, `Future`, `Send`,
  `Sync`, `Sized`, `Error`, `Any`.

Selected free functions and macros:

- **Threads:** the `thread` functions `spawn`, `scope`, `sleep`, `current`,
  `yield_now`, `available_parallelism`.
- **Files:** the `fs` functions `read`, `read_to_string`, `write`,
  `create_dir`, `create_dir_all`, `remove_file`, `remove_dir`, `remove_dir_all`,
  `rename`, `copy`, `metadata`, `read_dir`, `canonicalize`.
- **Environment:** the `env` functions `args`, `var`, `vars`, `set_var`,
  `remove_var`, `current_dir`, `set_current_dir`, `temp_dir`.
- **Process and standard streams:** `process::exit`, `process::abort`,
  `process::id`, `io::stdin`, `io::stdout`, `io::stderr`, `io::copy`.
- **Memory and pointers:** the `mem` functions `swap`, `replace`, `take`,
  `drop`, `forget`, `size_of`, `align_of`, `size_of_val`; the `ptr` functions
  `null`, `null_mut`, `eq`, `read`, `write`, `copy`, `copy_nonoverlapping`,
  `drop_in_place`.
- **Comparison and iteration:** `cmp::min`, `cmp::max`, and the `iter`
  functions `once`, `repeat`, `empty`, `from_fn`, `successors`, `zip`.
- **Channels and construction:** `mpsc::channel`, `mpsc::sync_channel`,
  `hint::black_box`, `char::from_u32`, `char::from_digit`, `str::from_utf8`,
  `array::from_fn`.
- **Macros:** the print/format/write macros, the assert macros, `panic`,
  `vec`, `unreachable`, `todo`, `unimplemented`, `matches`, `dbg`.

## 7. What this does not certify

Qualification requires checked declarations, unsafe invariants, applicable cfg
execution and runtime comparison; manifest records alone establish none of these.

## 8. Conditional supporting protocols

A stable callable can have a defaulted, sealed or compiler-controlled protocol
whose explicit reference-language declaration is experimental. Rejecting that
call would lose a stable capability; exposing every experimental implementation
would expand the agreed baseline. The native translation preserves the callable
and its exact eligible substitutions, not unrestricted implementation rights.
The machine-readable family register is
[supporting-protocols.json](../baseline/supporting-protocols.json).

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
describe the failed capability, not a requirement to enable an external
experimental feature.
Inherent implementation headers group operations; an experimental child cannot
become stable merely because its container type/header is stable.

The validator requires every remaining stable-to-experimental supporting
reference to name one of these families. It separately rejects a stable
implementation member whose interface member is experimental. Thus Error
provider/Request, experimental buffered-reader cursors and experimental Windows
process-attribute methods are not smuggled in as supporting-protocol exceptions.

## 9. Vocabulary and the `experience-1` prelude

Decision D21. Canonical reexports or aliases preserve the
baseline identities that baseline-mapping.md requires; there is one collection
implementation, not a branded and a compatibility copy. Compiler-recognized
protocols follow resolved declaration identities, not a second set of
spelling-based special cases.

| Catalog identity or form | Native name or form |
| --- | --- |
| `Vec`, `HashMap`, `HashSet` | `List`, `Map`, `Set` from `alloc.collections` |
| General `Cow<region r,B>` | `BorrowedOrOwned<region r,B>` in `alloc.borrow`; borrowed payload and associated owned type remain distinct |
| `Cow<'a, [T]>` for `Vec<T>: From` | `BorrowedOrOwned<region r, [T]>` in `alloc.borrow`; conversion clones borrowed items and moves owned Lists |
| `cmp::Reverse` | `Descending` in `core.cmp` |
| `sync::Condvar` | `Condition` in `std.sync.condition` |
| `NonNull<T>` | `core.ptr.NonNull<T>`; compiler-owned raw-pointer operations remain in `core.ptr` |
| `BTreeMap`, `BTreeSet` | `SortedMap`, `SortedSet` |
| `IntoIterator`, `IterableMut` | `OwnedIterable`, `MutableIterable` |
| `DoubleEndedIterator`, `FromIterator`, `Extend` | `BidirectionalIterator`, `FromItems`, `ExtendItems` |
| Interface implementation blocks | `extend<T> X implements I` |
| Out-of-line inherent implementation blocks | `extend<T> X`; ordinary methods prefer the type body |
| Hosted `Read`, `Write`, `BufReader`, `BufWriter` | `Reader`, `Writer`, `BufferedReader`, `BufferedWriter` |
| Named optional/result wrappers | None introduced: use `T?` and `(Outcome<T, E>)` |

The hosted I/O names refer to `std.io`; `core.fmt.Write` retains its name.
Under D31, slices use `BorrowedOrOwned<region r,[T]>` directly.
`core.borrow.OwnedType` supplies the associated owner independently of copying;
`ToOwned` supplies copying into it. Borrowed/read `BorrowedOrOwned` usage does not require
Clone merely to name the owned branch.
Under D30, the alloc Map default is deterministic; randomized hashing requires
an explicit builder and must not introduce a hidden OS dependency into alloc.

Iterator adapter types use one consistent past-participle scheme, distinct from
the collection type `Map`:

| Catalog adapter | Native type | Catalog adapter | Native type |
| --- | --- | --- | --- |
| `Map` | `Mapped` | `TakeWhile` | `TakenWhile` |
| `Filter` | `Filtered` | `SkipWhile` | `SkippedWhile` |
| `FilterMap` | `FilterMapped` | `StepBy` | `Stepped` |
| `Enumerate` | `Enumerated` | `Inspect` | `Inspected` |
| `Zip` | `Zipped` | `Fuse` | `Fused` |
| `Chain` | `Chained` | `Rev` | `Reversed` |
| `TakeN` | `Limited` | `Skip` | `Skipped` |

`Peekable` and adapter *method* names (`map`, `filter`, ...) are unchanged.
`Map` names the collection; iterator adapters use the names in the table. The
iterator module does not export a `Map` alias for an adapter.

Retain `Iterator`, `Iterable`, `Copy`, `Clone`, `Eq`, `Ord`, `Hash`, `Text`
and `String`.

**Library prelude `experience-1`, exact contents:**

- Core: `Text`, `Iterator`, `BidirectionalIterator`, `OwnedIterable`, `Iterable`,
  `MutableIterable`, `PartialEq`, `Eq`, `PartialOrd`, `Ord`, `Ordering`, `panic`,
  `assert`.
- With allocation enabled: `String`, `List`, `Map`, `Set`.
- Hosted additions: none; import I/O, threads, networking and executors.

The list excludes compiler-predeclared scalar/capability names, which keep their
existing specifications. Prelude entries have the lowest lookup priority. The
package language revision selects the prelude version; changing this set needs a
new version and collision tests.

`Text` is UTF-8 content viewed through `read Text`; `String` owns growable UTF-8
storage and its allocator. Literals have type `read Text from static` and
allocate nothing. `String(text)` visibly requests ownership and copying;
`string.as_text()` borrows without copying. Existing checked read coercions may
avoid redundant adapters but never manufacture an owned String.

## 10. Formatting and output

Decisions D23-D24. Core owns sink formatting; **std owns Writer's
`write`/`write_line` methods and the byte-I/O adapter**;
`write_all(bytes)` and `flush()` stay methods too.

### 10.1. `format` parameters and `core.fmt.Message`

```text
fn log(message: format core.fmt.Message): Unit throws io.Error {
    var out = io.stderr()
    try out.write_line(message)
}
```

The parameter kind is part of the checked callable contract; any function or
method may declare one and no function name is compiler-special. A recipe may be
a direct `f"..."`, a direct Text/String lifted to a single-text recipe, or the
forwarded enclosing `format` parameter at such an argument. It cannot otherwise
be bound, returned, stored, put in an aggregate or passed to an ordinary generic
parameter. Forwarding keeps the outer call's lifetime bound, so user loggers
work without first-class recipes; the no-escape contract survives forwarding and
callable conversion, and asynchronous retention needs an explicit owned String.

`Message` is an opaque fixed-size borrowed descriptor, not generic over the
interpolation's shape. Conceptually it views literal pieces and a caller-stack
array of fields, each carrying a value-context pointer, a checked renderer
function pointer and formatting options; unsized values use a stack-resident
view descriptor with their metadata, never a truncated fat pointer. The layout
is compiler-owned, not a public or foreign ABI promise. This is explicit borrowed
erasure at the format boundary: indirect
renderer calls, no heap allocation, no Heap, and no implicit retention or copy of
payloads. A fixed borrowed sink adapter keeps the renderer ABI independent of
the concrete writer. Logger and relay functions therefore have one body across
message shapes; renderer thunks may be shared per value-type/format operation;
ordinary unrelated generics may still specialize. Normal backend inlining stays
possible: the guarantee is no recipe-shape instantiation of the logger, not
identical machine code. Measure indirect calls, renderer/code-size growth and
check cost under performance.md.

Receiver, ordinary arguments and holes evaluate once in source order. Owned hole
temporaries survive through the enclosing call; borrowed holes are loans only
through that call and its cleanup; on failure each established temporary is
destroyed exactly once. The description itself allocates nothing, while
`alloc.fmt.string` explicitly allocates an owned String and user formatters keep
their own documented costs.

Each formatted Writer method retains the first full `io.Error` from the sink and
returns it unchanged, including raw OS information. A formatter failure with no
sink error maps explicitly to `io.ErrorKind.invalid_data`. Partial output is
allowed; output is not transactional.

### 10.2. Convenience output and broken pipes

`io.print("hello\n")` and `io.eprint(f"count={count}\n")` declare `format`
parameters, add no implicit newline, and panic on ordinary failure instead of
ignoring it. **Stdout broken pipe is the exception** (`broken_pipe`, EPIPE on
POSIX): the runtime does not ignore SIGPIPE (only sockets use `SO_NOSIGPIPE`/
`MSG_NOSIGNAL`), so by default a write to a closed stdout pipe terminates the
process by SIGPIPE. Where the inherited disposition is *ignore*, `print` observes
EPIPE and terminates quietly with exit status 141, without a panic message or
hook. The shell-visible status is equivalent, but the raw child status still
distinguishes signal termination from `exit(141)`. No application-wide signal
disposition is installed for this convenience policy.

The EPIPE path uses `std.process.exit` immediate-termination cleanup: live
Mettle destructors do not run, other writers are not flushed, and it is not
graceful unwinding. This explicit exit applies only to stdout convenience output.
Fallible Writer methods never request it and preserve error identity when the
write returns an error. They do not suppress kernel-generated SIGPIPE: its default
disposition can terminate a closed-pipe write before any error is returned.
Programs needing controlled cleanup must first arrange for SIGPIPE to permit
error return, for example by inheriting an ignored disposition, then handle
broken pipe through `try out.write_line(...)`. `eprint` and non-pipe convenience
errors still panic when reported by the sink.

### 10.3. Implementation status

Formatting is profile-scoped and incomplete; current receipts and remaining F1
work belong to implementation-plan. The current hole surface accepts Text or
sized Display implementors. Current float formatting uses shortest round-trip
digits, plain positional notation, `NaN`/`inf` and `-0`, without libc;
`Spec.precision` does not yet apply to floats. Format specifiers, Debug holes,
hole-loan region tracking and cost measurements remain open.

## 11. Lending lines and byte iteration

Std buffered readers provide:

```text
mut fn read_line_into(mut buf: String): (read Text from buf)? throws io.Error
mut fn read_bytes_line_into(mut buf: List<u8>): (read [u8] from buf)? throws io.Error
```

Both clear `buf` before reading, retain LF/CRLF bytes, return `none` only when no
bytes remain, and return a final unterminated line. The returned view depends on
`buf`, not on the reader; retaining it prevents the next mutation or refill of
`buf`. Memory is proportional to the longest line plus the reader's buffer.
These are lending operations, not `Iterator` implementations.

The text form validates UTF-8 and reports `invalid_data`, leaving the String
empty and valid on validation failure. The byte form accepts arbitrary bytes. An
I/O failure may consume input and returns no view; any partial buffer contents
are documented and never presented as an invalid String.

`[u8].bytes()` is a Copy-valued iterator like `Text.bytes()`: it yields `u8`,
holds a read loan on the slice and allocates nothing. It removes repeated
dereferences without changing the `Iterable` item contract or choosing
generic-loop ownership from a later Copy instantiation.

## 12. Borrowed keys and path input

`core.borrow.KeyView<Q: unsized>` applies to hash/ordered maps and sets.
`std.path.PathInput` covers fs, env, process and Writer path input; Windows
delivery remains a target gate.

**KeyView.** `KeyView<Q>` exposes `read Q from self` without allocation or
retention. `Map<K,V>.get<Q>(key: read Q)` requires `K: KeyView<Q>` and
`Q: Hash + PartialEq`, so an unsized query such as Text is allowed, and returns a view
of the map's value, not of the query. Equal stored and query keys must hash
identically under the selected hasher with equality consistent across both
representations. Identity views and `String -> Text` are provided (String's hash
already delegates to Text). Ambiguous view relations are rejected. Insertion
still acquires an owned key explicitly, so `map.get("a")` allocates no temporary
String.

**PathInput.** `Path` remains an unsized borrowed OS-path view. `path.PathInput`
has `fn as_path(): read Path from self` and is implemented for Path/PathBuf and
OsStr/OsString, preserving the platform-native representation (bytes on POSIX,
the selected native Windows encoding on Windows) without allocation or lossy
conversion. The borrow never outlives its source, and NUL validation stays in
the OS operations. On POSIX, `Path` has a single unsized byte-slice field whose
address and length metadata match the borrowed bytes. `PathBuf` owns an
`OsString`; its mutable views remain tied to that owner, and conversion between
the owners transfers the allocation. Hosted path-taking convenience APIs accept
independently generic `PathInput` read parameters whose desugared bounds permit unsized
implementors as well as owned OS strings (language-grammar section 3); the
underlying read-Path entry points remain. `env.args()` keeps returning owned OS
strings, so `count(args[1], args[2])` needs no adapter. This is a library
protocol, not implicit allocation, interface erasure or a new constructor rule.

`out.write_path(input)` is the fallible std Writer operation for path display.
POSIX output preserves native path bytes. On Windows, redirected byte output uses
UTF-8 for valid Unicode and visible `\u{XXXX}` escapes for unpaired UTF-16 code
units; console output uses the wide-character console API with the same escapes
where required. This is display, not reversible serialization; native paths
remain available separately, and no invalid Text or lossy String conversion is
constructed.

Windows storage, sink dispatch and output expectations are target prerequisites,
not established support (implementation-plan §8.7, R2).

## 13. Hosted task scopes and networking

`std.task.scope` is the synchronous, local borrowing scope: it drives ready
children and destroys suspended children before returning. For async work,
`std.task.async_scope(read anchor)` returns a `Future` that owns each child
registered through its mutable `spawn` method. A child's captured regions and
output must satisfy `Within` for the anchor's region. The returned
`AsyncJoinHandle` only observes the result; dropping or forgetting it does not
unregister the child. `is_finished` reports completion or cancellation, and
`take_result` retrieves an available output without waiting.

Each parent poll serially polls every registered child once. A child wake only
notifies the parent task; it never polls the child directly. The scope becomes
ready when all children complete. Dropping the parent future synchronously
destroys every suspended child, while a child panic propagates after the other
registrations have been closed and destroyed. Wake metadata may outlive the
parent but cannot access its storage. Registration allocates pinned child
storage and polling is proportional to the number of registered children; this
is not a zero-cost or parallel-execution guarantee.

The POSIX hosted network surface's optional `std.task` executor adds `readable`,
`writable`, and `sleep`; its per-executor reactor parks while no task is ready.
These readiness futures require a `std.task` waker. `std.net` adds
`AsyncTcpListener`/`AsyncTcpStream`, `async_tcp_listen`,
`async_tcp_connect`/`AsyncTcpStream.connect`, and async `accept`, `read_some`,
`write_some`, and `write_all`. These wrappers use nonblocking sockets and retry
after advisory readiness. Dropping a pending I/O or timer future deregisters
its reactor token. The macOS reactor uses kqueue; profile qualification is
recorded separately.

The selected `std.net` names are `Ipv6Addr`, `IpAddr`, and
`SocketAddr`; constructors are `ipv6`, `ipv6_localhost`, `ipv6_unspecified`,
`Ipv6Addr.localhost`, `Ipv6Addr.unspecified`, `socket_addr_v6`, and
`socket_addr_ip`. Text entry points are `Ipv6Addr.parse`, `SocketAddr.parse`,
`parse_ipv6`, `parse_ip_addr`, and `parse_socket_addr`; malformed input throws
`std.io.ErrorKind.InvalidInput`.

`Ipv6Addr` stores the 16 network-order address bytes, is constructed from eight
16-bit segments, and formats as lowercase RFC 5952 text (compressing the
longest run of at least two zero segments, choosing the first run on ties).
`SocketAddr` stores an `IpAddr`, port, flowinfo and scope id. IPv6 socket text
uses brackets (`[::1]:8080`) and an optional decimal `%scope_id`; flowinfo is
preserved by socket operations but is not part of this text form. `resolve`
accepts a `Text` host and port and returns all IPv4/IPv6 stream addresses from
POSIX `getaddrinfo` in resolver order. TCP/UDP address operations preserve the
family and IPv6 flow/scope fields. Connect timeout expiry is reported as an
I/O timeout; read/write socket timeouts retain the existing `set_*_timeout`
names and behavior. No Windows socket profile is claimed.
