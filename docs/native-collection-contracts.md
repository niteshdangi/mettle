# Allocation, owner and collection operation contracts

Status: authored native specification for the explicit member groups below,
not evidence that their implementations or target executions are complete.
[Core operation contracts](native-core-library-contracts.md) define shared
protocols, views, callbacks and algorithms. The
[ownership/allocation policy](library-and-abi.md#2-ownership-and-allocation-operations)
and [memory model](memory-and-concurrency.md) apply.
Source-family names in parentheses identify the public identities being
specified; they do not incorporate another language's behavioral authority.

## 1. Common collection rules

`List` (Vec), `Map` (HashMap), `Set` (HashSet), `SortedMap` (BTreeMap) and
`SortedSet` (BTreeSet) are the native collection identities. VecDeque,
LinkedList, BinaryHeap, String, Box, Rc, Arc and Weak retain their specified
module/type identities. Reexports and aliases do not create a second owner.
Allocator type A defaults to Global; an `_in` constructor consumes an explicit
A and every surviving allocation remains associated with a compatible A.
Allocator-bearing APIs are an explicitly selected native facility.

Read-only queries, borrowed iteration, get and key/value projections allocate
nothing and never clone or retain payloads. Mutations need exclusive access,
except documented shared-owner/cell operations. Consuming iteration moves
items out. Methods taking an element/key/value consume that argument even if
it is Copy. A live element view or borrowed iterator prevents conflicting
mutation, reallocation and destruction of its owner. Raw pointers have no
such enforcement and must be revalidated after operations that can relocate
or remove their storage.

Capacity is the number of elements that can be stored without another
allocation for that collection's ordinary insertion path, not its byte size.
No growth factor, address, bucket/node layout, spare-byte value or hash
iteration order is promised. `len/is_empty/capacity/allocator` are O(1)
read-only queries where that type exposes capacity/allocator.
Zero-sized elements may have logical capacity usize::MAX without backing
element bytes; logical lengths and destructor counts still matter.
No owner is Copy. Clone follows section 11, not ordinary assignment.

Ordinary allocation exhaustion aborts through the selected allocation handler.
Capacity arithmetic overflow is a checked capacity panic, not a wrapped small
allocation. `try_reserve/try_reserve_exact` return a typed reserve failure for
capacity overflow or allocation failure and preserve the original initialized
contents; they do not convert callback panics into failures.
`try_push(take T)` returns a PushError owning the uninserted T on capacity/
allocation failure. Other `try_` constructors consume and clean their
arguments unless their explicit result returns those owners.
Allocation policy does not excuse a safe operation from valid partial cleanup.

Unless a stronger rule is given, callback panic leaves initialized owned
contents, possibly reordered or partially modified, with each resource owned
exactly once. A destructor panic can interrupt logical completion, but
unwind follows the language's cleanup rules; APIs do not promise rollback.
Forgetting a drain/splice/guard may leak elements or storage and is not
equivalent to dropping it. It cannot authorize later safe reads of invalid
storage.

## 2. Layout and allocator operations

Layout consists of byte size and nonzero power-of-two alignment.
Rounding size upward to alignment must be representable and <= isize::MAX
on the target. `layout_from_size_align` checks these conditions and returns
LayoutError on failure; unsafe `layout_unchecked` requires them.
`size/align` return the recorded values. `layout_of<T>` and `layout_of_val`
use the complete target layout, including an unsized tail's valid metadata.
Unsafe raw dynamic-layout queries require valid metadata for that layout.

`layout_array<T>(n)` checks multiplication and final layout bounds.
`align_to(a)` raises alignment to max(old alignment,a), checking layout
validity without changing size. `pad_to_align` rounds size to alignment.
`extend_layout(prefix,suffix)` / Layout.extend places suffix at the least
offset >= prefix size aligned to suffix alignment; the returned alignment
is their maximum, size is offset+suffix size, and the offset is returned
separately. Final trailing padding requires pad_to_align; it is not part
of extend. Overflow returns LayoutError.
`repeat(n)` returns a layout and stride: stride is the original size rounded
up to its alignment; for n > 0 total size is (n-1)*stride+original size,
with no final trailing padding; for n == 0 size is zero.
`repeat_packed(n)` instead has size n*original size and the original alignment.
`extend_packed(next)` has size self.size+next.size and self's alignment,
ignoring next's alignment. These are safe layout computations returning
LayoutError on overflow/invalid final layout; using their potentially
misaligned interior objects needs raw/unaligned operations or separate proof,
not ordinary aligned references.
`dangling_ptr` produces a non-null pointer aligned for this layout but no
storage ownership; its address can coincide with a real object, so it is
not a unique uninitialized-state sentinel.

The accepted native `Allocator` interface has mutable allocator access:

It is declared `pub unsafe interface Allocator` and implemented with
`unsafe extend`. Its safe `allocate` call relies on the provider to establish
the returned extent's liveness, exclusivity, size and alignment.
`deallocate`, `grow` and `shrink` are `mut unsafe fn` methods.
Allocator clones used for the same allocation must remain compatible.
Before `grow`/`shrink` returns a replacement, typed failure or unwind must
preserve the original live allocation and its initialized contents.
This does not forbid `deallocate` from releasing storage and then panicking.
Unlike `GlobalAlloc`, generic `Allocator` has no no-unwind requirement.

| Member | Contract |
| --- | --- |
| `allocate(layout)` | Return exclusive raw storage satisfying size/alignment or AllocError; initial bytes need not be initialized |
| `deallocate(p,layout)` | Return the live allocation to a compatible allocator with its original layout |
| `grow(p,old,new_size)` | Require new_size >= old.size; on success replace allocation, preserve all old bytes/initialization and original alignment |
| `shrink(p,old,new_size)` | Require new_size <= old.size; preserve the first new_size bytes/initialization |
| zeroed allocation/growth variants, when exposed | Additionally initialize newly allocated byte extent to zero; not proof of typed T validity |

Raw deallocation/reallocation calls require caller-established allocation
identity, exact compatible layout and exclusive authority to invalidate the
old storage. A successful resize transfers allocation ownership to the new
pointer even if its address is unchanged; the old pointer is no longer an
independently usable allocation. Failure preserves the original allocation.
Zero-size native allocate returns a non-null aligned placeholder; zero-size
deallocation does not call the external heap. Growing from zero allocates;
shrinking to zero releases the old allocation and returns a placeholder.
The placeholder cannot be used to access a nonzero-sized T.
Allocator effects and cost are allocator-specific; no constant-time,
nonblocking or bounded-memory allocator guarantee is implied.

`Global` is the stateless global-provider handle. Raw global functions
`alloc/alloc_zeroed/dealloc/realloc` (also reexported through core.alloc)
follow their unsafe allocation-provider contract: allocation size is nonzero,
alignment/layout valid, allocation failure returns null, and zeroed allocation
zeros all requested bytes. Dealloc requires the exact live allocation/layout.
Realloc additionally requires nonzero valid new_size and the old layout,
preserves min(old,new) bytes, and on null leaves the old allocation owned.
It may change address. It must not be used to resize a stack/foreign
allocation merely because the pointer is aligned.
`GlobalAlloc` implementations satisfy those same operations, may not unwind
across the allocation boundary, and must not rely on every syntactic
allocation actually surviving optimization as an observable event.
`handle_alloc_error(layout): Never` terminates under the selected failure
policy; it does not return or unwind through allocator callbacks.

## 3. Unique allocation owners

`Box<T: unsized,A>` owns exactly one initialized T and the allocation needed
for it. Drop destroys T once and then releases its allocation with the
compatible allocator/layout; a cleanup guard protects deallocation during
payload unwind. A zero-sized payload still has a non-null aligned pointer
and its destructor still runs.

`new(take T)` / `new_in(take T,take A)` allocate and transfer T into fixed
storage without cloning it. Fallible `try_new[_in]` return AllocError and
clean the consumed value/allocator on failure; they do not promise the input
value in the error. `get/as_ref/Deref` lend T; `get_mut/as_mut/DerefMut`
require exclusive Box access. `allocator` lends A. `into_inner` transfers T
and frees only its former storage without destroying the returned T.

`new_uninit[_in]` owns MaybeUninit<T>; zeroed variants initialize bytes to
zero without asserting T validity. Slice variants take a length and own
that many MaybeUninit elements. Unsafe `assume_init` requires every selected
element/payload to be valid and initialized and transfers the same allocation
to Box<T>/Box<[T]>. `write(take T)` on Box<MaybeUninit<T>> initializes once
and converts ownership without a second allocation. Partial initialization
remains the caller's responsibility until an initialized owner is formed.

`into_raw` consumes the Box, suppressing drop and transferring one destruction/
deallocation responsibility to the caller. For explicit allocators,
`into_raw_with_allocator` returns both pointer and A; the caller must retain
the allocation's actual compatible allocator even when using a pointer-only
form. Unsafe `from_raw[_in]` requires that unique responsibility, correct
pointer metadata, alignment, live allocation layout, initialized valid T,
and matching allocator. Reconstruct once; never reconstruct from a borrowed
as_ptr, interior pointer, stack pointer or already reconstructed owner.
NonNull raw forms have identical ownership rules plus non-null representation.
Obtaining a raw address does not itself transfer ownership.

`leak(take Box)` transfers an exclusive T view while deliberately suppressing
deallocation; its region may not outlive any region embedded in T or allocator
obligations. It does not erase borrowed payload lifetimes.
`pin(take T)` allocates pinned payload storage; `into_pin(take Box)` pins
existing storage without moving it or allocating again.
Unsizing/coercion preserves allocation identity, metadata and destruction.
Checked erased-owner `downcast<T: Any>` returns Box<T> on exact type identity,
otherwise returns the original erased Box unchanged.

Borrowed Box<[T]>/Box<[T; N]> iteration lends slice elements.
Consuming iteration moves each initialized T exactly once and owns the
original allocation/allocator until completion or iterator destruction.
It is exact-size, bidirectional and fused; unyielded elements are dropped
before deallocation. Empty/zero-length iteration never dereferences an
element pointer. Box conversions from List/String may shrink/reallocate
to the slice/text allocation; converting the resulting boxed slice back to
List preserves elements without cloning. Box delegation of Iterator,
Future, callable, formatting or Error operations preserves the underlying
protocol and requires its declared bounds; Box does not itself make an
unpollable/uncloneable payload satisfy those interfaces.

## 4. Shared owners and weak handles

Rc is local reference-counted ownership; Arc uses thread-safe counting.
Each owns a handle to one payload/control allocation. `new[_in]` consumes
T and A, creates one strong handle and no user weak handles.
Fallible construction returns typed allocation failure with ordinary consumed
argument cleanup. Arc requires target-supported atomic counting; it is not
an automatic mutex around T. Cross-thread transfer/sharing additionally
requires the payload and allocator's appropriate structural properties.
Rc and its Weak do not cross threads.

`get/as_ref/Deref` lends read T. Explicit `retain` and owner Clone acquire
another strong handle, never clone T. Moving transfers one handle.
`downgrade` creates a weak handle without keeping T alive.
`Weak.new` constructs an empty handle without allocation; upgrade on it
always returns none. Dropping the last strong destroys T once. Weak handles
may keep allocation metadata alive after T's destruction; the last remaining
control reference releases that storage. Strong cycles can leak.
Counter overflow aborts safely instead of wrapping.

`upgrade` attempts to acquire a strong handle and returns none after strong
ownership has reached zero; it cannot race with destruction to resurrect T.
Arc's successful upgrade coordinates with payload lifetime using its atomic
count protocol. `ptr_eq` compares allocation identity/addresses without
payload comparison, ignoring irrelevant erased metadata.
`strong_count/weak_count` exclude internal implementation weak bookkeeping.
For local owners counts are exact at observation; Arc observations are
snapshots immediately subject to concurrent changes, never uniqueness proofs.
Weak observations on expired payloads report no strong ownership and
weak_count returns zero rather than the dead allocation's retained metadata
count. Arc count observations remain inherently concurrent snapshots.

`get_mut` returns an exclusive payload view only when the strong owner is
unique and no other user weak handle can upgrade; otherwise none.
Arc must synchronize that check against concurrent weak operations.
Unsafe `get_mut_unchecked` requires no competing payload access and all
aliases to refer to the identical concrete payload/region interpretation
for the entire returned exclusive loan; counting alone is insufficient.
`make_mut<T: Clone>` returns exclusive payload access:
when another strong owner exists it clones T into a new allocation; with
only weak aliases it dissociates them without cloning T; with no aliases
it reuses the allocation. Old weak handles cannot upgrade to the new owner.
The operation may allocate and panic/abort under those selected operations.

`try_unwrap(take owner)` succeeds when this is the only strong handle,
transferring T and releasing storage/control responsibility correctly;
user weak handles do not prevent success. On failure it returns the original
strong owner, not a new retained clone.
`into_inner(take owner)` instead drops this handle and returns none if
another strong handle exists. For Arc, when every strong handle is consumed
by into_inner, exactly one call must return the payload; separate
try_unwrap-then-discard operations do not have that collective guarantee.
`unwrap_or_clone<T: Clone>(take owner)` transfers T when unique, otherwise
clones T and drops this strong handle.
`downcast<T: Any + Static>(take erased_owner)` tests exact payload type
identity. Success transfers the same counted responsibility as Rc<T>/Arc<T>
without allocating or cloning T; failure returns the original erased owner
with its count unchanged.

`new_cyclic(make: take fn(read Weak<T>): T)` allocates control storage before
calling make with a borrowed weak handle; that handle cannot upgrade while
construction is in progress. The callback may explicitly retain weak handles
inside its result. Publish the initialized T and first strong owner only on
success. Panic cleans partial construction without destroying nonexistent T;
escaped weak handles remain non-upgradeable. A new_cyclic callback does not
receive an initialized shared T.
Uninit/zeroed scalar/slice construction and unsafe assume_init follow section
3's validity/partial-initialization rules, with shared-count lifetime retained.
Pinning establishes stable payload storage, not a clone or thread upgrade.

`as_ptr` borrows a raw payload address without changing counts.
`into_raw` transfers exactly one strong responsibility to raw form.
Unsafe `from_raw[_in]` requires a matching live raw strong responsibility,
layout/metadata and allocator; it must not increment the count again or run
twice. Unsafe `increment_strong_count` requires a live strong allocation,
correct compatible allocator/metadata and room in the counter; it acquires
one responsibility. `decrement_strong_count` consumes one such responsibility
and may destroy/deallocate. Weak raw conversion transfers/reconstructs one
weak responsibility, including after payload destruction; it does not make
the dangling payload readable. Empty weak reconstruction follows its
designated empty sentinel representation, not arbitrary NonNull storage.

All count/handle operations use O(1) work excluding contention, allocation and
destruction; no lock-free progress bound or constant-time payload clone is
promised. Shared-owner equality/order/hash use T, not pointer identity.
Their Clone operation retains; cloned-owner replacement releases the old
handle after obtaining the new one according to replacement cleanup.

## 5. List and allocation-backed slice operations

`List<T,A>` owns length initialized elements in contiguous storage of capacity.
Only [0,len) may be read/dropped as T; spare slots are uninitialized storage.
`new/new_in` is empty and allocates no element storage.
`with_capacity(n)` guarantees capacity >= n; zero does not allocate element
storage. `as_slice/as_mut_slice`, get and iteration lend existing storage.
The complete slice operation groups of core sections 5/5.1/5.2 are also
available through List's corresponding borrowed slice, retaining their bounds.

`reserve(additional)` ensures capacity >= len+additional, preserving contents;
`reserve_exact` does not deliberately choose geometric extra capacity, though
the allocator may supply more. Already sufficient capacity does not reallocate.
Try variants preserve contents and allocation on failure.
`shrink_to_fit` attempts to reduce excess capacity, never below len;
`shrink_to(min)` never below max(len,min) and does not grow an already smaller
allocation. Neither guarantees capacity equals a requested value.
Growth/shrink may relocate every element by move, not Clone.
Allocation growth costs O(len) moved elements at worst; end-push has
amortized O(1) work, excluding allocator/payload work, without prescribing
a particular growth factor.

| Members | Effect |
| --- | --- |
| `push(take T)` | Append, allocate if needed |
| `push_mut(take T)` | Append and return exclusive view of inserted last element |
| `try_push(take T)` | Append or return owning PushError |
| `pop()` | Transfer last T or none, without allocation |
| `pop_if(test: take fn(mut T): bool)` | On nonempty test last once, remove iff true; mutation survives false/panic; empty does not call |
| `insert(i,take T)` | Require i <= len; shift suffix right, insert; panic otherwise |
| `insert_mut(i,take T)` | Same and return exclusive inserted view |
| `remove(i)` | Require i < len; transfer element, shift suffix left |
| `swap_remove(i)` | Require i < len; replace removed slot with last element, no order guarantee |
| `truncate(n)` | Destroy suffix when n < len; n >= len is no-op |
| `clear()` | Destroy all elements, keep capacity |
| `append(mut other)` | Move other's elements after self; other becomes empty retaining its allocation |
| `split_off(i)` | Require i <= len; return new owner of suffix, leave prefix with original capacity |
| `resize(n,take T)` | Shrink by destruction or append Clone copies of T |
| `resize_with(n,make: mut fn(): T)` | Call only for new slots, once per slot, in order |
| `extend_from_slice(read [T])` | Clone each source element in order |
| `extend_from_within(range)` | Clone selected original in-range elements onto end; invalid range panics |
| `retain(test: mut fn(read T): bool)` | Visit every original element in order, keep true elements in original order |
| `retain_mut(test: mut fn(mut T): bool)` | Same, with element mutation |
| `dedup` | Remove adjacent equal items, retaining the first in each run |
| `dedup_by(same: mut fn(mut T,mut T): bool)` | Test later then earlier retained element; remove later on true |
| `dedup_by_key(key: mut fn(mut T): K)` | Adjacent dedup by PartialEq keys; may recompute keys |

Push/pop/swap_remove are O(1) apart from growth. Insert/remove are O(suffix);
append/split/resize/extend are O(affected elements) plus allocation and Clone.
Retain/dedup are O(len) predicate visits with constant auxiliary element
storage. A callback panic preserves initialized retained/unvisited elements;
discarded elements are not restored and user mutations persist.

Unsafe `set_len(n)` requires n <= capacity and every newly included element
already valid and initialized; decreasing does not drop excluded elements,
so caller owns their cleanup obligation. `spare_capacity_mut` lends
[MaybeUninit<T>] over len..capacity without publishing those slots as elements.
Unsafe `from_raw_parts(p,len,cap)` requires a compatible live allocation of
exact cap-element layout/alignment, len <= cap, initialized valid prefix,
target size bounds and unique destruction/deallocation responsibility.
It is invalid to invent capacity from a pointer into another owner.
`from_parts` is the NonNull form with identical conditions.
`into_raw_parts/into_parts` consume without dropping elements/allocation,
returning pointer,len,capacity (and allocator for explicit allocator forms).
Raw pointer recovery must preserve that allocator; safe element views are
not transferable ownership receipts.

`into_boxed_slice` consumes the List and may discard excess capacity through
reallocation; no element Clone is needed. `leak` suppresses cleanup while
preserving embedded regions. `into_flattened` for List<[T;N]> transfers the
same elements to a List<T> with checked product length/capacity; the zero-
sized product overflow case panics rather than wrapping. Consuming List
iteration is exact-size, bidirectional, fused and drops only remaining
elements before freeing the original allocation. `as_slice/as_mut_slice`
on its iterator expose only remaining initialized elements.

### 5.1. Drain, splice and extraction

`drain(range)` requires a valid ordered in-range interval and borrows List
exclusively for the iterator lifetime. It yields removed elements by move
in index order; next_back shares that range without duplicates.
Dropping it destroys unyielded removed elements and restores the retained
tail after the prefix; it retains capacity. Work is O(removed+shifted tail).
`as_slice` on the drain borrows its remaining removed elements.
Leaking it may lose elements outside the nominal range; no leak-equivalence
to completed removal is promised.

`splice(range,take replacement: I)` has I: OwnedIterable<Item=T>.
It yields the removed interval as a drain, then inserts replacement items
at the same position, preserving their order and the tail. Destruction
completes removal/insertion even if removed items were not demanded.
Replacement conversion/pulls may therefore occur during destruction and
may panic or allocate. A forgotten splice need not consume replacement or
preserve every otherwise-retained element. A panic preserves valid owned
elements but need not leave the intended full replacement. Auxiliary
allocation can be needed for unknown-length replacement; cost is O(old
affected extent + inserted items), excluding input iteration and allocation.

`extract_if(range, test: mut fn(mut T): bool)` visits only the selected
original interval and lazily removes/yields true elements in order.
False elements and unvisited elements remain, in order; their mutations
persist. Dropping early stops testing and retains unvisited elements,
unlike drain. The predicate is never re-invoked for an already-tested item.
Predicate panic retains the currently tested element and its mutations.
Tail compaction costs O(len) overall, with constant extra element storage.

### 5.2. Allocating slice algorithms

`to_vec/to_owned` clone each borrowed T into new List storage, cleaning a
constructed prefix on failure. `repeat(n)` checks product length and clones
the original sequence n times in order. `concat` concatenates borrowed
subsequences; `join(separator)` inserts the separator only between input
subsequences. They preserve element/text order, require the relevant Clone/
borrow bounds, and cost O(output length) plus those payload operations.

`sort/sort_by/sort_by_key` stably sort the exclusive slice ascending;
equal keys preserve original element order. Comparators receive read
elements; key callbacks produce owned Ord keys and may be called repeatedly.
Worst-case comparisons O(n log(n+1)); temporary element storage O(n).
`sort_by_cached_key` computes the key at most once per element, sorts using
those retained keys, preserves equal-key element order, and uses O(n)
extra keys/indices and O(n log(n+1)) comparisons. Callback/key destructor
panic preserves initialized original elements with possible reordering.
Non-total comparators can panic or produce unspecified ordering but cannot
cause memory unsafety. Nonallocating unstable sorting remains in core.

## 6. VecDeque

VecDeque<T,A> is a growable double-ended sequence. Logical index order is
front to back; its storage may wrap. New/capacity/reserve/try-reserve/shrink/
clear/truncate rules match List, but no single contiguous element view is
implied. `as_slices/as_mut_slices` return two disjoint slices whose
concatenation is logical order; either may be empty. `make_contiguous`
reorders storage in O(len) work without allocation or changing logical
order, returning one exclusive slice.

`front/back/get` and mutable forms return optional views.
`push_front/push_back` consume an element, `pop_front/pop_back` transfer one
or none. End operations are amortized O(1), excluding growth.
`pop_front_if/pop_back_if` use an at-most-once exclusive predicate, retaining
mutations on false/panic and not calling it on empty.
`swap(i,j)` requires two valid indices.
`insert(i,take T)` permits i <= len; `remove(i)` returns optional owned T
and returns none if i >= len (unlike List.remove).
Shifting uses O(min(i,len-i)) moves. `swap_remove_front/back(i)` returns
none if out of range; otherwise fills the hole using the corresponding
end and transfers the removed value in O(1), not preserving order.

`rotate_left/right(n)` requires n <= len and moves logical elements
cyclically in O(min(n,len-n)) time without allocation.
`split_off(i)` panics for i > len, returns a separately allocated suffix,
and leaves original capacity unchanged. `append(mut other)` moves its entire
sequence to the back and empties other. `resize/resize_with/retain/
retain_mut` have List's ownership, predicate order, panic and stable
retention rules. `contains` scans; binary search and partition-point use
logical indices with the sorted/partitioned preconditions from core.
`range/range_mut` validate bounds and iterate the logical subrange.
Drain has List's ownership, early-drop and leak caveats, applied to logical
indices. Iterator/IterMut/IntoIter are exact-size, bidirectional and fused.
Deque/List conversion moves elements, may rearrange/reallocate storage and
never clones T. Physical wrap position is not observable semantic state.

## 7. LinkedList and BinaryHeap

### 7.1. LinkedList

LinkedList<T,A> owns individually linked nodes in logical order.
New is empty without node allocation. `front/back` and mutable forms lend
optional endpoints; push_front/back allocate a node and consume T;
pop_front/back remove a node and transfer T. Endpoint access/removal/link
updates are O(1) excluding allocation/destruction.
`append(mut other)` relinks all donor nodes in O(1) work/auxiliary storage,
leaving other empty. Compatible allocator identity must survive node
transfer; it cannot free donor nodes through an unrelated allocator value.
`split_off(i)` panics for i > len and transfers nodes at/after i to a new
list in O(len) time without cloning T. `clear` destroys every node/item.
`contains` and index-like extension queries scan O(len); no O(1) random
access promise follows from an optional native convenience get.
Iter/IterMut/IntoIter are exact-size, bidirectional and fused.
`extract_if(test: mut fn(mut T): bool)` lazily visits front-to-back, yields
removed true items and retains false/unvisited items and their mutations.
Panic retains the current tested item; drop stops visiting.
Unlisted cursor/entry/experimental insertion APIs are not covered here.

### 7.2. BinaryHeap

BinaryHeap<T: Ord,A> owns a max-heap. Every parent compares >= its children;
`peek` lends a maximum or none; `pop` transfers a maximum or none.
Equal maxima have no stable tie order. `push` inserts by move.
Peek is O(1), pop O(log(n+1)), push O(log(n+1)) worst case excluding growth;
construction from an owned List heapifies in O(n).
`as_slice` lends heap-storage order, not sorted order.
Capacity/reserve/shrink/clear follow List's allocation rules.
`append(mut other)` moves donor items and restores heap order, leaving it
empty; work is bounded by O((n+m) log(n+m+1)), with implementation free to
use a linear rebuild.

`peek_mut` returns an exclusive maximum guard or none.
Mutation may break the heap invariant only while that guard is active;
dropping the guard restores it in O(log(n+1)) work when necessary.
Guard `pop` consumes the guard, removes/returns that element and restores
the rest without dropping the transferred T. Leaking the guard may leak
some items but the safely accessible heap must remain valid.
Changing an element's ordering through interior mutability while stored is
a logic error confined to this heap: panic, leak, nontermination or wrong
ordering may result, not memory unsafety.

`into_vec` transfers storage in unspecified heap order without sorting;
`into_sorted_vec` transfers an ascending sorted List using in-place heap
sorting, O(n log(n+1)), no new element allocation.
Borrowed/consuming ordinary iterators yield heap-storage order, not repeated
maximum order; they are exact-size and fused with their declared
bidirectional capability only. `drain` yields all owned elements and empties
on drop. `retain(test: mut fn(read T): bool)` visits storage in unspecified
order, destroys false elements and restores the heap. It is not a sorted
predicate traversal. Comparison/predicate panic preserves initialized
ownership; restoration may be incomplete but safe later access cannot
assume invalid memory.

## 8. Maps, entries and ordered ranges

Both map families own unique keys and their associated values.
Keys are never exposed for ordinary exclusive mutation while stored.
Map requires compatible Eq/Hash; SortedMap requires Ord. Borrowed lookup
uses `K: KeyView<Q>` with Q's corresponding equality/hash/order laws.
These obligations include query/stored-key coherence, not merely an address
conversion to Q. Disobeying them is a contained collection logic error,
never permission for undefined behavior.

### 8.1. Lookup and mutation

| Members | Result |
| --- | --- |
| `get(read Q)` | Optional read V |
| `get_mut(read Q)` | Optional exclusive V |
| `get_key_value(read Q)` | Optional (read stored K,read V), not a view of query Q |
| `contains_key(read Q)` | Whether a matching entry exists |
| `insert(take K,take V)` | New key inserts; existing equal key remains the stored key, new V replaces old and old V is returned |
| `remove(read Q)` | Optional owned V, destroying removed K |
| `remove_entry(read Q)` | Optional owned (K,V) |
| `clear` | Destroy all entries; capacity retention only where exposed |
| `retain(test: mut fn(read K,mut V): bool)` | Retain true entries, allow value mutation, never mutable key access |
| `extract_if(test: mut fn(read K,mut V): bool)` | Lazily remove/yield selected owned pairs; false and unvisited remain |

Existing-key insertion consumes and destroys the unused incoming K rather
than replacing stored key identity. Predicate false/panic retains its value
mutations; panic retains the currently tested entry. Extract-if destruction
stops testing, not drain-all behavior.
SortedMap extraction may take an explicit valid key range and visits its
entries in ascending order; Map's order is unspecified.

`iter/iter_mut` yield (read K,read V)/(read K,mut V).
`keys/values/values_mut` project those items without cloning.
`into_iter/into_keys/into_values` consume the map; unused key/value components
are destroyed normally. Every yielded owned entry transfers its fields once,
and iterator drop destroys remaining entries.
Hash traversal order is unspecified. Sorted traversal is ascending, with
bidirectional operations from the same interval and no duplicate yields.
Exact-size operations report the actual remaining count; range iterators
do not gain exact size merely from full-map iterators.

### 8.2. Entry handles

`entry(take K)` borrows the map exclusively and returns Occupied or Vacant.
An occupied handle owns the unused query key until appropriate cleanup and
identifies the existing stored key; a vacant one owns its proposed key.
Handles preserve the map region and prohibit competing map mutation.
`key` always lends the relevant stored/proposed key.

`or_insert(take V)` inserts on vacant, otherwise destroys the unused value,
and returns an exclusive V view. `or_insert_with(make: take fn(): V)`
invokes make only on vacant. `or_insert_with_key(make: take fn(read K): V)`
reads the proposed key without cloning it; `or_default` calls V's Default
only on vacant. `and_modify(f: take fn(mut V): Unit)` calls once only on
occupied and returns the entry handle, preserving value mutations on panic.
`insert_entry(take V)` installs/replaces and returns Occupied; replacement
destroys the old V, unlike occupied `insert` which returns it.

Occupied `get/get_mut` lend the stored V; `into_mut` consumes the handle and
lends it with the original map loan. `insert(take V)` returns old V without
changing K. `remove` transfers V; `remove_entry` transfers (K,V).
Vacant `into_key` consumes the handle and returns its proposed K;
`insert(take V)` inserts the owned K/V and lends V; `insert_entry` instead
returns an occupied handle. Lazy initializer panic leaves the entry vacant;
the handle's key is cleaned normally. Entry interfaces require the actual
map's key bounds, allocator and hash policy; they do not bypass lookups.
Raw-entry/cursor interfaces are not implied by this entry contract.

### 8.3. Hash Map

Map<K,V,S,A> carries its hash-builder policy S and allocator A; native
declarations that select a policy must make it visible.
`with_hasher/with_capacity_and_hasher` consume the supplied builder, and
`hasher` borrows it. Every lookup hashes under that same builder and verifies
equal keys, not hash equality alone. A fixed/unkeyed policy is not collision-
attack resistant.

Owner decision D30 selects a deterministic alloc default. `new` and
`with_capacity` without an explicit builder select that policy; a generic
`Default` construction uses the selected S's Default implementation.
Construction neither requests hidden OS entropy nor implies collision-attack
resistance. Determinism does not stabilize the algorithm, exact hash bytes or
iteration order across releases.

Untrusted-key applications explicitly supply a randomized builder.
Hosted entropy acquisition belongs to std, not alloc; a caller-provided
builder can likewise supply its own policy without adding an alloc dependency.
A seeding failure must not silently substitute the deterministic default while
claiming randomized behavior. Builder construction retains its own declared
failure/effect contract. Selecting a randomized policy does not make arbitrary
user Hash implementations collision resistant.

New Map has no entry storage. Reserve/try-reserve/shrink follow section 1
and need not retain existing iteration order. Capacity is a lower bound on
entries insertable before growth. Lookup/remove are expected O(1) under
well-distributed hashes, O(n) worst case under collision; insertion is
expected amortized O(1), O(n) worst case excluding resizing/payload work.
Full iteration, retain and drain have O(capacity) upper traversal cost where
the table scans empty buckets; no O(len)-only requirement is weakened for
ordered containers. A denser native implementation may be faster.
`drain` empties entries while preserving allocation and yields owned pairs;
dropping the drain destroys unyielded entries.

`get_disjoint_mut<Q,const N>(keys: [read Q;N])` validates duplicates/overlap
before returning independent optional exclusive value views.
Missing keys produce none; two requests resolving to the same stored entry
panic.
Duplicate detection takes O(N^2) worst-case comparisons.
Unsafe unchecked form requires that no two present requests address the
same stored entry even if the returned views are never used.
The caller cannot bypass that precondition by dropping one result unused.

### 8.4. SortedMap

SortedMap maintains ascending key order. Lookup, ordinary insertion/removal
and endpoint operations take O(log(n+1)) comparisons, excluding allocator/
payload effects. Full iteration is O(n) total, O(log(n+1)) initial search
for a bounded range, amortized O(1) per subsequent yielded entry.
No public B-tree node degree/layout is guaranteed.
New is empty without nodes; capacity/reserve APIs are not invented.

`first_key_value/last_key_value` lend extrema or none;
`first_entry/last_entry` return optional occupied endpoint handles;
`pop_first/pop_last` transfer optional extreme (K,V).
`range<R: RangeBounds<Q>>` and `range_mut` select keys by Included/Excluded/
Unbounded endpoints, return borrowed/mutable-value bidirectional iteration,
and panic when start > end or equal endpoints are both Excluded.
An empty result for a valid range is not an error.
`split_off(read Q)` transfers all keys >= the split key into a new map,
preserving smaller keys in self. `append(mut other)` empties other and
moves its entries; for duplicate keys the receiver's stored key remains
and donor V replaces receiver V. Equivalent but distinct donor keys are
destroyed. Conservative work is O((n+m) log(n+m+1)), with allocation allowed.
Allocator clones/transferred nodes must remain compatible with their
original allocations.

## 9. Sets

Set<T,S,A> and SortedSet<T,A> store one representative of each equality/order
class. They have their respective map's lookup, allocator/hash policy and
complexity rules. They lend read elements, never ordinary exclusive elements.
`get(read Q)` returns a stored representative; `contains` tests membership.
`insert(take T)` returns whether new; an equal stored representative remains
unchanged and the unused input is destroyed.
`replace(take T)` installs the new representative and returns the old one
or none on new insertion. `take(read Q)` transfers the removed representative;
`remove` returns bool and destroys it. Retain/extract-if predicates read T;
they do not acquire key mutation rights. `clear/drain` destroy or transfer
under the corresponding collection's rules.

`difference/intersection/union/symmetric_difference(read other)` return
lazy borrowed set iterators; an intersection may select either set's
representative for an equal element and its result region must cover the
possible source. Difference yields only self; symmetric difference excludes
shared classes. Union yields each class once.
`is_subset/is_superset/is_disjoint` are early-terminating membership tests.
SortedSet algebra iterates ascending in O(n+m) comparison work and constant
iterator state. Hash Set algebra uses expected O(n+m) hashing/equality work,
or O((n+m)^2) worst case under collisions, plus its table traversal extent.
No algebra iterator receives stronger exact-size/bidirectional properties
without its declared implementation.
Owning operator forms for union/intersection/difference/xor that take read
sets require T: Clone and construct a new owning set; they do not transfer
elements through borrowed inputs. Their costs include cloning and allocation.

SortedSet `first/last` lend extrema; `pop_first/pop_last` transfer them.
Range selection and its invalid-bound panics match SortedMap.
`split_off(read Q)` transfers elements >= Q; append empties the donor while
preserving one valid representative per key class. It does not promise which
equivalent representative is retained beyond any explicitly specified
insertion/replacement operation. Hash-specific entry/get-or-insert methods
not listed here need separate member contracts; nightly sorted-set entry
facilities are not stabilized by this document.

## 10. String, CString and borrowed-or-owned values

### 10.1. String

String<A> owns a growable UTF-8 byte sequence, length and capacity in bytes.
No embedded NUL prohibition or trailing terminator is imposed.
New is empty without byte allocation. `from_text/String(read Text)` copies
UTF-8 bytes visibly into owned storage. `as_text/as_str/as_bytes` lend;
mutable text lends validated exclusive Text, not an unrestricted byte list.
All covered Text search/view/iteration operations apply to these borrowed
views without allocating or cloning.
Reserve/shrink and try variants use byte additional capacity.

`from_utf8(take List<u8>)` validates then reuses ownership on success; on
failure FromUtf8Error owns the original byte List and the Utf8Error.
Error `as_bytes/utf8_error` query; `into_bytes` returns the exact owned bytes.
Unsafe `from_utf8_unchecked` requires full valid UTF-8.
`from_utf8_lossy(read [u8])` returns borrowed-or-owned text, borrowing when
valid and otherwise allocating a String replacing each maximal malformed
UTF-8 subsequence with U+FFFD. Incomplete final input is one replacement.
`from_utf8_lossy_owned(take List<u8>)` reuses a valid input allocation when
possible; replacement may allocate, without leaking the original bytes.

`from_utf16(read [u16])` rejects unpaired surrogates with FromUtf16Error;
lossy form replaces each unpaired surrogate with U+FFFD.
`from_utf16le/be(read [u8])` decode units with the named endian independent
of target endian; strict forms reject odd byte length and unpaired
surrogates. Lossy forms replace malformed units and an odd final byte.
No BOM is automatically stripped. Conversion is O(input+output length).

| Members | Effect and bounds |
| --- | --- |
| `push(char)` / `push_str(read Text)` | Append encoding/bytes, grow if needed |
| `pop()` | Transfer last scalar or none |
| `insert(i,char)` / `insert_str(i,read Text)` | i must be in-range UTF-8 boundary; shift suffix and insert |
| `remove(i)` | i must be a scalar start < len; remove/return that scalar |
| `truncate(n)` | If n < len require boundary and destroy suffix bytes; n >= len is no-op |
| `clear()` | Empty, retain capacity |
| `split_off(i)` | Require in-range boundary; return independently owned suffix, retain prefix |
| `retain(test: mut fn(char): bool)` | Visit original scalars once in order, keep true encodings in place |
| `extend_from_within(range)` | Copy an in-range boundary-delimited original byte interval to end |
| `replace_range(range,read Text)` | Require ordered in-range boundaries; replace that interval and preserve UTF-8 |
| `drain(range)` | Exclusively borrow, iterate removed chars, complete byte removal on drop |

String drain is bidirectional and fused but not byte-length ExactSize for
char items. Leaking it need not remove the interval. Retain predicate panic
keeps initialized valid UTF-8 and previously retained/unvisited content,
with completed removals not restored.
Appending is amortized O(appended bytes); insert/remove/truncate/split/
replacement cost O(affected bytes) plus allocation where necessary.
Pop decodes only one scalar. Extend/collect from chars encodes each scalar;
from Text pieces appends their bytes; from owned pieces transfers contents
without any requirement to reuse every input allocation.

`repeat(n)` checks byte length multiplication, returning n copies.
`replace/replacen(pattern,replacement[,count])` construct new owned text
from nonoverlapping forward matches, at most count for replacen.
An empty pattern matches scalar boundaries and still makes progress.
`to_lowercase/to_uppercase` use core's Unicode mappings (including final
sigma for whole-text lowercase), allocating O(output bytes);
ASCII variants change only ASCII letters and retain every non-ASCII byte.
`make_ascii_lowercase/uppercase` mutate without changing length/UTF-8.

