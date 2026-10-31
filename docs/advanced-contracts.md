# Advanced ownership, async and metaprogramming contracts

Status: selected architecture elaboration, not an implemented safe API.
The [memory/concurrency contract](memory-and-concurrency.md) specifies borrowed
task execution epochs; the [specification annex](specification-annex.md) completes
macro, numeric, solver and attribute selections.

## 1. Pinning and address-sensitive objects

A pinned owner guarantees that its payload remains at its established address
until its destruction completes or its storage is deliberately leaked without
reuse. Moving the owner handle is distinct from moving its payload.

Safe operations cannot extract or swap an address-sensitive payload out of pinned
storage. A capability equivalent to Unpin may permit operations for types whose
correctness does not depend on that guarantee. Structural derivation and manual
unsafe implementations need explicit rules; not all types are pinned by default.

Initialization has two phases: reserve valid aligned storage, then establish
fields under a construction guard. User code must not obtain a reference to
uninitialized T. On failure, destroy established fields and release storage;
do not call the whole-value destructor before its invariants exist.

Pinned projections are legal only when the parent promises the field will remain
pinned through its destruction, including when a parent destructor runs. An
ordinary mutable projection cannot be exposed if it would permit replacement.
Projection APIs and generated destructors carry this contract together.

Shared ownership does not by itself imply pinning. Unique heap ownership does
not by itself prohibit moving the payload out. An address-sensitive C callback
must separately establish storage stability and callback cancellation/lifetime.

Rust comparison: these are pinning capabilities, not a claim that Mettle invented
stable addresses. Automatic safe self-referential construction is not added as
a new language feature by this document.
Performance: stable heap storage may allocate; inline pinned storage need not.
The state/owner representation determines costs, not the presence of the keyword.

## 2. Futures and executor protocol

An async call evaluates its arguments and constructs owned/borrowed captured
state under the signature contract. The body does not run until polled.
Borrowed input regions therefore constrain the future even before its first poll.

Poll receives exclusive pinned future access plus a wake context and returns
Pending or Ready(result). Pending retains initialized future state. A future that
may become ready must arrange notification or otherwise obey its executor's
documented polling contract. Spurious wakeups are permitted; duplicate concurrent
polls are not.

Ready completes the computation. Subsequent polling is outside the ordinary
future protocol, but a safe caller doing so cannot justify memory unsafety inside
a supposedly safe implementation; implementations may panic or provide specified
fused behavior. Future destruction cleans up initialized state exactly once.

Moving a not-yet-pinned future is permitted when its type allows it; moving pinned
address-sensitive state is not. Multiworker scheduling requires the appropriate
Transferable capture/state contract, not simply an atomic task handle.

Cancellation request is cooperative and distinct from destruction. Owned task
handles can expose request_cancel, join and completion inspection. A timeout that
only requests cancellation must not report completed cleanup.

The optional hosted `std.task` executor may park in an OS reactor when its ready
queue is empty. A readiness registration owns a clone of the current task waker;
dropping its future deregisters the registration, and event delivery after
deregistration is ignored. Descriptor readiness is advisory and may be spurious,
so I/O futures retry their nonblocking operation. Timer futures use the same
reactor and recompute their remaining duration after every wake. The core future
protocol remains OS-independent and does not select or install an executor.

## 3. Borrowed task scope enforcement

Choose lexical containment with poll-scoped execution epochs for borrowed tasks.
The compiler treats the scope as an owner of every borrowed child, not as a
forgettable library guard. Handles may be forgotten without releasing the
scope's registration of the child.

Every region captured by a child must outlive the scope region required by its
`Within` bound. If a method expresses that bound through a region parameter of
its receiver type, the obligation uses the receiver's nominal region argument;
a shorter call-site reborrow cannot reduce it.

Required state machine:

1. Open: parent storage is valid and new children may register.
2. Closing: registration is forbidden and cancellation is requested as needed.
3. Quiescing: wait until every registered child can no longer execute or resume
   accesses to borrowed parent storage.
4. Closed: registrations are removed and backing parent storage may be destroyed.

Scope normal exit, typed failure, panic and enclosing-future destruction all
must reach Closed before that storage is invalidated, or terminate the process.
The runtime cannot detach a borrowing child on an exceptional path.

Async scope exit may await cooperative completion. Every parent poll joins its
active child polls before returning or unwinding. Synchronous destruction thus
starts with no independently executing children and drops suspended child state.
It does not arbitrarily await. See memory-and-concurrency section 6 for forgotten
parent futures, wake metadata, recursive polling and worker panics.

This may block indefinitely for uncooperative work. It does not promise bounded
destructor latency, deadlock freedom, or completed asynchronous cleanup after
forced destruction. Local executors must not implement it by blocking the only
worker required to make cancellation progress.

