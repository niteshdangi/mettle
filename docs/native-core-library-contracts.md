# Core library operation contracts

Status: authored native specification, not an implementation or qualification
receipt. The member groups explicitly described below have independent Mettle
semantics. The coverage boundary in section 15 is part of this specification;
mentioning a module does not assign every declaration in it native authority.

[Core semantics](core-semantics.md), [typing](semantic-rules.md),
[the memory model](memory-and-concurrency.md), and
[native signatures](library-surface.md#2-recursive-translation-rules) supply the
language rules. The names here are native names; source names in parentheses
identify declarations during migration, not an alternative implementation.
Optional and stored-outcome methods are specified separately in
[native-value-contracts.md](native-value-contracts.md). Allocation, owners,
owned text and collections are specified in
[native-collection-contracts.md](native-collection-contracts.md).

## 1. Access, callbacks, failure and cost

`read T from r` lends initialized T for region r; `mut T from r` lends exclusive
access; `take T` transfers an owner, including a Copy owner explicitly taken.
A returned view inherits its backing region. Methods cannot extend that region,
retain a shared owner, or duplicate an element to make a signature convenient.
All type arguments, associated types, const lengths and independent regions
remain explicit in the operation's declaration. `T: unsized` removes only the
ordinary Sized requirement.

An unqualified query reads its receiver. Mutations require `mut`; transformations
of an owner require `take`. A callback repeatedly invoked by an algorithm has
the capability `mut fn(...)`; an at-most-once callback accepts
`take fn(...)`. A read-callable callback may satisfy either capability.
Callback input modes are given below; they do not follow from Copy
specialization. Captures move into an adapter when that adapter takes the
callback. Core never allocates or erases a callback implicitly.

Argument evaluation precedes entry in source order. Unselected eager inputs
are still constructed and destroyed. Lazy callbacks run only when selected.
A callback or destructor panic propagates through normal cleanup; typed
failure is never manufactured from panic. A callback may change its own state,
interior-mutable values, or explicitly borrowed mutable inputs before failing;
these effects are not rolled back. Partial construction tracks exactly the
initialized fields/elements. Unwind destroys those, never uninitialized storage.
A second destructor panic during unwind follows the language abort policy.
Safe algorithms remain memory-safe with inconsistent comparisons, hashes or
predicates, though their logical results may be unspecified as stated below.

Unless specified otherwise, a scalar query, projection, adapter constructor or
single handle operation takes O(1) work and auxiliary storage and allocates
nothing. Costs exclude invoked callbacks, payload operations, destructors and
sink work. A scan is O(n) visited items, not a promise that a callback is O(1).
Core algorithms use no allocator or OS. Algorithms explicitly assigned to alloc
may allocate. Forgetting a guard/iterator may leak resources but cannot make
later safe operations expose invalid values.

## 2. Comparison, duplication, defaults and conversions

### 2.1. Comparison

`PartialEq<Rhs: unsized = Self>.eq(read Rhs): bool` compares values;
`ne` is its complement. Symmetry and transitivity must hold wherever the
corresponding cross-type implementations exist. `Eq` additionally requires
reflexivity. `PartialOrd<Rhs>.partial_cmp(read Rhs): Ordering?` returns
Less, Equal, Greater, or absence for incomparable values. Its `lt/le/gt/ge`
queries return false on absence. Comparison must agree with equality and be
transitive across supported operand types. `Ord.cmp(read Self): Ordering`
provides a total order consistent with PartialOrd and Eq.
Violating these laws is a logic error, not permission for unsafe behavior.

`Ordering` has Less, Equal and Greater. Its six `is_*` predicates test those
relations to Equal. `reverse` exchanges Less/Greater. `then(other)` selects
other only on Equal; `then_with(make: take fn(): Ordering)` invokes make only
on Equal. Both preserve a non-Equal receiver.

Free `min<T: Ord>(take a, take b)` returns a on equality; `max` returns b.
`min_by/max_by` use `mut fn(read T, read T): Ordering`; `_by_key<K: Ord>`
uses `mut fn(read T): K`. Unreturned operands and temporary keys are destroyed.
`Ord.min/max` follow the same tie rules. `clamp(take value, take low, take high)`
first requires `low <= high`, panicking otherwise even if value is already in
range; it returns low, high, or value according to the comparison. Bounds are
consumed and unreturned bounds destroyed. `Reverse<T>` reverses comparison,
not equality, hashing, representation, or ownership.

Primitive integers, bool and char compare by numerical value; false precedes
true. Text compares lexicographically by UTF-8 bytes, equivalently scalar
order. Arrays, slices, tuples and ordered sequence containers compare
lexicographically, shorter equal prefixes first. Unit values are equal.
Optional orders none before present; outcomes order success before failure;
within matching alternatives payload comparison is used.
The relevant payload interface bounds remain necessary. Float comparisons
use section 3.3, not Ord.

### 2.2. Clone and Default

`Clone.clone(): Self` reads its receiver and returns another value according
to its type's duplication contract. It need not duplicate shared payload
storage. `clone_from(source: read Self)` requires a mutable destination and
leaves it equivalent to a fresh clone on success; allocation reuse is allowed,
not required. A failed clone need not preserve its old value but must leave
valid destination storage. Copy implementations must clone as a plain value
copy and remain eligible only under the language's explicit Copy rules.

Thin function pointers implement Clone by copying the pointer, without cloning
arguments or results. Cloning preserves parameter access, result regions,
failure effects, unsafe qualification and calling convention. This does not
give every Copy type a blanket Clone implementation.

Structural Clone processes fields/elements in declaration/index order, clones
only the active enum alternative, and cleans partial results on panic.
Structural Default calls field defaults in declaration order. There is no
universal default enum alternative; an explicitly selected default unit variant
is used where supported. `Default.default(): Self` has no implicit allocator
parameter or purity guarantee. Primitive defaults are zero, positive floating
zero, false, NUL char and Unit; optional defaults to none. Arrays default each
element under the declared supported array implementation; tuples default each
component. The selected fixed-array Default implementations cover N == 0
without T: Default and N == 1..32 with T: Default; this does not create an
unbounded generic Default array implementation. Selected tuple structural
comparison/Clone/Default/Hash implementations cover the declared tuple arities
through twelve, with the corresponding component bounds. Nonzero integers
and references have no fabricated zero default.

### 2.3. Conversion and borrowed protocols

`From<S>.from(value: take S): Self` consumes S without a typed failure result.
`Into<D>.into(): D` consumes its receiver and dispatches to D's selected From.
`TryFrom<S>.try_from(take S): (Self throws Error)` and the corresponding
`TryInto<D>` preserve the declared associated Error, not a generic panic.
A conversion may allocate only when its destination's contract requires it.
Identity conversion moves its input. `identity<T>(take value): T` does likewise.
`Infallible` has no values; it cannot be synthesized on a failed conversion.
No unchecked numeric cast is implicitly substituted for a checked conversion.
The selected lossless numeric conversions are specified in
[library-and-abi section 3](library-and-abi.md#3-text-and-collection-contracts);
this does not introduce additional blanket implementations.

`AsRef<T: unsized>.as_ref()` and `Borrow<T: unsized>.borrow()` return
`read T from self`. `AsMut`/`BorrowMut` return exclusive views through exclusive
receiver access. BorrowMut requires Borrow. AsRef may expose a component;
Borrow must preserve the identity used by equality, ordering and hashing.
`KeyView<Q>.key_view()` has the same coherence requirement for borrowed-key
lookup: equal stored/query keys compare and hash identically under Q.
It allocates and retains nothing. A type has at most one KeyView for a given Q.
Identity views simply reborrow; they never move the backing value.
The selected identity/reborrow implementations are native facilities, not a
general automatic conversion search.

`core.borrow.OwnedType` has associated `Owned: Borrow<Self>`; the relation
identifies an owned representation without promising to construct it from a
read. `core.borrow.ToOwned` refines that relation with copying.
Concrete ownership projections select the declaring protocol:
`B.(OwnedType).Owned`.
`to_owned()` reads the view and constructs that owner; `clone_into(mut Owned)`
updates an existing owner with equivalent content and may reuse capacity.
Clone types use Clone; Text produces String; slices produce List with cloned
elements. Slice ownership identity does not require Clone; copying its elements
does. Implementations declare storage identity separately from copying, including
user-defined borrowed types with distinct owners. This is the owner-approved
D31 source migration, not an implicit conversion or a compiler-derived owner.
`ToString` is allocation-backed Display rendering, as specified by
library-and-abi section 3. None of these protocols permits an implicit retain
on ordinary assignment.

### 2.4. Hashing and error objects

`Hash.hash<H: Hasher>(state: mut H): Unit` reads its value and feeds identity
into H. Equal values must feed equal input for the same hasher.
Representations of distinguishable sequences must be prefix-separated:
concatenating component encodings must not confuse different component
boundaries. `hash_slice(read [Self], mut H)` hashes the ordered element
sequence; it need not equal repeated calls to an implementation's scalar
hash if the implementation uses a compatible bulk encoding.
The standard slice Hash additionally identifies the sequence length.
Text hashes its content with a boundary separator, not its pointer.
Owners hash/compare payloads unless their operation explicitly requests
pointer identity. Hashing an address is not a stable persistence format.

`Hasher.write(read [u8])` updates mutable state. `finish(): u64` reads a
digest without resetting the state. `write_uN/write_iN/write_usize/write_isize`
feed the declared integer; no cross-implementation equivalence to a particular
number of write calls is promised. A hasher implementation must document any
portable byte encoding it additionally promises. `BuildHasher` associates
one Hasher type; `build_hasher` constructs state such that repeated builds
from the same builder hash identical streams identically.
`BuildHasher.hash_one<T: Hash>(read T)` hashes one value with fresh state.
`BuildHasherDefault<H: Hasher + Default>` stores no H state and constructs
H's default. General Hash output, seeds and algorithm are not fixed across
library revisions or targets, and are not cryptographic guarantees.

`core.error.Error: Debug + Display` lends an optional source error from its
own region. The default source is absent. Traversing sources does not allocate,
retain or capture a backtrace. An implementation returning cycles can make
unbounded traversal fail to terminate; a consumer may not assume acyclicity
for memory safety. Erased error `is<T: Error + Static>`,
`downcast_ref<T>` and `downcast_mut<T>` compare concrete type identity and
return a properly borrowed T only on exact identity; failure returns none.
Allocating/downcasting an owning erased error transfers the owner on success
and returns the original owner on failure. Experimental provider/request
interfaces are outside this contract.

## 3. Scalar operations

### 3.1. Integers

For each native signed/unsigned width, let N be its bit width and R its
representable mathematical range. `BITS = N: u32`; MIN/MAX are exactly the
endpoints of R with the owning integer type. `usize/isize` use the target
pointer width, never the build host width.
[Ordinary operators](semantic-rules.md#3-scalars-and-arithmetic) and
[numeric casts](specification-annex.md#1-numeric-operations-and-constant-evaluation)
retain their existing contracts.

The following families are defined mathematically, at every eligible width:

| Members | Result and exceptional inputs |
| --- | --- |
| `checked_add/sub/mul/neg/abs/pow`, mixed signed/unsigned add/sub | Optional mathematical result, absent exactly when outside destination R |
| `strict_add/sub/mul/neg/abs/pow`, mixed add/sub | Mathematical result; panic on overflow in every runtime profile |
| `wrapping_add/sub/mul/neg/abs/pow`, mixed add/sub | Mathematical result modulo 2^N, interpreted in destination signedness |
| `overflowing_add/sub/mul/neg/abs/pow`, mixed add/sub | Wrapping result and bool indicating mathematical overflow |
| `saturating_add/sub/mul/neg/abs/pow`, mixed add/sub | Clamp mathematical result to destination R |
| `checked_div/rem`, `_euclid` | None for zero divisor or signed MIN / -1, including its remainder |
| `strict_div/rem`, `_euclid` | Panic for either invalid condition |
| `wrapping_div/rem`, `_euclid` | Panic for zero divisor; signed MIN / -1 yields MIN quotient or zero remainder |
| `overflowing_div/rem`, `_euclid` | Same result as wrapping forms; overflow flag only for signed MIN / -1; zero still panics |
| `saturating_div` | Zero panics; signed MIN / -1 gives MAX; otherwise ordinary quotient |
| `checked_shl/shr` | None for count >= N; otherwise bit shift, not a mathematical multiplication overflow check |
| `strict_shl/shr` | Panic for count >= N, otherwise that bit shift |
| `wrapping_shl/shr` | Use count modulo N |
| `overflowing_shl/shr` | Wrapping shift plus flag for count >= N |
| `unbounded_shl/shr` | Shift all bits out for count >= N: zero, except signed right shift yields -1 for a negative input |
| `unchecked_add/sub/mul/neg` | Unsafe: exact mathematical result must fit R |
| `unchecked_shl/shr` | Unsafe: count must be < N |

`div_euclid/rem_euclid` satisfy `a = q*b + r`, `0 <= r < abs(b)`;
ordinary division truncates toward zero and ordinary remainder has the
dividend's sign. Ordinary `_euclid`, `abs` and `pow` follow the applicable
checked/profile overflow policy. `unsigned_abs` returns exact magnitude in the
corresponding unsigned width, including signed MIN.
`abs_diff` returns the exact unsigned distance without intermediate overflow.
`signum` returns -1, 0, or 1; `is_positive/is_negative` use strict comparisons.
`cast_signed/cast_unsigned` reinterpret the same-width integer bits.
`checked_signed_diff` returns the signed difference only when it fits.

`count_ones/zeros`, leading/trailing ones/zeros inspect all N bits and return
u32; zero has N leading/trailing zeros. `lowest_one/highest_one` return the
least/most significant set-bit index or none on zero, including signed bit
patterns. `isolate_lowest_one/isolate_highest_one` retain only that bit, or
return zero. `bit_width` is zero on zero, otherwise highest set index + 1.
`reverse_bits` reverses all N bits. `rotate_left/right` rotate by count modulo
N. `swap_bytes` reverses byte order. Endian scalar/byte conversions are exact
bit permutations; byte arrays have N/8 elements and `ne` uses target endian.

`is_power_of_two` is true exactly for a positive single-bit value.
`next_power_of_two` gives the least power >= input, with zero mapping to one;
overflow follows its ordinary profile policy, and the checked form returns
none. `next_multiple_of(b)` is the least mathematical multiple >= self;
zero b panics, overflow follows ordinary policy; its checked form returns none
for zero or overflow. `is_multiple_of(0)` is true only for zero.
`div_ceil` rounds a nonnegative quotient upward and panics on zero divisor.
`midpoint` computes the mathematical average without overflow, rounding toward
zero for signed integers and down for unsigned integers.
`isqrt` returns floor(sqrt(self)); negative signed input panics and its checked
form returns none. `ilog(base)` returns floor(log_base(self)) and panics for
self <= 0 or base < 2; checked forms return none. `_ilog2/_ilog10` fix the base.
Carry/borrow arithmetic treats unsigned values as base-2^N digits:
`carrying_add(b, carry: bool)` computes a+b+carry and returns (low, carry-out);
`borrowing_sub(b, borrow: bool)` computes a-b-borrow and returns
(low, borrow-out). `carrying_mul(b, carry)` and
`carrying_mul_add(b, carry, add)` return (low, high) of the exact double-width
product plus the supplied digit additions. They never overflow internally.
Bit operations are O(1); exponentiation, integer logarithm and square root
require at most O(N + log exponent) word operations with constant storage.

`from_str_radix(read Text, radix)` accepts radix 2..36, optional leading +,
and leading - only for signed types. At least one digit is required; digits
are ASCII 0..9/a..z/A..Z with value < radix. Whitespace, separators and prefixes
are not skipped. Bad radix panics; bad input returns ParseIntError with kind
Empty, InvalidDigit, PosOverflow, NegOverflow, or Zero where a nonzero target
requires it. Decimal FromStr uses radix ten. Parsing is O(input bytes).

`Wrapping<T>` delegates arithmetic to wrapping operations and bitwise
operations to T. `Saturating<T>` delegates arithmetic to saturating operations;
neither wrapper makes division by zero valid. Wrapper equality/order/hash
inspect the inner value. `NonZero<Int>` contains exactly a nonzero integer:
`new` returns optional, `new_unchecked` requires nonzero, `get` returns the
integer. Nonzero arithmetic and checked/saturating forms use the corresponding
integer operation while preserving nonzero validity. Bitwise OR of a NonZero
operand preserves nonzero. A signed nonzero MIN is the signed integer MIN,
unsigned nonzero MIN is one, and MAX is the underlying integer MAX.
For unsigned NonZero, checked_add takes an ordinary unsigned integer;
checked_mul takes another NonZero and checked_pow takes a u32 exponent.
They return none on overflow. Saturating counterparts clamp to MAX.
checked_next_power_of_two returns none on overflow. Unsigned div_ceil,
midpoint and isqrt return NonZero with the underlying integer's mathematical
result; those positive inputs cannot produce zero.
For signed NonZero, abs/neg and their checked/wrapping/overflowing/saturating
forms apply the underlying signed operation; signed MIN is their only
absolute-value/negation overflow. unsigned_abs returns the exact unsigned
NonZero magnitude. cast_signed/cast_unsigned preserve bits and nonzeroness.
leading_zeros/trailing_zeros, lowest_one/highest_one and ilog2/ilog10 return
u32 (not optional), as a nonzero operand always has a set bit; signed
logarithms still require a positive operand. count_ones and unsigned
bit_width return NonZero<u32>. isolate_lowest_one/isolate_highest_one
return the owning NonZero type. is_power_of_two and signed sign queries
have the underlying integer semantics. Radix parsing additionally rejects
zero with ParseIntError kind Zero. These are width-parametric contracts,
not implementations for arbitrary non-integer generic T.

### 3.2. Bool, char and ASCII

Bool supports not/and/or/xor, comparisons and explicit integer conversion.
`then_some(take T)` returns present(T) on true and destroys T on false.
`then(make: take fn(): T)` calls make only on true. Bool `ok_or`/`ok_or_else`
return success(Unit) on true, otherwise the supplied/generated error.
No truthiness conversion is introduced.

Char is a Unicode scalar: 0..10FFFF excluding D800..DFFF. `MIN` is NUL;
`MAX` is 10FFFF; `REPLACEMENT_CHARACTER` is FFFD; maximum UTF-8/UTF-16 lengths
are four bytes/two units. `from_u32` returns none for a nonscalar;
`from_u32_unchecked` is unsafe with exactly that scalar-validity precondition.
Checked integer/char conversion returns the declared conversion error when
invalid. `FromStr<char>` accepts exactly one scalar and rejects empty/multiple
scalar text. `len_utf8/len_utf16` return encoded lengths.
`encode_utf8(mut [u8])` / `encode_utf16(mut [u16])` write the minimal encoding,
return the initialized prefix borrowed from that buffer, and panic when the
buffer is too short. No normalization is performed.

ASCII predicates recognize their named ASCII sets. Whitespace is
09, 0A, 0C, 0D, 20, excluding vertical tab; control is 00..1F and 7F;
graphic is 21..7E. ASCII case conversion changes only A..Z/a..z;
make-case variants mutate in place. `eq_ignore_ascii_case` compares after
that conversion, leaving non-ASCII values unchanged.
`from_digit(d, radix)` accepts radix <= 36 and returns none when d >= radix;
radix > 36 panics. `to_digit/is_digit` accept radix 2..36 (bad radix panics),
recognize only ASCII alphanumeric digits and return optional value/bool.

Unicode character properties and case mapping use Unicode 17.0.0:
`UNICODE_VERSION = (17u8, 0u8, 0u8)`. Primary data definitions are the Unicode
Character Database of that version: Alphabetic, Lowercase, Uppercase,
White_Space and general categories Cc and Nd/Nl/No. `is_control` tests Cc;
`is_numeric` tests Nd/Nl/No; `is_alphanumeric` is Alphabetic or numeric.
`is_cased/is_case_ignorable` use the corresponding derived properties.
This identifies actual sets, not locale-dependent C library predicates.
Scalar `to_lowercase/to_uppercase` yield the complete unconditional Unicode
mapping, possibly multiple scalars, without allocating. Text lowercase also
uses the Unicode final-sigma contextual rule; uppercase uses full mappings.
No locale tailoring, normalization or grapheme segmentation is implied.

`decode_utf16` consumes u16 items and yields an outcome per scalar. A valid
surrogate pair produces one supplementary scalar; an unpaired surrogate
produces DecodeUtf16Error carrying that unit without consuming an unrelated
following unit. `escape_unicode` emits `\u{lowercase-hex}` with no redundant
leading zero. `escape_default` uses `\t`, `\r`, `\n`, `\\`, `\'`,
`\"`, printable ASCII unchanged, and Unicode escapes otherwise.
`escape_debug` uses those short escapes plus `\0` for NUL. After quote/
backslash/short-escape handling, ASCII 20..7E and U+FF9E/U+FF9F remain literal.
Other scalars are Unicode-escaped when they have category Cc, Co or Cf,
White_Space, Grapheme_Extend, Default_Ignorable_Code_Point, or are unassigned
in Unicode 17.0.0; remaining scalars are literal. The standalone char escape
escapes both quote kinds. Text escape_debug applies this rule to its first
scalar but does not escape later scalars solely for Grapheme_Extend.
Character Debug surrounds the result with single quotes and does not escape
a double quote solely for quoting; Text Debug surrounds with double quotes
and applies the per-scalar rule, including Grapheme_Extend at every position,
without escaping a single quote solely for quoting.
ASCII byte escaping emits printable ASCII, short escapes for tab/CR/LF/
quotes/backslash and `\xhh` otherwise. Escape iterators own scalar/byte state,
are finite and fused, and add no allocation.

### 3.3. Floating helpers

Binary32/binary64 arithmetic, conversions, strict rounding and NaN arithmetic
are owned by [the numeric annex](specification-annex.md#1-numeric-operations-and-constant-evaluation).
Classification returns Zero, Subnormal, Normal, Infinite or Nan based on the
bits. `is_finite/is_infinite/is_nan/is_normal/is_subnormal` test those classes;
sign predicates inspect the sign bit including zeros and NaNs.
`abs` clears the sign bit; `copysign` selects the magnitude bits of self and
the sign bit of its argument. `signum` returns a NaN for NaN, otherwise +1/-1
according to the sign bit, including zero.
`recip` computes 1/self. Degrees/radians multiply by the corresponding
conversion factor; this is rounded floating arithmetic, not exact symbolic pi.

`min/max` ignore a sole NaN and produce NaN when both are NaN; equal inputs,
including opposite-signed zeros, may select either representation.
`clamp(low, high)` panics for a NaN bound or low > high, preserves a NaN
receiver, otherwise clamps numerically. A zero result may select either input
zero sign when several are available.
`midpoint` computes the average without avoidable finite overflow; NaN inputs
or opposite infinities give NaN. `next_up/next_down` select the adjacent
representable number in the named direction. Either zero steps upward to
the smallest positive subnormal, downward to the negative counterpart.
The inward step from the smallest-magnitude nonzero has the corresponding
signed zero. Outward infinity stays infinity; inward infinity gives the
largest finite value with that sign; NaN remains NaN.

`total_cmp` compares the complete IEEE totalOrder key: negative NaNs, negative
infinity, negative finite values, negative zero, positive zero, positive finite
values, positive infinity, positive NaNs. Negative NaN representation order
reverses the positive order; on the positive side signaling precedes quiet
and payload bits order numerically. It is not float PartialEq, which equates
the two zeros and never equates NaNs.
`to_bits/from_bits` and endian-byte conversions preserve every supplied bit.
The unsafe float-to-integer operation and decimal parser are specified in
library-and-abi section 3.
The decimal parser accepts an optional sign followed by either decimal digits
with an optional dot/fraction, or a dot followed by at least one decimal
digit; an optional e/E exponent has an optional sign and at least one digit.
At least one significand digit is required. The entire input must match:
no surrounding whitespace, digit separators, hexadecimal notation or radix
prefixes. Case-insensitive inf, infinity and nan with an optional sign are
the additional nonfinite spellings. Finite decimal input is rounded directly
to the requested binary width, ties to even; overflow/underflow gives signed
infinity/zero. Invalid syntax returns ParseFloatError. Parsing is O(input
bytes), with no allocator/OS requirement, and does not capture diagnostics
or a stack trace in that error.

For precision p and exponent limits emin/emax (binary32: 24,-126,127;
binary64: 53,-1022,1023), RADIX is 2u32, MANTISSA_DIGITS is p as u32,
EPSILON is 2^(1-p), MIN_POSITIVE is 2^emin, MAX is
(2-2^(1-p))*2^emax, MIN is -MAX. DIGITS is 6/15u32;
MIN_EXP is -125/-1021i32, MAX_EXP 128/1024i32;
MIN_10_EXP is -37/-307i32, MAX_10_EXP 38/308i32.
INFINITY/NEG_INFINITY are the signed infinities and NAN is a quiet NaN
without a selected payload. Module `consts` values are the nearest owning-width representations of these
mathematical expressions, without host-precision intermediates:

| Constants | Exact mathematical value |
| --- | --- |
| `PI`, `TAU`, `E` | pi, 2*pi, exp(1) |
| `FRAC_PI_2/3/4/6/8` | pi divided by the named denominator |
| `FRAC_1_PI`, `FRAC_2_PI`, `FRAC_2_SQRT_PI` | 1/pi, 2/pi, 2/sqrt(pi) |
| `SQRT_2`, `FRAC_1_SQRT_2` | sqrt(2), 1/sqrt(2) |
| `LN_2`, `LN_10` | Natural logarithm of 2 or 10 |
| `LOG2_10`, `LOG2_E`, `LOG10_2`, `LOG10_E` | Logarithm in the named base of the named argument |
| `GOLDEN_RATIO` | (1+sqrt(5))/2 |
| `EULER_GAMMA` | Limit of (sum of 1/k for k=1..n) - ln(n) |
`algebraic_add/sub/mul/div/rem` permit the algebraic relaxations identified by
their explicit operation, including reassociation and altered NaN/zero results;
ordinary operators remain strict. A strict implementation is permitted.
No additional hosted transcendental methods are implied by this core group.

## 4. Text and byte views

Text is validated UTF-8 with byte length, no terminator requirement, and a
region-bearing view. `len/is_empty/as_bytes/as_ptr` inspect its existing
storage. `is_char_boundary(i)` accepts zero, byte length, and scalar starts
inside the view, rejecting out-of-range values. `floor_char_boundary(i)`
clamps to length then searches down to a boundary; `ceil_char_boundary(i)`
returns length for i >= length and otherwise searches up. These searches
inspect at most one scalar's encoding.

`from_utf8(read [u8])` validates and returns a borrowed Text or Utf8Error.
`from_utf8_mut` requires exclusive bytes and returns exclusive Text.
The error's `valid_up_to` is the valid prefix byte count;
`error_len` is none for an incomplete final scalar or the malformed sequence
length (one to three) otherwise. Validation is O(bytes).
Unsafe `_unchecked` forms require valid UTF-8 for the entire supplied extent.
Unsafe `as_bytes_mut` lends bytes exclusively; callers must restore valid
UTF-8 before that loan ends or Text is observed. Raw pointer access conveys
no permission to change validated storage through a live read view.

`get/get_mut(range)` return none for invalid/reversed/out-of-bounds ranges or
non-boundary endpoints; IndexRange and `split_at[_mut]` panic instead.
Checked split returns none on the same error; valid splits lend disjoint
prefix/suffix views. Unsafe unchecked slicing/splitting requires ordered,
in-range boundary endpoints. Empty ranges are valid only at valid boundaries.
No text integer Index returning a char is provided.
`substr_range(read Text)` locates the argument by address/byte extent, not
content search, returning a half-open byte range or none. Zero-length
arguments from another allocation may give a false positive at an endpoint;
this is not an allocation-provenance proof.

### 4.1. Search and splitting

Pattern P is a sealed native capability with these eligible shapes:
char, a borrowed slice/array of chars meaning any member, borrowed Text
meaning an exact substring, and a `mut fn(char): bool` predicate.
Matching never splits a scalar. Text patterns use byte equality; char-set
and predicate patterns inspect scalars. Predicates take scalar values, not
mutable text. Forward/reverse capability is separate; double-ended iteration
requires that alternating ends agrees on the same nonoverlapping matches.
Char, set and scalar-predicate patterns support that agreement; arbitrary
substring patterns do not acquire it automatically.

`find/rfind` return the first/last match's byte start, or none.
`contains`, `starts_with`, `ends_with`, `strip_prefix/strip_suffix` test the
named position and return bool or an optional remaining borrowed view.
`split_once/rsplit_once` return borrowed text before and after the
first/last match, omitting it. No match returns none. Search uses O(h*p + h)
worst-case work for h haystack bytes and p pattern bytes; char predicates are
O(scalar visits), char-set matching O(visits * set length). Implementations
may improve these bounds without changing callback semantics.
`strip_circumfix(prefix,suffix)` removes exactly one matching prefix and one
matching suffix only when both exist and do not overlap, returning optional
remaining Text. It does not repeatedly trim or accept overlapping matches.

`matches/rmatches` yield nonoverlapping matched views in the requested
direction; `_indices` additionally yields byte starts. A zero-length substring
matches at each scalar boundary, including the two ends, and iteration still
progresses. Overlapping substring matches are not yielded.
`split/rsplit` yield the fields between those matches, including empty fields
at leading, adjacent or trailing separators. Splitting empty text by a
nonempty pattern yields one empty field. Splitting by empty text includes
empty end fields and one field per scalar.
`splitn/rsplitn(n)` yield at most n fields: zero gives none; one gives the
entire input; the last field is the unsplit remainder.
`split_terminator/rsplit_terminator` suppress the single final empty field of
the forward decomposition. `split_inclusive` attaches the matched separator
to its preceding field and does not add a trailing empty field.
Every iterator preserves the original region and is allocation-free.

`trim_start_matches/trim_end_matches` repeatedly remove matching edge
segments; `trim_matches` requires double-ended matching. Empty matches cannot
cause an infinite removal loop. `trim/trim_start/trim_end` use Unicode
White_Space. `trim_ascii*` uses the ASCII whitespace set in section 3.2.
`split_whitespace` and `split_ascii_whitespace` discard whitespace runs and
never yield empty fields. `lines` splits at LF or CRLF and excludes those
terminators; a lone CR remains content. Empty input yields no lines and a
final terminator adds no extra line.

`chars` yields scalars; `char_indices` yields (byte offset, scalar);
`bytes` yields u8 values; `encode_utf16` yields encoding units without a BOM.
Forward/reverse char and byte traversal do not revisit consumed elements.
`Chars.as_str`/`CharIndices.as_str` lend the not-yet-consumed contiguous text;
CharIndices offset denotes the next forward scalar start, or original length
at forward exhaustion. Byte iteration is exact-size, bidirectional and fused;
char iteration has valid size bounds but not an exact byte-derived scalar
count. Escaping traverses scalars under section 3.2. Text comparison, ASCII
tests and ASCII case operations do not allocate; conversion to owned case-
mapped text is an alloc operation.

## 5. Slices and arrays

`[T]` carries element count and valid contiguous T storage; `[T; N]` adds
const N. `len/is_empty` are O(1). `as_ptr/as_mut_ptr` lend raw addresses,
not ownership; `_ptr_range` gives start and one-past pointers. Pointer
invalidation follows the backing owner. All element projections preserve
the slice's region and access mode.

| Members | Contract |
| --- | --- |
| `get/get_mut(i or range)` | Optional element/subslice view; no bounds panic |
| index/IndexRange | Same projection, panic if invalid |
| `get_unchecked[_mut]` | Unsafe: selected index/range must be valid even if the result is never used |
| `first/last`, `_mut` | Optional first/last element; none on empty |
| `split_first/split_last`, `_mut` | Optional endpoint plus remainder, disjoint for exclusive views |
| `split_at[_mut]` | Prefix/suffix at i <= len, panic otherwise |
| `split_at[_mut]_checked` | Optional pair, none rather than panic |
| unchecked split | Unsafe: i <= len |
| `first_chunk/last_chunk<N>`, `_mut` | Optional fixed array view; none if len < N |
| `split_first_chunk/split_last_chunk<N>`, `_mut` | Chunk plus remainder; none if too short |
| `as_array<N>/as_mut_array<N>` | Optional array view exactly when len == N |
| `as_chunks<N>` | Complete `[T; N]` prefix plus residual suffix |
| `as_rchunks<N>` | Residual prefix plus complete `[T; N]` suffix |
| `as_chunks_unchecked<N>`, `_mut` | Unsafe: N != 0 and length divisible by N |
| `as_flattened`, `_mut` on `[[T; N]]` | Contiguous T view of product length; panic if product overflows usize for zero-sized T |

Checked chunk grouping panics for N == 0 even on empty input. Zero-length
endpoint chunks are otherwise valid. Inclusive range end conversion must
not wrap when the end is usize::MAX. An invalid/reversed range returns none
or panics according to the selected API, never a forged oversized view.
Fixed-array projections, checked/unchecked chunk grouping and mutable pointer
ranges are const-callable on live storage. Their const forms preserve the same
aliasing, bounds, zero-size and unsafe preconditions; evaluation cannot export
a view of local storage.

`element_offset(read T)` locates an element by pointer address, not value,
and returns its index only for an in-range aligned element start.
`subslice_range(read [T])` returns the argument's contained aligned interval,
or none. Both panic for zero-sized T; empty subslices may give endpoint
false positives across allocations, so neither query establishes provenance.
`strip_circumfix` removes a matching element prefix and suffix once, only
when nonoverlapping, and lends the remaining interval.

The split-off-view helpers mutate a stored slice view, not its backing owner:
on a valid one-sided RangeTo/RangeToInclusive they return the selected prefix
and replace the stored view with the suffix; on RangeFrom they return the
selected suffix and retain the prefix. Invalid bounds return none without
changing the stored view. `split_off_first/last` similarly return an optional
endpoint and retain the remainder. Mutable variants partition the original
exclusive region into disjoint returned/remaining views; they do not lend
the whole region twice or shorten the returned view to the temporary
container holding the view.
These are core.slice functions on mutable view-holder slots, including slice
views lent by List; they do not split or shorten the List owner.

`get_disjoint_mut<I, const N>(indices: [I; N])` supports homogeneous usize,
half-open ranges or inclusive ranges. It validates every range and pairwise
overlap before lending any output, then returns an array of exclusive views
or GetDisjointMutError (out of bounds or overlapping indices).
For this check, an empty range overlaps another range only when strictly
inside it, not at either endpoint. Duplicate element indices overlap.
Work is O(N^2), output/storage O(N). The unchecked variant requires all
indices in range and mutually nonoverlapping, even if outputs are unused.

### 5.1. Iteration and subdivision

Slice `iter/iter_mut` traverse each element in index order; mutable iteration
lends distinct elements with the original exclusive region, so several yielded
views may coexist without aliasing. Both are exact-size, bidirectional and
fused. `into_slice/as_slice` on iterators expose only the remaining extent;
exclusive conversions consume the iterator where needed to prevent competing
mutable access.

`windows(k)` yields all overlapping k-element read views, one index apart;
`array_windows<N>` yields fixed-array views. Zero window size panics.
No ordinary mutable overlapping-windows iterator exists.
`chunks/chunks_mut(k)` partition from the front with a possible short final
chunk. `rchunks/rchunks_mut` partition from the back with a possible short
first chunk in the original sequence. Exact variants omit the short chunk
and expose it through `remainder/into_remainder`, preserving access mode.
Zero chunk size panics. These iterators are exact-size, bidirectional and
fused; alternating ends yields each chunk once.

`split/rsplit` use `mut fn(read T): bool` on separators and omit separator
elements, including empty fields at ends/adjacent matches.
`split_inclusive` retains separators on the preceding segment.
Mutable variants lend nonoverlapping exclusive segments; their predicates
still read separator elements. Limited splits yield at most n segments with
the last the remainder. `chunk_by/chunk_by_mut` call
`mut fn(read T, read T): bool` on adjacent original elements; true joins a
run, false starts a new one. Empty input yields no runs.
Each visits O(n) elements overall and uses constant iterator state.

### 5.2. Movement, initialization, search and order

`swap(i,j)` panics unless both indices are valid and exchanges initialized
values without dropping them. `reverse` reverses elements in place.
`rotate_left/right(k)` requires k <= len, panicking otherwise, and permutes
cyclically in O(n) work and O(1) element storage. Zero/len is a no-op.
`swap_with_slice` requires equal lengths and exclusive disjoint input views.
`copy_from_slice` requires equal length and T: Copy; `clone_from_slice`
requires T: Clone and may leave an initialized modified prefix if cloning
panics. Length mismatch panics before copying/cloning.
`copy_within(range, dest)` requires T: Copy and valid source/destination
extents, allows overlap with memmove behavior and panics on invalid bounds.
`fill(take value)` clones as needed for T: Clone; `fill_with` repeatedly
calls `mut fn(): T`. Replaced elements are destroyed exactly once.
These operations are O(elements touched), including destruction separately.
Unsafe `align_to<U>/align_to_mut<U>` split into a T prefix, maximally sized
properly aligned U middle, and T suffix, covering the original byte extent.
If either type is zero-sized, the original slice is returned unsplit.
Every middle U must be valid/initialized with compatible reference regions
and ownership interpretation, as for transmute; exclusive conversion must
also leave storage valid for its subsequent T interpretation before that
interpretation is used again. It cannot observe padding as initialized U.
This is not a checked parser for arbitrary byte encodings.
`write_copy_of_slice` on `[MaybeUninit<T>]`, T: Copy, requires a destination
at least as long as the input (panic otherwise), copies into its prefix
and returns that prefix as initialized exclusive [T]. It does not drop
old initialized payloads hidden inside MaybeUninit or initialize the suffix.

`utf8_chunks` on bytes yields successive chunks containing a maximal valid
UTF-8 prefix and its next malformed subsequence; `valid` lends Text and
`invalid` lends its zero-to-three invalid bytes. It uses the same malformed/
incomplete grouping as Utf8Error, covers every input byte in order, and
never substitutes replacement bytes itself. The iterator is fused and
allocation-free; the final all-valid chunk has an empty invalid part.

`contains(read T)`, prefix/suffix tests and stripping compare corresponding
elements under PartialEq; they never clone.
`binary_search` requires a sorted ascending slice and returns
success(index of an equal item) or failure(insertion index).
`binary_search_by` uses `mut fn(read T): Ordering` comparing each probed
element to the sought value; `_by_key` uses
`mut fn(read T): K`, `K: Ord`. Duplicates may select any matching index.
`partition_point` returns the length of the initial true partition under
`mut fn(read T): bool`. An unsorted/nonpartitioned input gives an unspecified
index/result without invalid memory access. Search takes O(log(n+1)) probes.
`is_sorted`, `_by`, `_by_key` check successive elements, true for length <= 1;
the by predicate takes two read elements and returns bool for <=.

`sort_unstable[_by/_by_key]` gives ascending order without equal-element
stability, no allocation and O(n log(n+1)) worst-case comparisons.
By comparison is `mut fn(read T, read T): Ordering`; by-key is
`mut fn(read T): K` with K: Ord. `select_nth_unstable[_by/_by_key](i)`
panics unless i < len, partitions around the correctly ranked element, and
returns disjoint exclusive (prefix, element, suffix). Every prefix value is
<= the element and every suffix value >= it, without sorting either side;
work is O(n), allocation zero. Comparator/key panic preserves every original
element in initialized slice storage, with mutation performed through interior
mutability retained; order need not be restored. Inconsistent ordering may
panic or produce an unspecified order, never memory unsafety.
Stable allocating sorting is an alloc operation.

Array `from_ref/from_mut` makes length-one views; slice equivalents make
one-element slices. `from_fn<T, const N>(f: mut fn(usize): T)` calls ascending
indices, constructs one T per slot, and cleans the initialized prefix on panic.
`array.repeat<T: Clone, N>(take value)` and `[value; N]` retain their declared
duplication rules; the function clones to build the array and handles N == 0
without reading an element. `array.map<U>(take self, f: mut fn(take T): U)`
consumes in index order; on panic it drops remaining inputs and constructed
outputs. `each_ref/each_mut` returns an array of borrowed element views.
Consuming array iteration moves each element exactly once, is exact-size,
bidirectional and fused, and drops remaining elements on iterator destruction.
Checked slice-to-array conversion tests length; borrowed conversion lends,
owned conversion requires the declared Copy/Clone bound or returns the
original owner on length failure. No implicit per-element duplication occurs.

## 6. Iterator protocols and constructors

`Iterator` associates `Item`; `next(receiver: mut Self): Item?` transfers one
item or returns none. None alone does not promise permanent exhaustion.
`size_hint(): (usize, usize?)` bounds the remaining number of yielded items;
the upper bound is none if unknown/unrepresentable. Bounds must be sound but
are not an unsafe proof that uninitialized slots may be read.
`ExactSizeIterator.len()` equals the remaining count representable in usize;
its default is_empty tests zero. `FusedIterator` promises permanent exhaustion.
`BidirectionalIterator.next_back()` draws from the same remaining sequence
as next without duplicates or crossing ends. `nth_back` discards n from that
end before returning the next. `rfold/try_rfold/rfind` apply the forward
algorithm below in reverse traversal.

The separately named optional and outcome Iter/IterMut/IntoIter types are
zero-or-one iterators. Optional Iter/IterMut lend the present T; outcome
Iter/IterMut lend successful T and yield nothing for failure.
IntoIter owns the consumed alternative, moves present/success T once, and
outcome-to-IntoIter conversion destroys a failure E immediately while creating
an empty iterator; no E is retained for lazy destruction. All are exact-size, bidirectional and
fused; front/back calls share the one slot, never both yielding it.
Dropping a partly consumed owned iterator destroys its remaining T.
Borrowed Iter cloning duplicates a read view, owned IntoIter cloning needs
T: Clone, and IterMut does not gain Clone through an exclusive reference.
Other inherited methods use sections 6..8 with these Item/access bounds;
this is not a new optional/outcome value method contract.

`OwnedIterable` consumes the source into an iterator with an owned Item.
Arrays consume into allocation-free `ArrayIntoIter<T, N>` with inline storage.
Front/back calls share the initialized remaining range; moving the iterator
does not retain pointers into its former storage. It is exact-size and fused.
Destruction advances ownership before dropping each remaining element and
continues cleanup if one destructor panics, subject to the double-panic policy.
`Iterable` reads and `MutableIterable` exclusively borrows, with yielded
views tied to that loan. Iterators themselves can implement OwnedIterable
by identity. `by_ref()` lends the iterator exclusively so consuming adapter
operations can consume that view while leaving the underlying state available
when the loan ends. Trait/interface bounds on every adapter are conjunctive:
an adapter is not exact-size, bidirectional, cloneable or fused just because
its input has some different property.

| Constructors | Sequence and callback |
| --- | --- |
| `empty<T>()` | Empty, exact-size, fused, bidirectional |
| `once(take T)` | One owned item; same properties |
| `once_with(make: take fn(): T)` | Call only on first demand, at most once |
| `repeat<T: Clone>(take T)` | Infinite sequence of explicit clones |
| `repeat_n<T: Clone>(take T, n)` | Exactly n items; may move the retained T for the last item; zero drops it without yielding |
| `repeat_with(make: mut fn(): T)` | Call once for each demanded item |
| `from_fn(next: mut fn(): T?)` | Delegate every demand; none need not be permanent |
| `successors(first: take T?, next: mut fn(read T): T?)` | Yield current and compute its successor; absence ends permanently |

Repeat clones the retained item, not the closure state. Adapters keep their
captured regions and input ownership. Construction does not advance inputs,
except where an API explicitly requests lookahead later.

## 7. Lazy adapters

Native adapter type names follow
[the vocabulary table](library-surface.md#9-vocabulary-and-the-experience-1-prelude).
Each row gives the constructor method, item access, and traversal rule.

| Method | Contract |
| --- | --- |
| `map<U>(f: mut fn(take Item): U)` | One callback per pulled item, yielding its result |
| `filter(test: mut fn(read Item): bool)` | Yield original items whose borrowed test is true; destroy rejected owned items |
| `filter_map<U>(f: mut fn(take Item): U?)` | Consume successive inputs until present result or source none |
| `inspect(f: mut fn(read Item): Unit)` | Observe each yielded item without changing ownership |
| `enumerate()` | Yield (usize index starting at zero, item); overflow follows integer profile policy |
| `zip(other: take U)` | Pair corresponding items; a step pulls left first then right only if left produced an item |
| `chain(other: take U)` | Drain left until its first none, then permanently use right |
| `rev()` | Exchange next and next_back on a bidirectional source |
| `take(n)` / native `limit(n)` | Yield at most n items; never demand another item after n have been produced |
| `skip(n)` | Discard the first n demanded source items, then delegate |
| `step_by(k)` | Panic on zero; yield positions 0,k,2k,...; discarded pulls may be performed eagerly or delayed between these outputs |
| `take_while(test: mut fn(read Item): bool)` | Stop permanently at first false, consuming/destroying that tested item |
| `skip_while(test: mut fn(read Item): bool)` | Discard initial true items; yield the first false item and then never test again |
| `map_while(f: mut fn(take Item): U?)` | Map until a callback returns none; behavior on subsequent demands is not fused unless wrapped in fuse |
| `scan(take state: S, f: mut fn(mut S, take Item): U?)` | Persist callback state; each demand processes an input; none need not be permanent |
| `flat_map(f: mut fn(take Item): U)` | U: OwnedIterable; drain each produced inner iterator before advancing outer |
| `flatten()` | As flat_map with identity on iterable items; optional/outcome items contribute zero or one success item |
| `cloned()` | For read-view items with T: Clone, yield explicit T clones |
| `copied()` | For read-view items with T: Copy, yield copied T values |
| `cycle()` | Requires Clone source; preserve a cloneable restart state and restart after exhaustion |
| `fuse()` | After first none, always none without pulling source again |
| `peekable()` | Cache one next result on first peek; repeated peek does not advance again |

Zip may consume and destroy an unmatched left item when right ends. On further
demands after none it may again advance left once and right only when left
yields; it need not fuse nonfused inputs. Reverse zip requires both inputs
bidirectional and exact-size and aligns the paired prefix, discarding
unpaired tails. Enumerate reverse traversal requires exact-size indexing.
Take/skip reverse traversal requires exact-size bidirectional inputs.
Filter/filter_map/inspect/map may traverse from either end when their inputs
can, invoking callbacks in the actual demand order.
Flatten/flat_map reverse traversal additionally requires bidirectional inners.
Rev requires only bidirectional input; cloned/copied preserve valid size
and bidirectionality. ExactSize is preserved by map/inspect/enumerate/rev/
cloned/copied/zip/take/skip where the necessary input exact-size bounds hold,
not by filters or flatten. Chaining can overflow combined lengths and does
not supply ExactSize solely from two ExactSize inputs.
Cycle of an empty fused input is empty, not a busy loop.

`peek/peek_mut` return views of the cached Item with the adapter's region;
peek_mut changes the cached item, not the source's backing owner unless Item
itself carries that authority. Peeking may invoke next and cause effects.
`next_if(test: take fn(read Item): bool)` consumes only if test succeeds;
`next_if_eq` compares to a borrowed expected value. A rejected cached item
remains available. `next_if_map`-style extensions are not implicitly covered.

Adapters take O(1) state per nesting level except captured payloads and active
inner iterators. Producing an output costs the number of source pulls and
callback invocations needed; filtering/flattening infinite inputs may never
produce a next result. Clone of an adapter clones its actual stored input/
callback/cache state only under those Clone bounds; creation does not clone it.
Dropping adapters drops all unyielded owned state, including active inner
iterators and peeked items, without running unselected callbacks.

## 8. Iterator consumers

Terminal whole-stream operations consume the iterator; `next/nth/find/
find_map/position/rposition/any/all/try_fold/try_for_each` instead require
exclusive receiver access and leave the unvisited suffix available.
Calling a consuming method on `by_ref()` consumes only the reborrow.
Short-circuit operations consume the decisive item; they do not put it back.

| Members | Result, evaluation and empty input |
| --- | --- |
| `count` | Number of yielded items; destroy items; usize overflow follows profile policy |
| `last` | Last owned Item, or none; destroy previous candidates |
| `nth(n)` | Discard n items then return next, or none |
| `fold<B>(take seed, f: mut fn(take B, take Item): B)` | Left fold; seed on empty |
| `reduce(f: mut fn(take Item, take Item): Item)` | First item as seed; none on empty |
| `for_each(f: mut fn(take Item): Unit)` | Consume each item in traversal order |
| `try_fold/try_for_each` | Same traversal, return first residual immediately, preserving its type |
| `any/all(test: mut fn(take Item): bool)` | Stop on true/false respectively; empty is false/true |
| `find(test: mut fn(read Item): bool)` | First original item passing test, or none |
| `find_map(f: mut fn(take Item): U?)` | First present mapped value, or none |
| `position/rposition(test: mut fn(take Item): bool)` | Position in the remaining input; reverse requires exact-size bidirectional input |
| `min/max`, `_by`, `_by_key` | Best owned item or none; first minimum, last maximum on equality |
| `cmp/partial_cmp/eq/ne/lt/le/gt/ge` | Lexicographic comparison to another owned iterable, stopping at first difference/incomparability or length difference |
| `is_sorted`, `_by`, `_by_key` | Adjacent ascending check, stop at first false, empty/singleton true |
| `unzip<A: Default + ExtendItems<X>, B: Default + ExtendItems<Y>>` | Consume pairs into independent destinations |
| `partition<B: Default + ExtendItems<Item>>(test: mut fn(read Item): bool)` | Visit inputs in order and extend the corresponding destination |
| `collect<C: FromItems<Item>>()` | Transfer all items to the selected C implementation |
| `sum<S: Sum<Item>>`, `product<P: Product<Item>>` | Delegate the selected protocol; numeric empty identities are zero and one |

Comparator/key modes for min/max match section 2. Iterator `is_sorted_by`
takes a bool-producing two-read-item predicate. A key may be computed more
than once unless a cached-key operation explicitly guarantees otherwise.
`rposition` reports forward indices, not distance from the back.
Lexicographic default comparison uses item interfaces; by-comparison variants
are covered only where separately selected as stable native members.
Consumption costs O(visited items); comparisons stop as soon as determined.
Collected/partitioned outputs retain their container allocation/cost rules.
Partitioned outputs also retain B's ordering and duplicate-handling semantics;
insertion-order-preserving destinations retain relative input order.

`FromItems<Item>.from_items<I: OwnedIterable<Item = Item>>(take I)` builds
an owning result; `ExtendItems<Item>.extend_items(take I)` requires mutable
destination. Neither clones input items. Optional collection produces none
at the first none, dropping the partially built output; outcome collection
returns the first failure without visiting the remaining source.
Successful items are collected through the target FromItems implementation.
The same sealed short-circuit dispatch supports optional, outcome,
ControlFlow and the selected Poll combinations, retaining the actual
residual alternative and payload ownership rather than converting errors.
Panic still unwinds rather than becoming a residual. Fallible consumers
leave their borrowed source after the decisive input; consuming collection
drops its owned remainder normally.

## 9. Raw pointers and storage

The [memory model](memory-and-concurrency.md#1-allocations-bytes-and-values)
is normative for every operation here. Unsafe preconditions are obligations
at the call, including zero-length calls where alignment/non-nullness is
required, not suggestions to be checked only if a result is dereferenced.
`ptr<T>` and `ptr<mut T>` are nonowning. `NonNull<T>` additionally excludes
null without proving dereferenceability, uniqueness, initialization or
thread transfer.

`null/null_mut` have zero address. `dangling/dangling_mut` and
`NonNull.dangling` supply a non-null appropriately aligned pointer without
allocated T storage. `NonNull.new` returns none on null; `new_unchecked`
requires non-null. `from_ref/from_mut` derive a pointer preserving provenance
and the source loan's access restrictions. Pointer `cast<U>` changes pointee
interpretation and eligible metadata without validating U; const/mut casts
do not grant write authority. `slice_from_raw_parts(p,n)` builds a raw slice
descriptor without borrowing or checking the region.

`addr` extracts address without exposing provenance; `with_addr/map_addr`
replace an address while preserving the original provenance.
`without_provenance` makes an address-only pointer, unusable to access ordinary
allocated storage. `expose_provenance` makes provenance eligible for the
explicit exposed-provenance recovery operation; recovery requires a matching
live allocation and valid access and never revives freed storage.
`eq` compares addresses and metadata; `addr_eq` compares only data addresses;
pointer hash corresponds to the selected equality. Function-address equality
is only an address comparison: code folding or multiple copies may make it
unsuitable as semantic function identity.

`offset/add/sub`, and byte variants, require a same-allocation in-bounds
traversal to the result or one-past, with signed byte displacement
representable in isize and no address wrap. Element arithmetic multiplies by
size_of(T); byte arithmetic moves bytes while preserving metadata.
Wrapping variants permit leaving the extent but cannot authorize a different
allocation; access requires returning to an eligible valid region.
`offset_from`/byte counterpart require pointers in the same live allocation
or equal pointers under the operation's equality exception, exact divisibility
by element size, and a representable signed difference. Element distance for
zero-sized T panics. Unsigned distance additionally requires self >= origin.
`align_offset(a)` panics unless a is a power of two, otherwise returns the
element offset needed for alignment or usize::MAX if no solution is supplied;
it does not certify allocation extent. `is_aligned` checks address only.
Slice raw `len/is_empty` inspect metadata without dereferencing.

Unsafe `as_ref/as_mut` return none on null, otherwise require valid initialized
T storage and a legal read/exclusive loan for the chosen output region.
Unchecked versions require non-null as well. NonNull equivalents have the
same obligations. Mutability of a raw pointer alone never proves exclusivity.
Raw array-view conversions check the metadata length where checked, but do
not themselves establish storage validity.

| Unsafe operation | Required storage and effect |
| --- | --- |
| `read` | Aligned readable valid T; bitwise transfer creates an owned T, so caller must not later double-use/drop a non-Copy source |
| `read_unaligned` | Same, but no alignment requirement |
| `write` | Aligned writable size_of(T) storage; initialize with transferred T without dropping old bytes |
| `write_unaligned` | Same except alignment |
| `replace` | Read-valid and write-valid T slot; transfer old T out and new T in without a destructor |
| `copy` | Readable/writable n*T bytes, aligned pointers, extent/size valid; overlap allowed; preserves byte initialization including padding |
| `copy_nonoverlapping` | Same with disjoint byte ranges |
| `swap` | Both valid writable T slots; overlap allowed under raw swap's byte semantics; no user drop |
| `swap_nonoverlapping` | Disjoint n-element valid regions, exchange their bytes |
| `write_bytes` | Writable n*T bytes, alignment and extent valid; repeat byte value, not automatic T validity |
| `drop_in_place` | Valid initialized T and exclusive destruction authority; run destruction once without freeing allocation |
| `read_volatile/write_volatile` | Read/write validity and alignment, or designated target MMIO region under its device rules; emit observable volatile access, not synchronization |

Pointer methods `copy_to/from`, `_nonoverlapping`, read/write/replace/swap/
drop delegate to these same effects and preconditions with receiver as the
corresponding source/destination. Byte-copy is O(byte extent), destruction
has T's cost, remaining single-slot operations are O(size_of(T)) at worst.
No operation implicitly fixes ownership after copying a non-Copy value.

`slice.from_raw_parts[_mut]` requires non-null aligned storage, one live
allocation covering all elements, initialized valid T, total byte size <=
isize::MAX with no wrap, and read/exclusive authority for the chosen region.
Empty slices and zero-sized elements still require non-null alignment.
The resulting slice cannot span two adjacent allocations. Unsafe text
construction additionally requires UTF-8.

### 9.1. Value layout and manual initialization

`size_of/align_of<T>` return target size/alignment; size includes padding and
is a multiple of alignment, alignment is a nonzero power of two.
`size_of_val/align_of_val` read a valid possibly-unsized view and include its
dynamic tail. Unsafe raw forms require valid metadata for that dynamic layout,
without requiring payload initialization where the layout itself permits it.
`offset_of` names the field path and returns its target byte offset; it is
not permission to form a reference to uninitialized or packed storage.
`needs_drop<T>` false proves destruction can be omitted; true is conservative.
`discriminant` reads the enum alternative into an opaque comparable/hashable
token without moving payloads or exposing its numeric layout.

`mem.drop(take T)` destroys T normally; `forget(take T)` suppresses its
destruction without extending any borrowed region or guaranteeing that a
library guard was released. `swap(mut T, mut T)` exchanges without dropping.
`replace(mut T, take T): T` installs new and returns old.
`take<T: Default>(mut T): T` constructs default before replacing; a default
panic leaves the original destination initialized.

`ManuallyDrop<T>` preserves T's layout/validity but suppresses automatic T
destruction. `new/into_inner` transfer T; shared/exclusive projections borrow
a still-initialized T. Unsafe `drop` requires a live initialized payload and
clears the caller's right to use/drop it again; unsafe `take` moves it out.
Moving a wrapper whose heap-owning payload has already been manually destroyed
is not a safe way to resurrect a valid value. Public safe projections cannot
be exposed after manually invalidating payload storage.

`MaybeUninit<T>` has T's size/alignment but permits uninitialized or invalid
T bits. `uninit`, `zeroed`, and `new(take T)` establish raw storage, zero
bytes (padding need not survive moves), or initialized T respectively.
Dropping it never drops T. `write(take T)` initializes/replaces bytes without
dropping an old T and returns an exclusive initialized T view.
Raw pointer projection does not form T references.
Unsafe `assume_init/assume_init_read/assume_init_ref/assume_init_mut/
assume_init_drop` require a completely initialized valid T and the ownership/
loan/destruction authority their result needs. Read duplicates bits without
consuming the wrapper; repeated ownership extraction must not duplicate
non-Copy resources. Partial arrays require separate initialized-count tracking.
Safe conversion from MaybeUninit to T is never inferred from all-zero bytes.

Unsafe `zeroed<T>` requires that all-zero bytes represent a valid T;
references, nonzero scalars and many enums fail this precondition.
`transmute<S,D>(take S)` requires equal sizes and a valid D with correct
regions/provenance/ownership; it transfers bits without dropping S.
Padding is not promised preserved as initialized data. `transmute_copy<S,D>`
reads bits from S, requires D no larger than S and valid D, and leaves S
owned by its caller; avoiding duplicated non-Copy destruction is the caller's
obligation. These operations cannot extend lifetimes or bypass thread rules.

## 10. Cells and pinning

Allocation-free Cell/RefCell and guard borrow/replacement rules are specified
in [library-surface section 3](library-surface.md#allocation-free-cells-and-pin-properties).
In addition, Cell `into_inner` consumes the cell; Copy-only get copies the
payload. Cell `swap` is a no-op for identical cells but panics for partial
overlap; RefCell self-swap panics. Cell `update` reads a Copy payload,
calls an at-most-once callback and then sets its result.
RefCell `replace_with(f: take fn(mut T): T)` holds exclusive dynamic access
while calling f, replaces on success, and preserves any mutations to the
old initialized payload on panic. `take` uses Default before replacement.

`Ref.map`/`RefMut.map` consume a guard and call an at-most-once projection
from read/mut T to a subview with the same region/access, transferring the
dynamic borrow token. `filter_map` returns a mapped guard on present
projection or the original guard on none. `map_split` consumes a guard and
produces two guards over its projected read views or disjoint exclusive
views; releasing one does not release the other's borrow. Ref clone acquires
another read token. Guard projection neither clones payloads nor extends
the cell lifetime. Callback panic releases the consumed guard's token.
Borrow errors are ordinary zero-sized error values, not payload owners.

`UnsafeCell<T>` marks interior-mutable bytes, preserving T's representation.
`new/into_inner/get_mut` transfer or exclusively borrow as their names imply;
`get` returns a raw mutable pointer through shared access, not a safe exclusive
reference. It removes the read-freeze assumption for its marked bytes, not
data-race, validity or exclusive-loan obligations. It is not Shareable by
default merely because T is.

`OnceCell<T>` is an unsynchronized empty-or-initialized slot. `new/default`
is empty; `get` returns optional read T; exclusive `get_mut` returns optional
mut T. `set(take T)` initializes only an empty slot and returns the rejected
T as failure when occupied. `get_or_init(make: take fn(): T)` calls make
only on empty and installs after successful construction; panic leaves empty.
Reentrant initialization is an error and may panic; it cannot create
aliased mutable payload access. `take` needs exclusive access and resets to
empty while transferring optional T; `into_inner` consumes the cell.
Clone clones initialized T only; its allocation/effects are T's.

`LazyCell<T,F>` owns an uncalled at-most-once initializer F, initialized T,
or a poisoned state. `new(take F)` does not invoke F.
`force`/Deref initialize through shared interior access; `force_mut` through
exclusive access. `get/get_mut` do not initialize and return none until ready.
Initializer panic poisons the cell irrecoverably; later force panics rather
than calling a consumed initializer. Dropping an unforced cell drops F;
dropping a ready cell drops T. Default uses T's Default lazily.
These cells do not synchronize concurrent threads.

Pinning is an access promise, not ownership or allocation.
`Pin<P>` preserves P's pointer/owner representation and holds its dereference
target at a stable address until that target is destroyed in place.
Safe `new/into_inner/get_mut` require the target Unpin for operations that
would expose unrestricted movement. Unsafe `_unchecked` constructors and
extraction require the caller to maintain pinning even after the wrapper's
own lifetime ends. `as_ref/as_mut` reborrow pinned access;
`get_ref` returns an ordinary read view. Unsafe `get_unchecked_mut` must not
be used to move a !Unpin target. Unsafe `map_unchecked[_mut]` projections
require a structurally pinned subobject that remains in place and is
destroyed in place; a projection cannot introduce a shorter backing lifetime.
`set(take T)` destroys the previous target in place before initializing new
T at the same address, obeying replacement cleanup on panic.
`PhantomPinned` prevents automatic Unpin; PhantomData supplies its declared
variance, region, destruction and thread-property evidence without storage.
No pin operation by itself creates a Transferable/Shareable implementation.

## 11. Ranges, operators and control flow

Range bounds are Included(read T), Excluded(read T) or Unbounded.
`RangeBounds.start_bound/end_bound` borrow their endpoints;
`contains(read U)` uses the declared cross-type PartialOrd and returns false
on an incomparable bound/test value.
Half-open range is start <= x < end, inclusive is start <= x <= end,
one-sided forms omit one test, and full range always contains the value
because it performs no bound comparison, including for an unordered float.
`is_empty` tests reversed/equal half-open bounds or reversed inclusive bounds;
incomparable bounds make the range empty.

Integer and char range iteration uses a sealed stepping capability.
Half-open yields start through the predecessor of end; inclusive yields its
final endpoint once and marks exhaustion without overflowing beyond it.
Char stepping skips the surrogate interval. Reversed ranges are empty.
RangeFrom continues upward until its integer overflow policy intervenes;
it cannot silently yield a wrong-width host value. Char RangeFrom panics
rather than constructing an invalid scalar beyond char.MAX.
For inclusive range values that themselves implement Iterator, permanent
exhaustion makes is_empty true and contains false regardless of the retained
endpoint representation; endpoint queries after exhaustion have no additional
value guarantee. This state is not added to a separate non-iterator range
descriptor merely because its consuming iterator can become exhausted.
Forward/backward traversal shares the remaining interval. ExactSize is
implemented only when the declared endpoint domain/count fits usize for all
legal remaining states; not every wide integer range is ExactSize.
Size hints clamp lower bounds at usize::MAX and use absent upper on
unrepresentable counts. `nth` may optimize stepping but must preserve overflow
and the same selected value. Old `core.ops` and newer `core.range` identities
remain distinct where their iterator/consuming representation is distinct.

Arithmetic/bitwise operator interfaces associate Output and preserve the
receiver/argument modes in their implementation; assignment interfaces mutate
the receiver and return Unit. Deref lends its associated Target, DerefMut
lends exclusively and requires Deref. Index/IndexMut preserve bounds-panic
and region rules of their target collection; they cannot clone or allocate
to return an element. Drop runs once for initialized owned storage under
the language cleanup rules and cannot be invoked as an ordinary safe method
to leave an invalid live object.

`ControlFlow<B,C = Unit>` contains Break(B) or Continue(C).
`is_break/is_continue` query; `break_value/continue_value` consume and return
an optional selected payload, dropping the unselected one.
`as_ref/as_mut` project the active payload. `map_break/map_continue`
consume and invoke an at-most-once consuming callback only on their selected
branch. `break_ok/continue_ok` convert to outcomes with exactly the declared
payload alternatives. No allocation or implicit error conversion occurs.
Callable/async-call capabilities and uninhabited Never retain
[their native rules](library-and-abi.md#5-iteration-and-callable-apis).

## 12. Formatting, dynamic type identity and hints

The allocation-free borrowed Message/format parameter and sink boundary are
specified in [library-surface section 10](library-surface.md#10-formatting-and-output).
`Display/Debug/Binary/Octal/LowerHex/UpperHex/LowerExp/UpperExp/Pointer`
each read Self and write to `mut Formatter`, returning Unit throws fmt.Error.
Write `write_str/write_char/write_fmt` similarly propagates sink failure;
partial output is allowed. fmt.Error carries no OS error or allocation policy.
Formatting cost is O(emitted characters plus payload formatting work).

Formatter exposes fill, alignment, width, precision, alternate, sign and
zero-pad flags without altering them. Default fill is space; width is a
minimum output width measured in scalar characters, not UTF-8 bytes.
Text precision is a maximum scalar count. Numerical precision has the
operation's digit meaning; fixed floating precision rounds ties to even.
Sign-aware zero padding occurs after sign/radix prefix and overrides ordinary
numeric alignment. Alternate integer formatting supplies the radix prefix;
alternate Debug selects multiline pretty structure formatting.
Core integer output produces exact digits without a heap. Float Display/
Debug and parsing retain library-and-abi section 3's numerical contract.

Debug builders borrow their Formatter exclusively and emit struct fields,
tuple fields, list/set elements or key/value entries in invocation order.
`field/entry/entries/key/value` read values and propagate the first formatting
failure. `finish` closes the representation; non-exhaustive finish adds the
ellipsis marker. Map keys and values must alternate; an unmatched key before
finish/value sequencing error panics. Empty builders emit empty syntax.
Builders store formatting state, not owning copies of formatted values.
`from_fn` wraps a formatter callback and calls it when formatting is requested,
without pre-rendering or allocating. Numeric-buffer extension types are not
assigned full member coverage here.

`Any` applies to Static concrete types, including unsized types where its
declared implementation supports them. `type_id` yields TypeId for the
concrete type, not a borrowed wrapper unless that wrapper is the concrete
value being queried. TypeId equality/order/hash are consistent within one
program; numeric representation, cross-build identity and ordering are not
stable serialization promises. `is<T>/downcast_ref<T>/downcast_mut<T>` test
exact identity and borrow only on success. `type_name<T>/type_name_of_val`
produce static diagnostic text, without evaluating a value or allocating;
spelling is not unique type identity, stable mangling or a lifetime proof.

`black_box(take T): T` is a best-effort optimization barrier preserving the
value, not volatile I/O or a cryptographic constant-time guarantee.
`spin_loop` is a processor scheduling hint, not a fence, yield or progress
guarantee. `cold_path` supplies an optimization hint without semantic effects.
`select_unpredictable(cond, take a, take b)` eagerly evaluates/consumes both
arguments, returns the selected one and drops the other; no branchless code
guarantee follows. Unsafe `assert_unchecked(bool)` requires true;
unsafe `unreachable_unchecked(): Never` requires control never to reach it.
False/reached calls violate unsafe preconditions, unlike checked assert/panic.
Panic information/location/hook behavior is owned by library-surface section 1
and the language panic contracts, not by these optimizer hints.

## 13. Polling, waking and atomic operations

Future `poll(pinned mut Self, mut Context): Poll<Output>` requires exclusive
pinned access. Pending leaves initialized future state and arranges a wake
when progress can be made; it must not block waiting for readiness.
Repeated polls may use a different task waker; registrations must use the
latest appropriate one. Ready transfers output. Polling after Ready may
panic, diverge or otherwise be unspecified but a safe call cannot cause
undefined behavior. Compiler-generated completed/panicked futures panic on
repoll. No executor, task allocation or scheduling policy is selected by core.
Dropping a pending future destroys its live state, not an invented rollback
of external effects.

`ready(take T)` yields Ready(T) on its first poll; `pending<T>()` always
yields Pending. `poll_fn(f: mut fn(mut Context): Poll<T>)` owns and delegates
to f on each poll with pinned capture state. IntoFuture consumes its receiver
and constructs the associated Future; a Future's identity implementation
does not start execution.

Poll `is_ready/is_pending` query; `map` consumes and invokes
`take fn(take T): U` only on Ready. `as_ref/as_mut` borrow its active payload.
`map_ok/map_err` for Ready outcomes map only the selected alternative;
Pending and the other alternative propagate untouched. Pending never
fabricates an optional/outcome payload.

Context borrows its waker. Waker clone explicitly acquires another wake
capability; `wake(take self)` consumes one, `wake_by_ref` preserves one.
Dropping releases one. A wake schedules at least one future poll while the
executor continues running the task, with coalescing allowed and no fairness
or one-poll-per-wake guarantee. `will_wake` true guarantees the same task;
false may be conservative. `clone_from` may reuse an equivalent capability.
The no-op waker has no scheduling effects.

RawWaker contains a data pointer and clone/wake/wake_by_ref/drop table.
RawWaker.new and RawWakerVTable.new store the supplied data/function entries
without calling them or acquiring an ownership unit. Unsafe Waker.new/from_raw
claim one such ownership unit under the following obligations.
Unsafe construction must establish live data/table, matching callback ABI,
thread-safe calls for a transferable Waker, one independently owned capability
per clone, and exactly one consuming wake or drop for each owned capability.
Wake-by-ref cannot consume that capability. Raw accessors and equality do not
acquire ownership; reconstructing a Waker from borrowed raw parts without
acquiring another capability is invalid. No automatic allocator is supplied.
Static no-op access lends a Waker with static backing and no wake/drop effects;
it does not allocate or arrange a task poll.

Atomic memory ordering and fences are independently specified in
[memory-and-concurrency section 4](memory-and-concurrency.md#4-atomics-and-happens-before).
For every target-supported bool, integer and pointer atomic:
`new/into_inner/get_mut/as_ptr` construct, consume, exclusively borrow or
expose the storage without an atomic read/write; raw use retains race rules.
Unsafe `from_ptr` borrows an atomic object over raw storage: the pointer must
be aligned for the atomic type (which can exceed the underlying scalar's
alignment), live/readable/writable for the requested region and support the
atomic type's valid representation. Conflicting non-atomic or different-size
atomic accesses require the memory model's exclusion/synchronization; forming
the view does not itself synchronize or repair a race.
`load/store/swap` perform the named indivisible access. `compare_exchange`
compares stored bits, returning success(old) after writing the replacement
or failure(observed) without writing; weak form may fail spuriously.
`fetch_add/sub` use wrapping integer arithmetic; fetch and/or/xor/nand and
min/max compute the indicated operation and return the old value.
Bool nand is logical negation of conjunction. Pointer fetch arithmetic moves
the address without extending provenance or granting dereference authority.
`fetch_update` uses `mut fn(old): T?`, may call it repeatedly under contention,
stops on none without writing, and returns success(old) on the winning CAS
or failure(last observed) when declined. User callbacks must tolerate retries.
Invalid ordering panics before the access. Atomic operations do not allocate.
Supported widths/alignment/lock-free capabilities remain target-dependent;
an unsupported atomic width is unavailable, not silently an OS-locking core
operation.

## 14. C strings and foreign scalar interfaces

`CStr` views a contiguous byte sequence ending in exactly one first NUL;
UTF-8 is not required. Its borrowed extent includes that terminator.
`from_bytes_with_nul` checks exactly one terminal NUL and no earlier NUL;
`from_bytes_until_nul` finds the first NUL and ignores following bytes.
Missing/interior terminator errors retain the declared distinct error types.
Unsafe `_unchecked` construction requires those invariants.
Unsafe `from_ptr` requires a non-null readable pointer into one allocation
through its first NUL, within isize::MAX bytes, with no mutation for the
returned region. `as_ptr` does not transfer ownership or promise lifetime
beyond the backing loan.

`to_bytes/to_bytes_with_nul` lend excluding/including the terminator.
`count_bytes` excludes it. `is_empty` means a leading terminator.
`to_str` validates UTF-8 and returns a borrowed Text or Utf8Error.
`to_string_lossy` borrows valid UTF-8 or allocates replacements (U+FFFD)
for malformed subsequences. CStr equality/order/hash compare content bytes
independently of pointer addresses. Byte iteration omits the terminator.
Validation/construction/string conversion is O(bytes); a stored length may
make subsequent queries constant-time, but from_ptr must find the terminator.
CString ownership and raw reconstruction are specified in the collection
contract. `c"..."` literals have static terminated storage and reject interior
NUL during required construction.

Native `core.ffi.c_*` scalar aliases have the width, signedness and ABI of
the named C fundamental type on the selected target, not a fixed Linux-host
substitution. `c_char` signedness and `c_long` width are target-dependent.
`c_void` is an opaque foreign pointee type, not constructible owned payload.
Foreign calling, variadic cursor promotions and layout are specified by
[library-surface section 5](library-surface.md#5-layout-and-foreign-completion).
Reading a variadic argument is unsafe: the requested promoted scalar/pointer
type must match the next actual argument and the cursor must remain within
the live foreign call. Copying a cursor duplicates traversal state through
the target ABI operation, not a guessed bytewise native struct copy.

## 15. Applicability, constant evaluation and coverage

These are portable core semantics wherever their input types and explicit
target capabilities exist. Core requires no allocator, OS or executor.
Alloc-backed results require the alloc layer. V1 qualification is Linux x64
only; the eight [reference profiles](reference-profiles.md) remain post-V1
applicability/qualification obligations. Target pointer width/endian/C ABI/
atomic support control applicability, not the host running the compiler.
Architecture operation families are excluded from this document.
Stable nondeprecated operations only are assigned here; experimental members
are not made required by their stable enclosing type. Explicit native
allocator controls remain selected independently.

### 15.1. Required constant evaluation

Required constants use target data and checked evaluation under the numeric
annex. An invalid safe constant operation is a compile-time error; an unsafe
constant call must meet the same preconditions as runtime. No arbitrary
callback, destructor, allocation, erased dispatch or Clone implementation
becomes const-callable by appearing in this document.

For an operation whose runtime semantics are specified here, the local
catalog's stable constant-callability flag is native eligibility metadata
under T08. Such a call evaluates using the native value, arithmetic, region,
initialization and memory rules alone; it requires neither another language's
evaluator nor its documentation. The flag preserves eligibility, not permission
to perform otherwise-invalid constant effects. Eligibility does not arise merely
because an implementation can fold a call. A runtime member not
specified here remains unmigrated regardless of whether that flag is stable.

### 15.2. Native authority boundary

The covered runtime groups are:

| Native/source family | Covered members |
| --- | --- |
| `core.cmp`, `clone`, `default`, `convert`, `borrow`, `hash`, `error` | Protocol operations and structural/primitive implementation behavior in section 2; error sources and checked downcasts |
| Integer/bool/char/f32/f64 primitives, `core.num`, `core.ascii` | Explicit section 3 helpers, named NonZero helpers/numeric wrappers, constants, parse/escape behavior |
| `core.text` (source `str`) | UTF-8/view/search/split/trim/scalar/byte/encoding/escape groups in section 4 |
| `core.slice`, arrays | Projection/chunks/windows/splits/disjoint/movement/search/order/construction/iteration groups in section 5 |
| `core.iter` | Protocols, listed constructors/adapters/consumers, FromItems/ExtendItems and selected short-circuit collection |
| Source `core.option`/`core.result` Iter, IterMut, IntoIter | Zero-or-one next/next_back/size_hint/len/fused behavior, owned cleanup and the stated Clone eligibility; inherited consumers/adapters retain their own bounds |
| `core.ptr`, `mem`, `cell`, `pin`, marker properties | Explicit section 9/10 runtime operations and invariants |
| `core.ops`, source `range` | Listed operators, bounds, sealed scalar iteration and ControlFlow |
| `core.fmt`, `any`, `hint` | Listed protocols, builders, type checks and optimizer hints |
| `core.future/task`, `sync.atomic` | Listed poll/waker and target-supported atomic families |
| `core.ffi`, `alloc.ffi` reexports | CStr/foreign scalar/variadic rules here and CString in the collection document |

A protocol law applies to all of its implementation members, but does not
invent an absent implementation or erase its declared bounds. Separate
type-specific operations are covered only by an explicit group above.
Public reexports preserve one identity and one contract.

The following are concrete limits to complete core/alloc retirement:

- Newly added or uncommon members not named or semantically grouped here
  (including numeric-buffer formatting extensions, newer peek/initialization
  helpers and spare-storage writers other than write_copy_of_slice) require
  member-specific reconciliation before assignment.
- `core.io` byte-I/O adapters, `core.net` address methods and `core.time.Duration`
  require their own native operation authority; a std reexport alone does
  not define them. Hosted contract specifications may supply that shared
  authority. No socket/thread/clock semantics are imported into core here.
- Complete generated derive/auto-property/implementation-member and
  compiler-facility coverage is not established by this document.
  Unsupported target/compiler features remain implementation gaps rather
  than changing the language or library contracts.

### 15.3. Observed reconciliation work

Source inspection, not execution, found these mismatches requiring separate
implementation/acceptance work:

- `library/core/unicode_data.mt` declares Unicode 16.0.0; the selected property
  and case contract here requires Unicode 17.0.0.
- `library/core/cmp.mt` clamp does not check reversed bounds before selection.
  Its `Ordering.then_with` uses a read-callable signature where the contract
  must accept a consume-callable one-shot callback.
- Several iterator terminal methods in `library/core/iter.mt` use mutable
  rather than consuming receiver declarations; review their public access
  contract rather than treating currently accepted calls as authority.
- `library/core/future.mt` Waker.will_wake compares only data addresses;
  unrelated vtables can share an address, so true needs stronger task-identity
  evidence. Source Poll mapping callbacks likewise need one-shot capability
  review.
- `library/core/hash.mt` describes a fixed zero-key default hash and portable
  integer encoding. That is not evidence of randomized collision protection
  for Map, nor closure of prefix-separated structural hashing.

These observations do not redefine a contract to match current bodies.
No build, execution, sanitizer, constant or profile qualification is claimed.