`into_bytes` transfers its byte List without cloning. `into_boxed_str`
consumes and may shrink; `leak` deliberately suppresses storage cleanup
without extending embedded regions. Unsafe `as_mut_vec/as_bytes_mut` require
restoring valid UTF-8 and the storage's owner invariants before safe String
access resumes. Raw-parts construction requires valid initialized UTF-8
prefix, length <= capacity, correct allocation/layout/alignment and unique
deallocation responsibility; inverse raw-parts conversion transfers those
responsibilities. Byte alignment is one, not permission to free any aligned
foreign pointer. String implements fmt.Write by appending; sink writes may
allocate and follow ordinary allocation failure policy.

### 10.2. CString

CString owns arbitrary non-NUL bytes followed by one NUL terminator, normally
with Global storage. It need not contain UTF-8.
`new(take bytes)` rejects interior NUL and returns NulError containing its
position and the original bytes; otherwise it appends the terminator.
`from_vec_with_nul(take bytes)` requires exactly one terminal NUL and
rejects an earlier/missing terminator, returning an error owning the input.
Unsafe `_unchecked` constructors require their respective interior/terminal
conditions; they do not legalize arbitrary byte lengths or foreign storage.
Nonzero-byte sequence conversion can rely on its actual NonZero<u8> validity.

