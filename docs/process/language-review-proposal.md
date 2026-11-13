# Language review proposal: remaining Rust-shaped areas

Scope: areas not already covered by the in-flight changes (`package.*` anchor,
`pub(path)`, raw text, Box/Rc/Arc/Cell/RefCell and or_panic/expect/as_ref renames).
Basis: D16 ("Mettle must not read like a Rust copy") and `i13-library.md`.

Counting method: `grep -Eoh` occurrences in `*.mt` under `library/`, `tests/`,
`examples/` (`.claude/worktrees` and `build/` excluded); "docs" is `*.md` under
`docs/`. Diagnostics are unique string literals in `bootstrap/**/*.cpp`
(excluding `lsp/`). "Fixtures" are `expect-error:` files under `tests/`
(823 total). Every count is a grep count, not a semantic count; migration costs
are estimates. Compiler edits stay inside the AGENTS.md rule for V1 experience
work (D16, implementation-plan 8.7) and need owner approval before starting.

## Summary

| # | Area | Verdict | Why | Cost |
| --- | --- | --- | --- | --- |
| 1a | Wrapper macros `println!`, `eprintln!`, `format!`, `format_args!`, `todo!`, `unimplemented!`, `assert_eq!`, `assert_ne!` | CHANGE | Already thin wrappers over `format` parameters and functions; `format_args!` is the identity; macros here add only Rust spelling | Small: 8 `macro` defs in `library/std/macros.mt`, about 40 call sites in tests/library |
| 1b | Declarative `macro` definition syntax (`$x:expr`, `=> { }`) | DEFER | It is `macro_rules` in shape, but replacing it is a macro-system design, not a rename | 180 fragment uses, 123 `macro` defs; post-V1 |
| 1c | `name!(...)` invocation marker, `@attr`, `@derive`, `macros {}` manifest block, hygiene | KEEP | Marker separates expansion from calls; `@` and manifest block are native; `@derive` has 1 library use | none |
| 2a | `where` clauses, bounds, const generics, `region r` generics | KEEP | Consistent with `extend`/interface forms; `T: unsized` is a native inversion of `?Sized` | none |
| 2b | `?Sized` alias accepted by the compiler | CHANGE | Undocumented Rust spelling, 0 uses in library/tests/docs/spec | 4 sites in `bootstrap/semantics/generics.cpp` |
| 2c | `for<r>` higher-ranked bounds | DEFER | Rust-shaped but rare (19 library, 24 tests) and needed; revisit with 1b | low |
| 3 | Operator interfaces (`Add`, `Index`, `Deref`...) via `extend X implements Add<Y>` | KEEP | Universal vocabulary; declaration form is already native | none |
| 3b | `PartialEq`/`PartialOrd` | DEFER | Rust-only partial/total split; belongs to the naming proposal | 368+226 library, 177+110 tests |
| 4 | `as` casts, `0usize` suffixes, `wrapping_/checked_/saturating_/overflowing_` | KEEP | `as` is C-family, not Rust-specific; suffix and overflow names are descriptive and profile table is native | none |
| 5 | Patterns, `match`, `if let`, `let else`, `n @ p` | KEEP | `match mut/take`, `present/none/success/failure` are native; remaining forms are common | none |
| 6 | `panic`, `assert(cond, message)`, `unreachable`, `Outcome` | KEEP | Functions, not macros; mandatory message; `Outcome` plus `success/failure` is native | none |
| 6b | `todo`/`unimplemented` | CHANGE (with 1a) | Become functions; `unreachable()` already is one | included in 1a |
| 7 | `package.mettle`, `lock.mettle`, `build.mt`, `macros {}` | KEEP | Native data format, no TOML, explicit script/entry keys | none |
| 7b | Directory module root: `module.mt` vs `name/main.mt` | CHANGE | Two names for one concept; `name/main.mt` import discovery is used by 0 fixtures | Small, see below |
| 7c | Library default entry `src/main.mt` | CHANGE (optional) | "main" for a library is misleading; `src/module.mt` fits 7b | 43 `src/main.mt` files, most executables |
| 8 | Diagnostics vocabulary | CHANGE (partial) | `trait`/`crate`/`Option`/`Result`/`Some`/`None`: 0 hits, already clean. "borrow(ed)" (35 strings) and "Sized" (18 strings) are the Rust-shaped terms | Medium, see below |

## 1. Macros and attributes

