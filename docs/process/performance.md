# Performance and release protocol

## 1. Accepted requirement

Decisions D16-D17 require better readability and three measured release gates:

- **Runtime** must match or beat the frozen Rust baseline on each agreed
  representative workload.
- **Compile time** (clean builds, incremental builds after fixed edits, and
  check-only) must beat the frozen Rust/Cargo baseline on each agreed
  representative workload.
- **Retained build-cache bytes** must beat the frozen Rust/Cargo baseline for the
  same workloads and build states (section 5.1).

Apply section 4 on a qualified runner. Report compiler/program RSS, allocations
and binary size; they have no equality gates, but unacceptable growth must be
visible. No slowdown allowance or cross-workload compensation applies; the
former 10-percent investigation threshold is superseded.

## 2. Benchmark definitions

Before collecting release results, version each workload with:

- Rust and Mettle sources, algorithm and data-layout equivalence.
- Input datasets/seeds and small/medium/large sizes.
- Ownership, allocation, error, panic, overflow and bounds-check policies.
- Target hardware/OS, CPU features, toolchain/sysroot and dependency identities.
- Optimization, LTO, codegen and linking settings.
- Primary runtime metric, warmup, repetitions, run randomization and outlier rule.
- Statistical comparison, measurement resolution, and stop/retest conditions.

Use paired/interleaved Rust and Mettle runs on controlled hardware rather than
all Rust runs followed by all Mettle runs. Separate cold-start workloads from
steady-state workloads. Never remove inconvenient results after inspecting which
language lost; annotate infrastructure failures using predeclared rules.

## 3. Initial workload backlog

| ID | Workload | Primary evidence |
| --- | --- | --- |
| P01 | Integer loops and reductions | Runtime with matching overflow policy |
| P02 | Floating-point kernels | Runtime with matching arithmetic/fast-math settings |
| P03 | UTF-8 scanning and parsing | Throughput, valid/invalid input handling |
| P04 | Allocation-heavy structured parser | Runtime and allocation/peak-memory trace |
| P05 | Hash and ordered collections | Operation latency across sizes and key distributions |
| P06 | Generic iterator pipeline | Concrete specialization and eliminated intermediate storage |
| P07 | Streaming file transform | Throughput and system-call policy |
| P08 | Local and atomic shared ownership | Transfer versus retain workloads separately |
| P09 | Contended synchronization/channels | Throughput and tail latency under fixed concurrency |
| P10 | Async network service | Throughput, p95/p99, cancellation and shutdown |
| P11 | C callback/buffer bridge | Call and translation overhead with equivalent contracts |
| P12 | Compiler bootstrap workload | Runtime of produced compiler, distinct from time to build it |

P01 can start at M1; later workloads begin only when their required capabilities
exist. Passing the early subset is not passing the V1 runtime gate.
P12 becomes applicable when a comparable compiler workload exists; do not compare
different compiler algorithms as if they were identical generated-code tests.

`tools/run_p01.py` begins P01 using equivalent signed-i32 xorshift reductions
with matching overflow policy and generic CPU selection. An independent Python
calculation checks each exit checksum. It records compiler elapsed time/process
peak RSS, sources/binaries and six randomized pairs per size in `build/p01/`.
These include process startup and use one uncontrolled shared-host session.
This is engineering evidence only. Record the actual Rust version; anything
other than frozen 1.99.1 cannot qualify release comparison.

## 4. Decision rule

Normalize metrics so a ratio above one means Mettle is worse: for latency/time,
Mettle divided by Rust; for throughput, Rust divided by Mettle.

Use a predeclared confidence procedure appropriate to each metric and paired
run design. Account for multiple workloads and repeated looks; do not repeatedly
sample until an unfavorable interval happens to disappear.

- Credible slowdown: uncertainty bounds support a ratio above one. Fail and
  investigate that workload.
- Credible improvement: bounds support a ratio below one. Record a measured win.
- Indistinguishable: adequately precise results overlap parity. Record a tie
  within measurement resolution, not proof of exact equality.
- Inconclusive: noise, unstable environment, or inadequate sample precision.
  Do not count this as a pass.

Use paired log ratios of independent run-block metrics. For K predeclared primary
runtime endpoints, use two-sided Student-t intervals on the mean log ratio with
per-endpoint alpha = 0.05/K, then exponentiate the bounds. Bonferroni controls
family-wise error without assuming independence between endpoints. The method
assumes independent blocks with adequately behaved log-metric variation;
unresolved dependence/heavy-tail diagnostics make a result inconclusive.

The requested interval half-width is at most log(1.005), a selected 0.5-percent
measurement-resolution target, not a measured capability or slowdown allowance.
Use at least 16 pilot pairs across two sessions to estimate variance, then select
and lock a fresh release sample count of at least 30 independent pairs sufficient
for that precision using the corrected quantile. Pilot data is not release data.
Within-pair execution order is randomized; sessions are balanced across orders.
Tail-latency endpoints also require enough underlying events to estimate the
requested quantile; recording 30 tiny runs is not sufficient by itself.