`as_c_str/as_bytes/as_bytes_with_nul` lend the content excluding/including
the terminator as named. `into_bytes/into_bytes_with_nul` consume and transfer
those owned byte sequences. `into_string` validates UTF-8, producing String
or IntoStringError owning the original CString and Utf8Error; accessors
preserve/recover those values without losing bytes.
`into_boxed_c_str` transfers owned terminated content to boxed CStr;
borrowed/owned conversions copy only when ownership actually must be created.
Comparison/order/hash use content bytes, not allocation addresses.

`into_raw(take CString)` transfers its global allocation responsibility to
a C pointer. Unsafe `from_raw` requires that exact outstanding pointer from
CString.into_raw, not malloc, a borrowed CStr or an interior pointer.
The first NUL must remain at the original position so the allocation's
length/layout can be reconstructed; foreign code may change non-NUL content
but may not insert/move the terminator, reallocate, or free the block.
Reconstruct exactly once, with no live conflicting views. CString.as_ptr
is borrowed and must not be freed or reconstructed.
These are additional source-specific ownership/layout preconditions beyond
the C platform's readable-NUL-string requirement.
Construction/conversion/raw reconstruction costs O(bytes) when a scan is
needed. Default is an empty terminated C string, not an unterminated zero-
capacity byte list.