Facts: public std macros are `vec`, `matches`, `dbg`, `format`, `format_args`,
`println`, `eprintln`, `assert_eq`, `assert_ne`, `todo`, `unimplemented`
(`library/std/macros.mt`, `library/alloc/vec.mt`). Invocation counts in
`library/` + `tests/`: `asm!` 68, `format_args!` 9, `vec!` 7, `matches!` 6,
`eprintln!` 6, `println!` 5, `dbg!` 5, `todo!` 4, `assert_eq!` 4,
`unimplemented!` 3, `format!` 3, `assert_ne!` 3. Docs: 4 lines mention them.
Library-internal macros (40 definitions, mostly integer-width fan-out in
`core/num.mt`) are an implementation tool and not user surface.

1a CHANGE. `println`, `eprintln`, `format` expand to `print_line`,
`eprint_line`, `format_message`, which already take `format fmt.Message`
(D23) and accept f-strings. `format_args` expands to its argument. The macros
buy only the `!` spelling. Proposal: expose the real functions under the short
names (`println(f"x = {x}")`, `eprintln`, a string-building function), delete
`format_args`, make `todo`/`unimplemented` functions (`unreachable()` is already
one) and `assert_eq`/`assert_ne` functions (`read` parameters already avoid
moves, `assert_values` already does the work). Conflict risk: a function named
`format` collides visually with the `format` parameter kind (contextual
keyword); choose another name or verify the parser first. Hosted names are not
in the prelude, so they are imported from `std.io` like any function.
Cost estimate: about 40 call sites plus 8 macro definitions and 4 doc lines.

Keep as macros: `vec`, `matches` (take patterns or variadic syntax), `dbg`,
`asm!`. A native replacement for `matches!` and `vec!` (an `is` pattern test,
list literal) would be new syntax and is DEFER, not in the current docs.

1b DEFER. The matcher/expansion grammar in advanced-contracts section 5 and
specification-annex section 4 is `macro_rules` with `$name:fragment`. It is
sound and specified (hygiene, follow sets, `$capture`), so changing it only for
looks would be churn; a native design is a post-V1 item.

1c KEEP. Procedural macros are declared in a `macros { }` manifest block with a
versioned line protocol (tooling-and-packages L056); attribute and derive
macros are explicitly unsupported today, so no spelling is frozen.

## 2. Generics, bounds, `unsized`, const generics, `for<region>`

2a KEEP. Generic lists reuse `region r` and `const N: T`; bounds join with `+`;
callable bounds reuse closure types (`F: fn(i32): i32`); `T: unsized` reads as
a permission and replaces `?Sized`. `where` appears 97 times in library and 64
in tests, always after the result type, with the same constraint grammar.

2b CHANGE. `bootstrap/semantics/generics.cpp` still accepts `?Sized` (4
comparisons, lines 35, 45, 198, 755). It is not in the grammar, library, tests or
spec (only a catalog mapping row in library-surface T13). Remove it so the
language has one spelling. Risk: none found by grep; confirm no parser path
produces the token.

2c DEFER. `for<r>` is HRTB shape. Keep until the region model is revisited.

## 3. Operator interfaces

`library/core/ops.mt` declares `Add`..`Shr`, the `*Assign` forms, `Neg`, `Not`,
`Index`, `IndexMut`, `Deref`, `DerefMut`. Implementations are
`extend X implements Add<Y> { type Output; fn add(read rhs: Y): ... }`
(195 `extend ... implements` operator lines in library, 25 in tests; 386 and 35
by the broader `implements` pattern). KEEP: names are the shared vocabulary of
systems languages, and `Send`/`Sync` are already native
(`Transferable`/`Shareable`). The only Rust-only vocabulary here is
`PartialEq`/`PartialOrd`: DEFER to the naming proposal (prelude section 9 keeps
them explicitly).

## 4. Casts, literals, overflow

`as` appears 250 times in library and 82 in tests as a numeric cast. Narrowing
truncates by definition (semantic-rules section 3). KEEP: `as` is also C#,
Swift, Kotlin and TypeScript vocabulary, and a distinct truncation spelling is
a semantic change with no accepted evidence. Literal suffixes (`0usize`) occur
3,908 times in library and 77,171 in tests; not required by the spec after
literal inference, so this is style, not language. Overflow names
(`wrapping_*` 309/2,611, `checked_*` 91/3,238, `saturating_*` 17/1,253,
`overflowing_*` 0/5,038 in library/tests) are descriptive; the checks-on/off
table and `--overflow-checks` are Mettle's own. KEEP.

