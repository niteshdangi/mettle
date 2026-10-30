# Adoption rationale: start with a blocked task

Status: evidence-backed problem analysis. This document does not select the
language identity; the owner-accepted identity (readability, runtime parity,
faster compilation, smaller build storage) is decision D16-D17 in
[decisions.md](decisions.md), and a problem-led adoption case remains separate.
This replaces feature-first positioning as the discovery method. No additional
language capability or release commitment is approved by this document.

## 1. The question

What expensive task can a specific group not perform satisfactorily with an
existing language and its ecosystem, and which language-design decision prevents
an adequate solution?

A real problem is necessary but insufficient. Build delays, orchestration, GPU
execution and verification can be real problems while still being better
addressed within an existing language. A slogan is not an adoption argument.

## 2. Evidence examined

### E1. State of Rust 2025, published March 2, 2026

The official report describes 7,156 completed responses and cautions against
overgeneralization. Compilation/storage resource use remain prominent problems;
generic const expressions and improved trait methods are among requested
features. Concern about growing complexity persists.

This supports concrete developer friction, not a conclusion that respondents
will abandon Rust or that a new compiler will fix it. Existing Rust development
is also addressing these problems.

Source: https://blog.rust-lang.org/2026/03/02/2025-State-Of-Rust-Survey-results/

### E2. Google's Rust adoption study, published June 2023

The study concerns Google engineers using Rust in 2022, not the entire developer
population or the current compiler. It reports build speed as the leading
challenge and identifies macros, ownership/borrowing, and async as challenging
areas. It also reports favorable diagnostics and productivity experiences.

This is counterevidence to a simplistic "Rust is unusably hard" premise. C++
interop was not the top reported difficulty among these existing adopters.
Adopter experiences and barriers preventing adoption are different populations.

Source: https://opensource.googleblog.com/2023/06/rust-fact-vs-fiction-5-insights-from-googles-rust-journey-2022.html

### E3. Native-platform integration requirements

Google's Android interop account identifies using Rust inside an existing native
codebase as an integration challenge. Carbon explicitly targets incremental
adoption and migration of existing C++ software through bidirectional interop.

These establish a concrete task: introducing safer implementation code while
retaining existing callers, dependencies, and operational behavior. They do not
establish that Mettle would outperform the existing alternatives.

Sources:
- https://security.googleblog.com/2021/06/rustc-interop-in-android-platform.html
- https://github.com/carbon-language/carbon-lang/blob/trunk/docs/project/goals.md

### E4. Current alternatives must be taken seriously

Crubit's documentation describes bidirectional binding generation directly from
C++ headers and Rust crates, idiomatic type mappings, lifetime annotations, and
multiple build integrations with direction-specific support. Its status is not
"Rust needs handwritten C wrappers for everything."

Carbon already treats migration as a language-design goal, not just a library.
Mettle cannot claim this problem is unoccupied or name compatibility itself as
an invention.

Sources:
- https://crubit.rs/
- https://github.com/carbon-language/carbon-lang/blob/trunk/docs/project/goals.md

## 3. Candidate screening

| Problem | Existing route | New-language justification |
| --- | --- | --- |
| Rust build/debug friction | Compiler and tooling improvements | Weak by itself as an adoption case; compile time and build storage are nevertheless accepted gates (D17) |
| Difficult ownership/macros/async | Rust evolution and alternative semantics | Requires substantial semantic benefit, not punctuation changes |
| Surviving backend failures | Durable execution frameworks | Does not alone require a language |
| CPU/GPU application boundary | Existing accelerator languages and bindings | Needs concrete unsupported workloads and evidence, not generic portability claims |
| Verifying algorithmic contracts | Dafny and Rust verification tools such as Verus | Real category, but no established Mettle advantage; user rejected this identity |
| Incrementally replacing native components | Rust with CXX/Crubit, Carbon, C++ evolution | Strong concrete adoption task; still requires a demonstrated gap |

## 4. Recommended problem to investigate

Target a maintainer of existing C++ software who wants to implement new or
replacement components with stronger safety without first rewriting the host
application, redesigning its public APIs, or maintaining a second incompatible
data model.

The task is not "make C++ fast" or "make Rust syntax nicer." It is:

> Replace one production component with safer code while keeping the rest of the
> product working and preserving performance and integration contracts.