### 10.3. Cow

Decision D31 names general borrowed-or-owned storage
`alloc.borrow.BorrowedOrOwned<region r,B>`.
It has Borrowed(read B from r) or Owned(B.Owned),
with `B: core.borrow.OwnedType + unsized`. Reading/Deref lends B regardless of branch.
`is_borrowed/is_owned` test the branch.
`to_mut` requires ToOwned and exclusive handle access: borrowed content is copied through
ToOwned before yielding mut Owned; already-owned content is reused.
`into_owned` requires ToOwned and consumes: it clones borrowed content through ToOwned and moves
owned content unchanged. Clone of Borrowed copies its view; Clone of Owned
duplicates its content under the selected ToOwned/Clone contract.
Panic during copying cleans a partial owner; it never exposes uninitialized
owned storage.

For `[T]`, the associated owner is List<T>; for Text it is String, and for
CStr it is CString. Hosted Path/OsStr implementations associate PathBuf/
OsString in std; mentioning those instantiations adds no std dependency to
alloc. User-defined B retains its declared associated owner and bounds.

The selected slice spelling `Cow<region r,T>` is the alias for
`BorrowedOrOwned<region r,[T]>`, not a duplicate implementation.
Its into_owned requires T: Clone, copies borrowed items, and moves an owned
List without cloning. Reading and extracting an already-owned variant do not
require an element Clone bound.

