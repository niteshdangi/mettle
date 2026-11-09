# Adoption rationale: start with a blocked task

Status: problem analysis, not an additional language/release commitment.
The accepted identity is readability, runtime parity, faster compilation and
smaller build storage ([decisions.md](decisions.md) D16-D17). A problem-led
adoption case is separate.

## 1. The question

Which costly task is inadequately served by existing languages and ecosystems,
and which language contract causes that obstruction? A real problem justifies a
new language only if tooling or libraries cannot adequately solve it.

## 2. Evidence examined

### E1. State of Rust 2025, published March 2, 2026

The 7,156-response survey reports compilation/storage friction, demand for
generic const expressions and improved trait methods, and complexity concerns.
It cautions against overgeneralization; this is not evidence of willingness to
switch or that Rust's ongoing improvements will fail.

Source: https://blog.rust-lang.org/2026/03/02/2025-State-Of-Rust-Survey-results/

### E2. Google's Rust adoption study, published June 2023

Google's 2022 adopters reported build speed as the leading challenge and
ownership, macros and async as difficult, alongside favorable diagnostics and
productivity. C++ interop was not their leading difficulty. Existing adopters
are not the population blocked from adoption.

Source: https://opensource.googleblog.com/2023/06/rust-fact-vs-fiction-5-insights-from-googles-rust-journey-2022.html

### E3. Native-platform integration requirements

Android's Rust interop work and Carbon's incremental C++ migration goal establish
the task of adding safer code while preserving existing callers, dependencies
and behavior, not an advantage for Mettle.

Sources:
- https://security.googleblog.com/2021/06/rustc-interop-in-android-platform.html
- https://github.com/carbon-language/carbon-lang/blob/trunk/docs/project/goals.md

### E4. Current alternatives must be taken seriously

Crubit generates bidirectional bindings from C++ headers/Rust crates with type
mappings, lifetime annotations and direction-specific build support. Carbon
already makes migration a language goal; handwritten C wrappers are not Rust's
only route.

Source: https://crubit.rs/

## 3. Candidate screening

| Problem | Existing route | New-language justification |
| --- | --- | --- |
| Rust build/debug friction | Compiler/tooling improvements | Weak alone; compile time/storage remain accepted D17 gates |
| Ownership/macros/async difficulty | Rust evolution, alternative semantics | Needs substantial semantic benefit, not punctuation |
| Backend failures | Durable execution frameworks | Does not alone require a language |
| CPU/GPU boundary | Accelerator languages/bindings | Needs concrete unsupported workloads |
| Algorithmic verification | Dafny, Verus | No demonstrated advantage; identity rejected |
| Incremental native replacement | CXX/Crubit, Carbon, C++ evolution | Observable adoption task; requires a demonstrated gap |

## 4. Recommended problem to investigate

Replace one production C++ component with safer code while preserving callers,
data models, performance and integration contracts. Maintainers blocked from
safer native implementations are a candidate audience, not validated demand.
This research candidate is not the identity selected in D16.

## 5. The library-versus-language test

Missing bindings/build integration, wrappers or diagnostics call for existing
tool/library improvements. Repeatable type, lifetime, motion, exception or
generic-instantiation mismatches warrant investigating a different safe contract.
A native importer cannot infer arbitrary C++ safety.

Require a contract existing languages cannot adequately express without
unacceptable costs. Do not promise safe arbitrary C++, universally zero-copy
boundaries, inferred foreign ownership or compiler-independent C++ ABI stability.

## 6. Concrete comparison packet

Compare three real component boundaries: templates/overloads/containers;
ownership-transferring retained callbacks/destruction; and stateful borrowed
views with invalidation and error/exception paths.

For each, record signatures, callers, lifetimes, failures and ABI/build
dependencies. Compare Rust+CXX, Rust+Crubit, Carbon and proposed Mettle mappings,
distinguishing implementation from roadmap. Measure caller/dependency changes,
handwritten adapters, unsafe/trusted assumptions, copies/allocations/ownership
operations, error translation, compatibility/build coupling and inexpressible
safe cases.

The adoption criterion is a repeatable obstruction solved with fewer changes or
adapters under equivalent safety, compatibility and runtime contracts. Document
analysis identifies gaps; executable probes and maintainer feedback establish
operational effort. Do not invent migration times or interview evidence.
Documentation precedes any prototype.

## 7. First concrete boundary check

For `const int& smaller(const int& a, const int& b)`, Crubit uses a raw pointer
when lifetime elision cannot determine the relationship; explicit annotations
can produce a lifetime-bearing wrapper. Mettle's `from (a, b)` is therefore not
a new capability. Foreign annotations still need implementation evidence;
Crubit does not check inferred lifetimes against C++ bodies.

C++ const/mutable references do not guarantee Mettle/Rust freeze/exclusivity.
Crubit's CRef/CMut preserve that distinction; importing them as ordinary Mettle
read/exclusive views would be unsound. CXX deliberately limits its boundary to
shared structs, opaque objects and functions; Crubit offers broader generation
with documented limits. Removing handwritten wrappers alone establishes no
unmet language capability. These checks show integration work, not yet a unique
Mettle solution.

Sources:
- https://crubit.rs/cpp/references_and_lifetimes
- https://crubit.rs/overview/status
- https://cxx.rs/concepts.html

## 8. Effect on the current blueprint

High-fidelity C++ migration is new scope beyond native Rust-level capabilities,
C interop and optional Rust bridges. Acceptance would require explicit changes
to scope, type/ABI boundaries, toolchain policy and release evidence. A C++
frontend must not silently become mandatory for ordinary native projects.