If the fixed release sample misses precision or assumptions, report inconclusive.
A replacement experiment needs a new registered plan with prior results retained;
do not extend the favorable-looking run until it passes. A measurement-resolution
budget is not permission to accept a known systematic regression.

Investigate failures in semantics, algorithm, data layout, library implementation,
frontend lowering, LLVM settings, runtime policy, and environment separately.
Preserve minimized reproductions. Do not weaken safety or switch algorithms
silently to improve the score.

## 5. Build and tooling measurements

Measure clean builds from defined empty build state, incremental builds after
fixed edits, semantic check latency, LSP edit response, peak compiler memory,
binary/debug-info size, retained build-cache bytes and bootstrap stages.

Compiler time and produced-program runtime are separate metrics; self-hosting or
backend ownership implies no speedup.

### 5.1. Compile-time and build-storage gate

Version each build workload like section 2: Mettle and Rust/Cargo sources with
equivalent algorithms and dependencies, the frozen Rust 1.99.1 toolchain and its
Cargo, profiles, optimization/LTO/codegen/debug-information settings, target
and host identities, and an explicit cold/warm cache policy for both sides. The
same corpus as the runtime workloads is used where a workload is buildable by
both, plus multi-module and generic-heavy build corpora.

Per workload, compare Mettle with Rust/Cargo on: wall time of a clean build,
wall time of an incremental build after each fixed edit, wall time of
check-only, and **retained build-cache bytes** (allocated bytes of the build
directory and caches after the clean build and after the edit sequence, all
debug and incremental data included; moving data elsewhere is not a saving).
Also record peak RSS of the compiler, peak scratch bytes and binary size.
Apply the section 4 ratio normalization (ratio above one means Mettle is
worse), paired/interleaved runs and confidence procedure to the time metrics; the
byte metrics are deterministic per build state and are compared directly with
repeat runs confirming stability. An unqualified runner, missing counter or
inconclusive result does not count as a pass.

#### 5.1.1. Build-cache storage design

The user build cache is built to retain less than Cargo's `target/` directory:

- **One store for all projects.** Artifacts live in one user-level directory
  (`--cache-dir`, `METTLE_CACHE_DIR`, then `~/.cache/mettle`), not in a
  per-project tree, so projects, profiles and worktrees do not each keep a
  copy.
- **Content-addressed and deduplicated.** Blobs are named by the SHA-256 of
  their bytes; entries (key to blob) are ~100-byte files. Different keys that
  yield identical bytes (for example a feature that changes no code) share one
  blob. Blobs are read-only; outputs are private copies, never links into the
  store.
- **No incidental data.** Only final executables/objects and tiny build-script
  records are stored; there are no per-crate metadata, dependency-info,
  incremental or debug side trees. Comment and layout edits reuse the existing
  entry instead of adding one.
- **Bounded.** After every publication the store applies a byte budget
  (default 512 MiB, `--cache-limit-kib`) and an age limit (default 30 days,
  `--cache-max-age-days`): entries unused longest are evicted first, the entry
  just published last, then blobs without references and stale scratch files
  are removed. Each eviction is reported with `--explain` and its reason.
- **Verified and atomic.** Writes go to `tmp/` and are published by rename; a
  hit re-hashes the blob and a mismatch deletes the entry and blob and
  rebuilds (`entry corrupt`).
- **Clear removal.** `mettle clean` deletes only the store's own directories
  and refuses a directory lacking its `VERSION` marker; `--dry-run` reports
  the entries, blobs and bytes; `mettle clean PACKAGE` also removes that
  package's `target/mettle` build-script outputs.

Accounting uses logical file sizes; allocated bytes are at least as large, so
the gate comparison must use allocated bytes per the definition above.
The driver leases its active whole-build key; pruning preserves leased entries
and `clean` refuses live leases.

For eligible debug executable builds, dependency objects contain only
non-generic, owner-unambiguous package functions and statics. Generic instances,
synthesized helpers, ambiguous ownership and the executable wrapper stay in the
root object, and cross-object references use stable package-instance symbols.
Release, non-executable, debug-info, sanitizer, harness, freestanding,
package-context, global-assembly and uncertain/generated-input builds use the
single-object path. Package keys include exact source checksums, resolved
dependency object keys, compiler identity, target, profile, features and codegen
options. Artifacts are staged and hashed outside the store lock and published in
one batch per build; concurrent pruning can only cause a safe miss, and corrupt
blobs are rebuilt. Parsing and later front-end phases still run whole-program;
retained-byte and compile-time advantages require measurement.

### 5.2. Compiler-work regression guard

In addition, guard the compiler's own work with retired user instructions on a
qualified, fixed runner, recording event, tool, process/child scope and
multiplexing policy. Require a revised/baseline median instruction ratio of at
most **1.05** per representative workload, cold and warm separately, with
repeatability established first. An unavailable or unreliable counter leaves this
guard incomplete; no unqualified substitute is allowed.