The owner-approved 2026-11-11 refinement separates ownership identity from
copying rather than requiring ToOwned on the enum. The slice identity exists
for every T; only copying from borrowed storage requires T: Clone. The core
protocol and its in-tree implementations migrate explicitly; no compiler
special case infers an owner or grants cloning without its bound.

## 11. Structural implementations, cleanup and applicability

Collection Clone reads the original and constructs an independent container,
cloning each stored element/key/value under the declared Clone bounds.
It may reuse capacity in clone_from; it must clean partial clones on panic.
Rc/Arc/Weak Clone instead retains ownership bookkeeping, not payloads.
Box Clone duplicates T and its storage, not its pointer responsibility.
String/CString Clone duplicate owned bytes. Allocator cloning must preserve
the allocator's stated compatibility, not select a convenient different heap.
Default constructs the type's empty/default value only under its declared
allocator/hash-builder/payload bounds.

Sequence equality/order/hash use logical element order, independent of capacity,
addresses and node shape. String/Text use UTF-8 bytes; C strings use their
content bytes. Map equality compares key/value associations, independent of
hash iteration order; Set equality compares membership. Ordered-map/set
ordering is lexicographic in key order. Hash-map/set ordering and structural
Hash are not invented merely because their items are ordered/hashable.
Debug iterates the type's specified traversal and writes into the supplied
formatter without requiring an intermediate String; formatting a value retains
its own effects/cost.

