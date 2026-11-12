# Native machine operation contracts

Operation specification. These rules define
architecture operations independently of another programming language.
[Native memory validity](../spec/memory-and-concurrency.md),
[scalar arithmetic](../spec/semantic-rules.md#3-scalars-and-arithmetic) and
[platform ABI contracts](../spec/platform-contracts.md) still apply.

## 1. Declarations and applicability

Architecture builtins have fixed native declaration identities, parameter and
result types, constant operands, target/feature predicates and safety modes.
The frozen declaration catalog retains these facts and their provenance;
an external documentation URL is not the semantic authority for the operations
specified below. The signature translation rules in
[library-surface](library-surface.md#2-recursive-translation-rules) determine
native access modes, generic constants and type identities.

Every immediate operand marked constant must be evaluated during checking.
Validate its declared signedness, bit width, lane range and permitted encoding
before lowering. A runtime value or out-of-range immediate is rejected, not
silently truncated, unless the operation explicitly defines masking.
Inputs are evaluated in native source order. Scalar/vector inputs are values;
raw pointer inputs do not create safe views or transfer allocation ownership.
Required constant-callability is the declaration's stable constant contract
under T08, independently of runtime stability. A mathematical formula below
does not make a runtime-only intrinsic constant-callable.

An intrinsic is available only under its declaration's architecture and feature
predicates. The compiler must establish those predicates from the selected
baseline, the enclosing function's feature requirements or a valid dominating
feature guard. An architecture module name alone establishes no optional CPU
feature. Feature-dependent calling ABIs must be bridged under
[the native feature contract](library-surface.md#5-layout-and-foreign-completion).

Unsupported lowering is diagnosed explicitly. It does not redefine the
operation, authorize arbitrary instruction execution or qualify the profile.
All eight [reference profiles](../spec/platform-contracts.md#8-reference-profiles) remain in post-V1 scope;
only applicable instructions belong to a profile's operation obligations.

## 2. ISA-defined intrinsic families

For x86/x86-64 vector and scalar intrinsics, the native operation with a published
vendor intrinsic name implements that named operation in the
[Intel intrinsic specification](https://www.intel.com/content/www/us/en/docs/intrinsics-guide/index.html).
For AArch64 vector intrinsics it implements the corresponding named operation
in the [Arm ACLE intrinsic specification](https://arm-software.github.io/acle/neon_intrinsics/advsimd.html).
These are platform instruction contracts, not source-language compatibility.
The declaration's exact operand widths, signedness, lane count, memory form,
immediates, masking and target features select the particular operation.

The compiler must preserve that operation's:

- lane arrangement, signed/unsigned interpretation and bit-pattern result;
- wrapping, saturation, rounding, comparison and exception behavior;
- active-mask behavior, including whether inactive results merge or zero;
- memory extent, alignment, address-generation and fault-suppression rules;
- instruction-specific ordering, cache, floating-environment and register effects.

For a pointer operand, the caller must establish the live readable/writable
extent actually accessed by that operation, provenance and any required
alignment. A non-temporal store still requires valid writable storage.
For x86 non-temporal stores, the storing thread must execute `_mm_sfence`
before any other access to the affected storage, including publishing it for
another thread's access.
A masked operation suppresses access only for lanes for which its instruction
contract promises suppression; a mask does not generally validate a bad pointer.
Unaligned forms relax alignment only, not extent, validity or access authority.
Architecture float operations retain their instruction's NaN, signed-zero and
rounding behavior rather than inheriting a generic fast-math license.

Vector carriers preserve native vector identity. A carrier's lane shape,
bit width and alignment are part of its declaration. Multi-register structures
preserve the declared register order and calling ABI; they are not interchangeable
with an arbitrary tuple solely because their byte sizes agree. Bit casts
preserve the source bits; widening casts with unspecified upper lanes do not
initialize those lanes to a promised value. Explicit zero-extension forms do.

When an intrinsic is a documented alias, its canonical instruction operation
and operand interpretation determine behavior; the alias creates no second
type or implementation identity. ISA-only instructions unavailable on every
selected profile do not become universally callable.

## 3. Integer bit helpers

These operations have the direct results below and retain their `tbm` target
feature requirement. The formulas do not authorize a feature-free fallback.
Let `x` be an N-bit unsigned integer,
`~` be complement within N bits, and addition/subtraction below wrap modulo
`2^N`. The u32 and u64 forms use N = 32 and 64 respectively.

| Helper stem | Result |
| --- | --- |
| `_blcfill` | `x & (x + 1)` |
| `_blci` | `x | ~(x + 1)` |
| `_blcic` | `~x & (x + 1)` |
| `_blcmsk` | `x ^ (x + 1)` |
| `_blcs` | `x | (x + 1)` |
| `_blsfill` | `x | (x - 1)` |
| `_blsic` | `~x | (x - 1)` |
| `_t1mskc` | `~x | (x + 1)` |
| `_tzmsk` | `~x & (x - 1)` |

For `_bextri`, the constant control must fit 16 unsigned bits.
Bits 0-7 give the start bit and bits
8-15 give the requested length. A start at or beyond N yields zero.
Otherwise return the selected range shifted to bit zero, using only
`min(length, N - start)` bits and clearing the rest. The mathematical mask
definition does not require an overflowing native shift by N.

These helpers are independent of the program's overflow-check setting.

## 4. Machine queries and specialized transfers

`__cpuid` queries the selected leaf with subleaf zero and returns
eax/ebx/ecx/edx as u32 values in those named fields.
The query observes the executing CPU's instruction result, including any
virtualization policy; compile-host facts or static feature assumptions cannot
replace that observation.
The counted/subleaf form preserves the supplied leaf and subleaf.
`__get_cpuid_max` returns `(eax, ebx)` for the supplied leaf and subleaf zero.
For leaf zero or `0x80000000`, eax is respectively the maximum supported basic
or extended leaf; arbitrary leaf inputs are not reinterpreted as those queries.
No query alone grants permission to use an optional instruction; OS-managed
state support is also required where applicable.

`cmpxchg16b` performs the aligned 16-byte atomic compare/exchange operation:
observe the old 128-bit value, replace it only when its bits match the expected
value, and return the observed value. The pointer must be 16-byte aligned and
valid for the atomic access; the processor feature and requested
success/failure orderings must be valid.
[Native atomic ordering](../spec/memory-and-concurrency.md#4-atomics-and-happens-before)
governs synchronization. No tearing or blocking lock emulation is permitted
under this operation's identity.

The `_mm_extract_si64`/`_mm_extracti_si64` operations extract a bit field from
the low 64 bits of `x`, shift it to bit zero and clear the remaining low bits.
`_mm_insert_si64`/`_mm_inserti_si64` replace that field in the low 64 bits of
`x` with the low field-width bits of `y`, preserving other low bits.
All four leave their upper 64 result bits unspecified.

The immediate forms supply `LEN` and `IDX` as six-bit unsigned constants;
`(0, 0)` means all 64 low bits. Reject operands outside 0-63, a sum above 64,
or zero length with nonzero index. For dynamic extraction, `y[13:8]` supplies the index and
`y[5:0]` the length; dynamic insertion instead uses `y[77:72]` and `y[69:64]`.
Other control bits are ignored. Encoded zero length means 64. If a dynamically
selected field extends beyond bit 63, no result bits are specified; this does
not permit invalid memory access, erased surrounding effects or arbitrary
program behavior. The four bit-field operations require `sse4a`.

`_mm_stream_ss` and `_mm_stream_sd` perform non-temporal stores of the low
f32/f64 lane to respectively four/eight writable bytes, aligned to four/eight
bytes. These are non-atomic stores, not synchronization or persistence
operations and require `sse4a`. They neither store the whole vector nor promise
durable storage. The store-fence obligation in section 2 applies.

## 5. AArch64 scalar and lane aliases

The following alias families have direct native definitions:

- `vadd`/`vaddq` on f64 lanes add corresponding floating lanes under the
  instruction floating environment. Scalar and single-lane s64/u64 additions
  retain the low 64 result bits.
- `vdup_n`/`vdupq_n` and `vmov_n`/`vmovq_n` replicate the supplied f64 or
  polynomial-64 bit pattern to each destination lane.
- `vbsl`/`vbslq` select each result bit from the second input when the matching
  mask bit is one, otherwise from the third input. This is not a float comparison.
- `vget_lane_f64` returns the selected lane. `vext` concatenates the two input
  carriers and takes the declared vector-sized lane range at the constant
  offset. Indices must satisfy the declaration's lane bounds.
- `vld1_dup`/`vld1q_dup` read one f64 and replicate it; lane-load forms read one
  f64 and replace only the selected destination lane. The access extent is one
  f64, not the entire resulting vector.
- `vshld_n` retains the low 64 bits after a constant left shift. `vshrd_n`
  uses arithmetic shift for s64 and logical shift for u64. `vsrad_n` adds that
  shifted value to its accumulator modulo `2^64`. The encoded shift's legal
  range is checked before lowering, including the instruction-defined
  full-width right-shift case.

Polynomial carriers preserve bits; they do not acquire ordinary integer
arithmetic from an alias. Constant-lane and feature constraints remain part of
each declaration.

## 6. WebAssembly operations

Native wasm32 builtins implement the named instructions in the
[WebAssembly execution specification](https://webassembly.github.io/spec/core/exec/instructions.html),
including SIMD and explicitly enabled proposal instructions. `v128` is a
128-bit carrier; the operation's lane prefix specifies its interpretation.
Unsigned aliases select unsigned comparison, extension, saturation or conversion
where those differ; bitwise-equivalent aliases share the same operation.

The native naming correspondence is:

| Native family | Instruction behavior |
| --- | --- |
| `iNxL`, `uNxL`, `fNxL` constructors | Place arguments into lanes in increasing lane-index order |
| `splat`, `extract_lane`, `replace_lane` | Replicate, read or replace the indicated lane |
| `shuffle` | Select constant lanes from the concatenated two-input lane sequence |
| `swizzle` | Select source bytes using byte indices; out-of-range indices yield zero |
| `eq`, `ne`, `lt`, `le`, `gt`, `ge` | Lane comparisons produce all-one or all-zero lane masks |
| `add`, `sub`, `mul`, `neg` on integers | Lane-wise arithmetic modulo the lane width |
| `add_sat`, `sub_sat`, `narrow` | Clamp to the operation's signed/unsigned destination range |
| `shl`, `shr` | Mask the shift count to the lane width; signed right shift extends the sign |
| `extend_low`, `extend_high`, `extmul_low`, `extmul_high` | Select the low/high input half and extend with the indicated signedness before use |
| `extadd_pairwise` / `dot` | Widen and combine the specified adjacent lane products/sums |
| `all_true`, `any_true`, `bitmask` | Reduce nonzero lanes/bits or gather each lane's high bit |
| `and`, `or`, `xor`, `not`, `andnot`, `bitselect` | Apply the corresponding bitwise operation to the carrier |
| Float arithmetic, min/max, pseudo-min/max and conversions | Preserve the distinct named instruction's NaN, zero-sign, rounding and saturation rules |
| `load`, `store`, lane/extension/splat/zero loads and lane stores | Access only the instruction's byte extent and perform its declared lane arrangement |

`relaxed_*` operations permit exactly the result alternatives of their
corresponding relaxed-SIMD instructions, not arbitrary results or native
fast-math assumptions. A relaxed opcode requires its own enabled target
feature. A strict operation cannot be lowered to a relaxed one if that expands
its possible results.

Memory indices and lane indices are compile-time operands where declared.
The selected `memory_size`/`memory_grow` declarations accept memory index zero
only; the presence of a constant index does not expose arbitrary memories.
Raw-pointer accesses require valid native provenance and extent even when
WebAssembly would otherwise trap on an out-of-bounds linear-memory address.
Memory growth returns the previous page count on success and the all-one
pointer-width unsigned sentinel on failure. It does not fabricate an allocation
owner; size/growth units are the instruction's pages. Growth cannot shrink
existing memory. Newly added bytes are zero, and failure leaves the memory size
unchanged.
An unreachable instruction traps and does not run cleanup.

## 7. Assembly, validity and acceptance

Inline/global/naked assembly use the independent native contracts in
[the assembly annex](../spec/specification-annex.md#5-attributes-layout-and-assembly)
and [foreign completion](library-surface.md#5-layout-and-foreign-completion).
No optional feature, clobber, unwind permission or memory effect is inferred
solely from assembly text.

Acceptance requires exact declaration checks, constant-immediate negatives,
lane/bit-pattern cases, feature admission/dispatch tests, memory extent/alignment
and actual ABI/execution evidence on applicable profiles. Instruction-specific
NaNs, saturation, masks and fault suppression cannot be replaced with a single
representative vector-add test. No execution or safety proof is claimed here.