For generated suffix, projection and builder families at N, 2N, 4N and 8N, require
successive instruction growth of at most **2.2x** after fixed setup is amortized,
and record parser visits and solver constraint steps to locate repeated work.
Include the two exhibit programs of implementation-plan section 8.7 and
generic-heavy code. These budgets are regression guards on top of, not
substitutes for, the section 5.1 gate. Wall time, RSS, code size and
allocations remain reported; no hard 5% elapsed-time gate applies on a loaded
development machine.

### 5.3. D17 comparison harness

`tools/bench_compare.py` builds each paired workload from `benchmarks/<name>/`
(Mettle `main.mt` and Rust `Cargo.toml`/`src/main.rs`) with
`mettle build --profile release --overflow-checks off --cache-dir <fresh>` and
`cargo build --release --offline` (fresh `CARGO_TARGET_DIR` and `CARGO_HOME`, no
dependencies, `CARGO_INCREMENTAL=0`). Options and output format are documented
by the tool's `--help`. Workloads cover the P01-P06 subsets the compiler
supports; P07-P12 are added when comparable. Programs return a 7-bit checksum
as exit status; the harness requires equal status and stdout from both
languages for the clean and the semantically edited build.

Rust profile: `opt-level=3`, `debug=false`, `lto=false`, `codegen-units=16`,
`panic=abort`, `overflow-checks=false`, `incremental=false`, edition 2024, host
`target-cpu`. Per workload and repetition (randomized order) it records wall
time of a clean build, a no-op rebuild, a comment-only edit, a semantic edit
and check-only; compiler peak RSS; binary size; and allocated bytes
(`st_blocks`) after the clean build and the edit sequence. Mettle's retained
bytes are its cache store plus package-local `target/mettle` plus the output
executable; Cargo's are the whole `target/`. Time endpoints use section 4
(paired log ratios, Student-t, alpha = 0.05/K for K = workloads x six time
endpoints); runtime passes on a win or a precise tie, compile-time metrics need
a win; byte metrics compare medians and require stability within one percent.
Without a qualified runner, 30 pairs and the frozen Rust toolchain the report is
an engineering signal only. The section 5.2 instruction counters are not
collected by this harness.

### 5.4. Debug-build compile-time work

Debug object emission uses `CodeGenOptLevel::None` and does not run LLVM's
per-module O2 pipeline; the compiler does not select FastISel or GlobalISel, and
sanitizer instrumentation still runs in debug emission. Selector changes need
measured evidence across supported targets. Every symbolic body, including
unused declarations, must still be checked.

### 5.5. Front-end work items from the 2026-11-14 profile (I14)

Pilot measurements (WSL2, loaded machine, indicative only; repeat under the
section 5.1 protocol before claiming a result). A program importing only
`std.io`, no build cache, took about 21 s in the front end; importing `core`
only, about 7 s; an empty program, about 2 s. With the checked-library cache
warm, a small test builds in about 2.4 s. Stack sampling of the 21 s case (ten
interrupted runs, one per 2 s mark; proportions are approximate) showed, in
order: SHA-256 hashing of the library sources and archive preparation (first
~6 s), interface-implementation coherence over the whole library
(`Solver::coherent`, ~6-10 s), IR verification (~12 s), and borrow/loan
analysis (`analysis::loans`, ~14-16 s). LLVM codegen and linking added about
0-4 s. The library does not change between builds, yet each pass re-runs over
it. These are I14 compile-time gate candidates, not V1 behavior changes; each
must keep every symbolic body checked (section 5.4).

| Item | Work | Acceptance |
| --- | --- | --- |
| I14-C1 | Library input hashing: stop re-reading and software-hashing the whole library per invocation. Keep the cache-key semantics (library contents, path, compiler identity and the flags in `library_cache.cpp`) but obtain the content identity from a size/mtime-validated manifest and use hardware SHA where available. | Same keys for same inputs; changed content still invalidates; cold and warm wall time before/after |
| I14-C2 | Coherence: store the library-only coherence result in the checked-library archive; per build check only the program's implementations against the library and each other. | Identical diagnostics on overlap, orphan and conflicting-implementation fixtures; wall-time delta |
| I14-C3 | IR verification and loan/origin analysis of library functions: record the verified/analyzed result in the archive keyed by library contents and reuse it, instead of re-running per build. Do not skip any body. | Same diagnostics and unwind/cleanup behavior; wall-time and peak-RSS delta |

Record raw before/after results in the I14 evidence bundle; a faster result
does not offset a regression in retained cache bytes (section 5.1).

## 6. V1 / V1.1 / V1.2 evidence

V1 requires the audited capability denominator, supported-profile probes, semantic
corpus, tooling workflows, and the runtime, compile-time and build-storage gates. Publish known limitations without
reclassifying missing promised capabilities as completed.

V1.1 additionally requires a substantive self-hosted compiler, repeatable staged
bootstrap, and comparisons against V1. V1.2 additionally requires an LLVM-free
production backend path for every accepted profile/capability without hidden
fallback, plus runtime comparisons against both Rust and the LLVM path.

Neither byte-identical bootstrap artifacts nor differential execution alone
proves correctness. Record shared frontend assumptions and independent tests.