All alloc operations require the explicit allocation layer but not an OS,
process, threads or executor. Global freestanding programs must provide the
selected allocator boundary. Arc additionally needs target atomic support;
its payload/allocator thread properties stay explicit.
V1 execution scope is Linux x64; all eight reference profiles remain post-V1
obligations. Layout arithmetic, pointer sizes and foreign scalar types are
target-derived. Allocating operations are not implicitly usable in required
constant evaluation. For each operation specified here, the local catalog's
exact stable constant-callability flag remains native eligibility metadata
under T08, evaluated solely with native constant/memory rules as described in
core section 15.1. This does not grant allocation, payload Clone/destruction or arbitrary
allocator/hash-builder construction a constant-evaluation capability.
Construction, failure, destruction and borrowing semantics do not vary with
optimization profile.

## 12. Exact coverage and remaining work

The authored runtime coverage is the explicit groups in sections 1..11:

| Native module/type (source family) | Assigned groups |
| --- | --- |
| `alloc.alloc`, core.alloc reexports | Layout construction/access/array/extension/alignment/padding/repetition/dangling; native allocator operations; raw global allocation/provider operations |
| `alloc.boxed.Box` | Initialized/uninitialized/zeroed construction, projections, extraction/raw/leak/pin/downcast, array/slice iteration and listed conversions |
| `alloc.rc.Rc/Weak`, `alloc.arc.Arc/Weak` (source sync) | Construction/retain/weak/count/uniqueness/extraction/cyclic/uninit/raw/pin groups |
| `alloc.vec.List` | Capacity, mutation, raw/spare storage, drain/splice/extract, slice delegation, flatten/box/leak/iteration groups |
| `alloc.vec_deque.VecDeque` | End/index movement, storage views/contiguity, range/drain/iteration, capacity/resize/retention/conversion groups |
| `alloc.linked_list.LinkedList` | Endpoints, nodes/append/split, traversal/containment/extraction/cleanup |
| `alloc.binary_heap.BinaryHeap/PeekMut` | Heap query/push/pop/guard/retain/drain/storage/sorted conversion/capacity |
| `alloc.hash_map.Map` and entries | Lookup/insert/remove/mutable values, iteration, entry, drain/extract, capacity/hash policy, checked disjoint lookup |
| `alloc.btree.SortedMap` and entries | Shared map/entry operations, ordered ranges/endpoints/split/append |
| Set/SortedSet | Membership/representatives/algebra/traversal, ordered endpoints/range/split/append |
| `alloc.string.String` | UTF encoding/conversion, byte capacity/mutation, view delegation, drain, owned search replacement/case/repeat/raw operations |
| `alloc.ffi.CString` and error types | Termination validation, owned recovery/UTF conversion, borrowed/boxed/raw conversions |
| `alloc.borrow` | ToOwned, general BorrowedOrOwned branch/projection/owning conversion and the selected slice Cow alias |
| allocation-backed slice methods | Cloning/concat/join/repeat and stable/cached-key sorting |