## 5. Patterns and match

`match [mut|take]`, `present(p)`, `none`, `success(p)`, `failure(p)`, qualified
variants, `|`, guards, `..=`. `if let`/`while let` occur 31 times and
`name @ pattern` 7 times in library+tests; `match mut|take` 492 times in
library. KEEP. A native `value is pattern` test would replace `if let` and
`matches!` together, but it is new syntax: DEFER with 1b.

## 6. Error handling

`panic(read message: Text): Never`, `assert(condition, read message)`,
`unreachable()` are functions (`library/core/panic.mt`; 171 and 1 library uses,
25,159 and 829 test uses). `Outcome<T, E>` with `success/failure` and
`throws/try/capture` is native. KEEP. Only `todo`/`unimplemented` are macros
(see 1a).

## 7. Module and manifest layout

KEEP `package.mettle`, `lock.mettle`, `build.mt` (named by `build { script }`),
`.mt`, `macros/*.mt` via manifest.

7b CHANGE. A directory module root has two names. `module name` loads
`name.mt` or `name/module.mt` (`bootstrap/resolution/load.cpp` lines 776, 1557);
an undeclared import loads `name.mt` or `name/main.mt` (same file, lines 776 and
1416; spec: language-grammar section 2, tooling section 2 line 324). Usage:
`module.mt` 6 files (library core/alloc/std/std.sync, 2 test dirs); `main.mt`
43 `src/main.mt` package entries plus 1 other file (a test fixture, not an import
case). `tests/modules.py` uses `main.mt` as the entry of generated test
packages, not as a discovered module. Proposal: one name, `module.mt`, for
both paths; spec edit in 2 places, loader edit in 2 sites, a regression
test for the ambiguity diagnostic if one exists for `name/main.mt`. Risk: none
for library; external packages are out of scope in this pre-1.0 repository.

7c CHANGE (optional, depends on 7b). Libraries default to `src/main.mt`
(`bootstrap/packages/manifest.cpp` 313, 373) and the spec states that default
covers both libraries and executables. With `module.mt` as the module-root
name, a library entry `src/module.mt` and executable entry `src/main.mt` are
distinct and self-describing. Cost: manifest defaults plus any library test
package relying on the default (43 `src/main.mt` files include executables, so
only library fixtures move; count not measured).

## 8. Diagnostics vocabulary

Spec terms are view, loan, region, interface, package, `extend`. Measured in
unique diagnostic strings (non-LSP): `trait` 0, `crate` 0, `Option`/`Result`
words in messages are API names not Rust terms, `lifetime` 1 ("access or
storage lifetime conflicts with a live ..."), `impl` 2 (internal `<impl.` tags),
`borrow`/`borrowed`/`borrows` 35, `Sized` 18 (13 are messages such as
"generic argument does not satisfy Sized"; the rest tag internal paths), `mutable`
21 (acceptable: `mut` is the keyword), `exclusive borrow` 3.

CHANGE (partial). Rewrite user-facing messages that say "borrowed
place/receiver/result" to view/loan wording ("cannot move out of a viewed place",
"mut view requires a mutable place"), and the lifetime string to loan/region
wording. KEEP "Sized": `Sized` is the real name of the default property
(`Clone: Sized` in 25 library lines) and `unsized` is its opt-out. Fixtures:
38 `expect-error:` files mention "borrow", 4 "Sized", 16 "mutabl", so about 40
fixture lines change (the matcher is a substring); docs use "borrow" 309 times
(spec 91, library 177, process 41) and D04 itself says "Static borrowing", so
a docs-wide rewrite is not recommended; adopt the wording only for diagnostics
and new docs, and decide D04's wording separately. Risk: renamed strings in
`bootstrap/ir` and `lowering` that tests match exactly; run only the affected
fail fixtures.

## Recommended order

1. 2b and 7b (smallest, no wording debates, remove duplicate spellings).
2. 1a (std macros to functions, plus doc lines), after checking the `format`
   name collision.
3. 8 (diagnostic wording for borrow/lifetime, then the roughly 40 fixtures).
4. 7c (library default entry) only if 7b lands.
5. DEFER list: 1b, 2c, 3b, `is` pattern test, `vec!`/`matches!` replacements.