Custom executors may support borrowed spawning only through an unsafe integration
contract that establishes registration, quiescence and storage validity.
Executors not implementing that contract still support owned tasks and directly
awaited borrowing. This is a contract requirement, not a blanket ban on custom
schedulers.

The mechanism is selected; independent soundness review and implementation
evidence remain required. No API is labeled safely implemented merely because
its intended execution-epoch protocol is documented.

Rust comparison: scoped threads and futures provide relevant capabilities, but
ordinary future dropping is not proof of safe borrowed task containment.
Performance: registration/join bookkeeping is a real cost. Compare against an
equivalent scoped implementation, not detached work with weaker lifetime rules.

## 4. Constant evaluation and host execution

Required type/layout constants execute in a deterministic target-aware evaluator.
Its values include typed scalars, aggregates, symbolic allocations and permitted
constant references. It must not materialize host pointers as target addresses.
Invalid required constant evaluation is a compile-time error.

Host macros/build programs may use files, network, clocks and native tools.
Their outputs become declared compilation inputs. An untracked input cannot
be omitted from cache invalidation merely because execution occurred at compile
time. Optional hermetic modes do not change the default capability commitment.

Cycle detection and resource limits distinguish recursive computation from
invalid semantic cycles. User-configurable budgets and cancellation protect the
compiler process without claiming every valid computation terminates.

## 5. Macro token grammar and hygiene

Working declarative form:

```text
macro name {
    (matcher) => { expansion };
}
```

Token trees contain balanced parentheses/brackets/braces or individual tokens.
Matchers support literal tokens, `$name:fragment`, and repetitions
`$(matcher) separator? *`, `+`, or `?`. Defined fragment kinds include token-tree,
identifier, literal, expression, type, pattern, statement, block, path and item.
The optional separator must not make following-token recognition ambiguous.

Expansions substitute bound metavariables and corresponding repetitions.
Repetition nesting/counts must match bindings; mismatched depths are errors.
Fragment boundaries invoke the native parser, not a text concatenation heuristic.
Metavariables cannot manufacture partially encoded UTF-8 tokens.

Generated names are hygienic by default. Definitions carry expansion and
definition-site identity; deliberately captured names require an explicit
capture operation. Record both invocation and definition spans for diagnostics.
Expansion happens before ordinary name/type checking of emitted items.

Declarative macros occupy a namespace distinct from values and types.
`pub macro` makes a definition available to a qualified invocation through its
module path, including a resolved package path. Private definitions are visible
only within their defining module and descendants; attempting a qualified call
from elsewhere is a name-phase diagnostic. Explicit macro imports, reexports
and restricted visibility are not part of the implemented subset.

Procedural extensions consume/produce versioned token streams and source spans.
Derive and attribute extensions receive the relevant item tokens; they cannot
depend on private compiler object layouts. Optional typed queries require an
explicit phase/dependency model and are not assumed available in every expansion.

Source execution remains visible local code, not automatically trusted or
sandboxed. A failing extension produces a diagnostic with provenance; it may
not silently omit generated declarations.

The specification annex defines fragment follow sets, deliberate capture,
attribute/derive ordering and extension API version negotiation.

## 6. Foreign declarations, assembly and attributes

Foreign varargs use a final `...` parameter in permitted external signatures.
Calls apply the target's C default promotions; arbitrary managed/native objects
cannot cross a variadic boundary without an explicitly compatible representation.
Foreign definitions and varargs-list manipulation require per-target contracts.

Assembly uses a delimited `asm!` invocation containing template strings, named
input/output/inout operands, explicit register classes, clobbers, and options.
Options affecting memory, stack, flags or unwinding are unsafe promises.
An optimizer must not assume pure/no-memory behavior when those options are absent.
Target-specific register legality and unwind support are validation requirements.

Attribute families and payloads:

| Attribute | Payload | Meaning |
| --- | --- | --- |
| layout | C or a specified integer enum representation | Layout contract, not automatic calling-ABI compatibility |
| align / packed | Positive power-of-two constant | Alignment / maximum field alignment with valid combinations |
| export_name / link_name | Constant string | Object symbol name |
| target_feature | Defined target feature names | Codegen requirement and caller safety obligation |
| cfg | Boolean target/feature expression | Conditional item inclusion |
| nonexhaustive | None | External consumers require fallback/construction restrictions |
| derive | Macro paths | Generate specified implementations |
| diagnostic | Defined lint code and level | Control diagnostic reporting, not semantic validity |

Unknown required attributes are errors. Target features cannot silently change
the public type layout of a supposedly compatible interface. The specification
annex defines packed/align combinations and assembly operand/option contracts.

## 7. Remaining design versus implementation evidence

These are advanced architectural contracts, not a claim of full formalization.
The linked refinements select mechanisms; compiler/runtime tests, ABI probes
and independent safety review remain additional evidence.

No verification-first language, native GPU model, durable workflow semantics, or
C++ migration-first scope has been accepted through these extensions.
