# Performance and release protocol

## 1. Accepted requirement

Runtime must match or beat the frozen Rust baseline on each agreed representative
workload. Compilation time, peak compiler/program memory, allocation counts, and
binary size are measured separately; they do not have an accepted equality gate.
Do not hide unacceptable resource growth simply because runtime passes.

The former 10-percent slowdown investigation threshold is superseded. A win on
one workload does not compensate for a credible slowdown on another.
This is a corpus-based release requirement, not a theorem about all programs.

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
They are not the two-session pilot, confidence/precision experiment or a runtime
parity verdict. The actual Rust comparator version is recorded; a mismatch with
the frozen 1.99.1 baseline cannot qualify the release comparison.

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
binary/debug-info size, and bootstrap stages.

Do not conflate compiler execution speed with the speed of code it produces.
Additional optimization may improve application runtime while increasing build
time. Self-hosting and backend ownership are architectural goals, not expected
automatic speedups.

## 6. V1 / V1.1 / V1.2 evidence

V1 requires the audited capability denominator, supported-profile probes, semantic
corpus, tooling workflows, and runtime gate. Publish known limitations without
reclassifying missing promised capabilities as completed.

V1.1 additionally requires a substantive self-hosted compiler, repeatable staged
bootstrap, and comparisons against V1. V1.2 additionally requires an LLVM-free
production backend path for every accepted profile/capability without hidden
fallback, plus runtime comparisons against both Rust and the LLVM path.

Neither byte-identical bootstrap artifacts nor differential execution alone
proves correctness. Record shared frontend assumptions and independent tests.