This table is a selector boundary for the named operations, not a wildcard
claim over every member, inherited implementation and constant in a type's
inventory. In particular, full retirement still needs:

- Member-by-member reconciliation for storage writers other than the covered
  write_copy_of_slice, and unlisted push/entry/cursor helpers.
  Core sections 4/5 cover address-based substring/element/subslice queries
  and split-off-view helpers, including their zero-size/provenance caveats.
  No whole Vec/str/slice page may be assigned
  solely because most methods are described here.
- Runtime members not specified here remain unmigrated; their local stable
  constant-callability metadata does not substitute for a missing runtime
  semantic contract.
- General BorrowedOrOwned declarations, the slice alias's non-Clone extension
  and complete hash-builder constructor/member reconciliation. D30/D31 resolve
  the policy and naming decisions, not their implementation/type-checking
  receipts. The current zero-key implementation is not randomized.
- Full source-cfg applicability and target ABI/allocator/thread evidence
  on the seven non-V1 profiles. No platform coverage follows from portable
  prose alone.

Concrete source reconciliation findings, not executed failures:

- `library/alloc/alloc.mt` layout validation embeds a 64-bit isize maximum;
  layout_from_size_align must use target isize::MAX. extend_layout currently
  pads its final size, unlike the unpadded extend result specified in section
  2; callers needing padding must request it explicitly.
- The same file's Allocator.deallocate/grow/shrink declarations do not mark
  their raw ownership preconditions unsafe, and grow does not enforce the
  grow-only direction. A public safe caller must not be able to free arbitrary
  storage by merely passing a raw pointer and a Layout.
- `library/alloc/hash_map.mt` chooses a zero-key hash helper and exposes a
  smaller generic policy shape than Map's full source-family builder surface.
  Treat policy/constructor coverage as partial, not as an implicit random
  default or missing-key guarantee under mismatched KeyView hashes.
- `library/alloc/borrow.mt` supplies only slice Cow, is_borrowed, as_ref and
  into_owned; BorrowedOrOwned/to_mut and its other member assignments remain
  implementation/reconciliation work.

No build, runtime, constant-evaluation, complexity benchmark, sanitizer or
target qualification was performed while authoring these contracts.