This is the strongest problem-led candidate from this pass because its adoption
boundary is observable. It is not the identity selected in D16, nor a claim
that existing solutions fail it.

Happy Rust users need not be the first audience. Teams blocked from using safer
native implementations may have a stronger reason to adopt something new.
That is an inference to validate, not a market finding.

## 5. The library-versus-language test

For each observed obstruction, classify the cause:

- Missing generated binding or build integration: improve an existing tool.
- Missing convenience wrapper: improve a library.
- Missing diagnostic or documentation: improve tooling/documentation.
- A type, lifetime, object-motion, exception, or generic-instantiation mismatch:
  investigate whether an existing language can express the necessary safe
  contract. A native importer might help, but cannot infer arbitrary C++ safety.

A new language is justified only if an important, repeatable obstruction remains
and a different language contract solves it without unacceptable new costs.
Rebranding a binding generator as a language fails this test.

Do not promise safe arbitrary C++, zero-copy every boundary, automatic ownership
inference for unknown foreign code, or compiler-independent C++ ABI stability.
Each would hide precisely the difficulty being investigated.

## 6. Concrete comparison packet

Prepare three representative component contracts before expanding syntax:

1. A value-oriented library using templates, overloads, and standard containers.
2. A callback/lifecycle component with ownership transfer, retained callbacks,
   and destruction-sensitive behavior.
3. A stateful object interface with borrowed views, mutations that invalidate
   them, and an error/exception boundary.

For each, write the real signatures, caller behavior, lifetime constraints,
failure paths, ABI/build dependencies, and intended replacement boundary.
Compare Rust+CXX, Rust+Crubit, Carbon's documented design/available implementation,
and a proposed Mettle mapping. Distinguish implemented support from roadmaps.

Record:

- Changes required in callers and dependencies.
- Handwritten adapters and contracts.
- Unsafe/trusted boundaries and what they assume.
- Copies, allocations, ownership operations, and error translation.
- Source/binary compatibility limits and compiler/build coupling.
- Remaining semantic cases that cannot be expressed safely.

No invented migration-hour estimate or interview quote is acceptable.
Documentation analysis can establish missing documented contracts; executable
probes and real maintainer feedback are needed to establish operational effort.
The user has required documentation first, so no compiler prototype is started.

## 7. First concrete boundary check

Consider a foreign function returning a view of either of two inputs:

```text
const int& smaller(const int& a, const int& b);
```

Crubit's documented behavior when elision cannot determine the relationship is
to expose a raw pointer; explicit foreign lifetime annotations can express the
relationship and produce a lifetime-bearing reference wrapper. Its documentation
also warns that incorrectly inferred foreign lifetimes are not checked against
the C++ body.

Mettle's proposed `from (a, b)` spelling expresses the relationship, but this is
not a capability advantage over an annotated Rust binding. The annotation still
needs evidence that the foreign implementation obeys it.

Second, a C++ const reference does not guarantee Rust-style absence of mutation,
and a mutable C++ reference does not guarantee exclusivity. Crubit uses CRef/CMut
wrappers to preserve that distinction. Mettle cannot safely import either as its
ordinary read/exclusive reference simply to improve ergonomics.

Third, CXX deliberately supports a restricted boundary with shared structs,
opaque objects, and functions rather than arbitrary signatures. Crubit provides
broader generation and documented limitations. "Eliminate handwritten wrappers"
alone is therefore not an unmet language-level capability.

Result: these first checked cases establish real integration work, but do not
yet establish a unique Mettle solution. A credible migration-first design must
show a specific safe contract or object model that the existing tools cannot
adequately express, not merely spell their annotations differently.

Sources:
- https://crubit.rs/cpp/references_and_lifetimes
- https://crubit.rs/overview/status
- https://cxx.rs/concepts.html

## 8. Effect on the current blueprint

The existing blueprint prioritizes native Rust-level capabilities with C interop
and optional Rust bridges; high-fidelity C++ migration is a material new direction.
Do not quietly add it to V1 or let a C++ compatibility frontend become mandatory
for ordinary native projects.

If this direction proves useful and is accepted, explicitly revise the scope,
type/ABI boundaries, toolchain dependency policy, and release evidence.
If the identified work is only a missing binding feature, solve it there rather
than pretending it justifies another language.

The immediate outcome is a concrete adoption problem and a falsifiable comparison
plan. It is deliberately not another claim that a language identity has been
discovered merely by naming a field.
