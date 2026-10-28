# Mettle language grammar: extended specification

Status: documentation draft selected under routine delegation. This extends
`core-grammar.md`; it does not claim an implemented or conflict-free parser.
Explicitly unapproved identity proposals are not part of this grammar.

The core grammar is a subset, not a second dialect. Where this document extends
a rule, its additional alternatives apply to the same syntax. A statement that
the initial subset lacks a construct describes implementation sequencing only.

## 1. Lexical completion

Use UTF-8 input; reject invalid encoding before tokenization. Full identifiers
use Unicode XID_Start/XID_Continue with underscore permitted, normalized to NFC
for identity. Preserve original bytes for source locations and diagnostics.
Use Unicode 16.0.0 XID and normalization data as the initial lexical baseline;
changing it is a documented language-version change. Backtick-delimited identifiers allow reserved words; their
contents must otherwise be a valid identifier, with no embedded backtick.

Line comments, nested block comments, and newline/tail rules follow the core.
A brace-delimited statement block restores statement-newline processing even
inside an enclosing parenthesized expression. Newlines inside array literals,
argument lists and generic lists are suppressed except inside nested blocks.

Integer literals add `0b`, `0o`, and `0x` bases. Separators may occur only between
digits. Suffixes must be separated unambiguously from digits in the chosen base.
Floating literals use decimal fractional/exponent forms with optional f32/f64
suffix; require digits on both sides of a decimal point. Thus `1..3` is a range,
not a float. Unary minus remains separate. Literal range checking uses the
contextual type; the signed-minimum literal case is handled before rejection.

Text uses `"..."`; scalar characters use `'...'`; byte text/scalars use a `b`
prefix. Escapes: backslash, matching quote, n, r, t, 0, and Unicode scalar
`\\u{hex}` in Unicode literals; byte escapes use `\\xHH`. Byte scalar literals
must produce one byte; character literals exactly one valid scalar.
Raw text uses `r"..."` or matched hash fences `r#"..."#`; raw byte text uses `br`.
Interpolated text uses `f"..."`, with `{ expression }` holes and doubled braces
for literal braces. Raw and interpolation combinations are reserved until
specified, not silently concatenated.

Reserve the additional keywords used below. Unsupported reserved constructs
produce a feature-not-implemented diagnostic, not reinterpretation as identifiers.
Documentation comments are `///` and `//!` attached to the following item and
enclosing module respectively.

## 2. Paths, imports and generics

```ebnf
path          = path_head, { "::", IDENT } ;
path_head     = IDENT | "self" | "super" | "package" ;
visibility    = "pub", [ "(", path, ")" ] ;
module        = [ visibility ], "module", IDENT, ( ";" | "{", items, "}" ) ;
import        = [ visibility ], "import", path,
                [ ( "as", IDENT ) | ( "::", "{", import_names, "}" )
                  | ( "::", "*" ) ], ";" ;
import_names  = IDENT, [ "as", IDENT ],
                { ",", IDENT, [ "as", IDENT ] }, [ "," ] ;
generic       = IDENT, [ ":", bounds ], [ "=", type ]
              | "region", IDENT
              | "const", IDENT, ":", type, [ "=", const_expression ] ;
bounds        = bound, { "+", bound } ;
bound         = [ "for", "<", region_list, ">" ], path, [ generic_args ]
              | "unsized" ;
generic_args  = "<", generic_arg, { ",", generic_arg }, [ "," ], ">" ;
generic_arg   = type | "region", region_reference
              | "const", "{", expression, "}"
              | "type", IDENT, "=", type
              | "const", IDENT, "=", const_expression ;
region_reference = IDENT | "static" ;
where_clause  = "where", constraint, { ",", constraint } ;
constraint    = type, ":", bounds
              | type, "=", type
              | "region", IDENT, ":", region_reference ;
```

In item-level declarations, newline separation may replace the terminating
semicolon under the core separator rule. `pub import` reexports rather than
creating a second module identity. Visibility is module-private by default;
restricted `pub(path)` names an enclosing module boundary.

Name resolution uses distinct type, value and macro namespaces. Reject ambiguous
imports; import order cannot change implementation selection. Dependency package
identity is provided by the resolver, not merely a source spelling.
An external `module name;` loads exactly one of `name.mt` or `name/module.mt`
relative to its containing module's directory; two matches or no match diagnose.
An inline module uses a same-named child directory for its external children.
The package target's source is its root module. A source file cannot acquire
two module identities by being loaded through different paths.

Collect module item declarations before resolving their bodies, permitting
mutually referring items/imports without cyclic initialization. Resolve local
bindings from innermost scope outward, then explicit item/import bindings, then
unambiguous glob imports and the prelude. Duplicate explicit bindings diagnose;
multiple glob exposures of the same declaration do not create an ambiguity.
Private items cannot be reexported beyond their visibility. Cyclic aliases or
imports that never resolve to a declaration diagnose; compilation dependency
cycles remain package-resolver errors. Static initialization remains constant,
not import-order execution.

Explicit generic call arguments use `function::<Types>(arguments)` as a working
native disambiguator. This is a selected spelling, not a Rust compatibility
fallback or requirement to expose Rust APIs. Ordinary calls infer arguments.
`a < b > (c)` remains comparisons and is rejected as a comparison chain.

## 3. Type expressions

```ebnf
type          = simple_type, [ "throws", type ] ;
simple_type   = owned_type | borrowed_type | postfix_type ;
owned_type    = ( "heap" | "shared" | "local", "shared"
               | "weak" | "local", "weak" | "pinned" ), simple_type ;
borrowed_type = ( "read" | "mut" ), postfix_type, [ "from", sources ] ;
postfix_type  = type_atom, { "?" } ;
type_atom     = path, [ generic_args ]
              | "(", type, ")"
              | "(", type, ",", type_list, ")"
              | "[", type, [ ";", const_expression ], "]"
              | "any", bounds, [ "from", sources ]
              | "some", bounds, [ "from", sources ]
              | "ptr", "<", ( "read" | "mut" ), type, ">"
              | projection_type | callable_type | "_" ;
projection_type = "<", type, "implements", bound, ">", "::", IDENT,
                  [ generic_args ] ;
sources       = region_source | "(", region_source, { ",", region_source }, ")" ;
region_source = path | "static" ;
callable_type = [ "for", "<", region_list, ">" ],
                [ "unsafe" ], [ "extern", TEXT ],
                [ "async" ], [ "mut" | "take" ],
                "fn", "(", parameter_types, ")", result_annotation,
                [ "throws", type ] ;
result_annotation = ":", simple_type ;
```

Lists may be empty only where the corresponding construct permits it.
`[T]` is an unsized slice; `[T; N]` is a fixed array. A borrow of an optional
payload is `read T? from r`; an optional borrowed view is `(read T from r)?`.
Parentheses resolve ownership/optional nesting; do not infer a different shape.
Fields storing views must carry a named region or a defined static source.
Named sources in function results may name parameters/receiver; stored-field
sources name declared regions, not out-of-scope variable names.

Bare interface parameter types denote independently generic concrete inputs.
`any Interface` is erased dispatch; `some Interface` is an opaque concrete return.
Associated bindings, including types and constants, use where constraints.
`Self` is the enclosing type/implementation. The predeclared `Never` has no values;
it is a type name, not a keyword. Lowercase `never` is not a built-in type alias.
The predeclared `Unit` names the unit type; `()` is its value and is not accepted
in a type position. Callable types have no body, so their result annotation is
required, including `fn(): Unit`.

An explicit function result parses as `: simple_type`, followed independently by
optional `throws Error`. Returning an outcome as an ordinary value requires
parentheses: `: (Config throws Error)`. This distinguishes effect from payload
without relying on type-name lookup to parse. Omitting the result annotation
does not omit or infer an error effect: `fn load() throws Error { ... }` infers
only the success type. `throws` remains an explicit contract.

## 4. Types, methods and implementations

```ebnf
type_item     = attributes, [ visibility ], [ "copy" ], "type", IDENT,
                [ generics ], [ "implements", bounds ], [ where_clause ],
                "{", members, "}" ;
enum_item     = attributes, [ visibility ], [ "copy" ], "enum", IDENT,
                [ generics ], [ where_clause ], "{", [ variants ], "}" ;
variant       = attributes, IDENT, [ "(", type_list, ")" | "{", fields, "}" ],
                [ "=", const_expression ] ;
interface     = attributes, [ visibility ], [ "unsafe" ], "interface", IDENT,
                [ generics ], [ ":", bounds ], [ where_clause ],
                "{", associated_items, "}" ;
implementation = [ "unsafe" ], "impl", [ generics ], type,
                 [ "implements", bound ], [ where_clause ],
                 "{", associated_items, "}" ;
function      = attributes, [ visibility ], [ "unsafe" ], [ "const" ],
                [ "async" ], [ "mut" | "take" | "static" ],
                "fn", IDENT, [ generics ], "(", [ parameters ], ")",
                [ result_annotation ], [ "throws", type ],
                [ where_clause ], ( block | ";" ) ;
associated_type = attributes, [ visibility ], "type", IDENT, [ generics ],
                  [ ":", bounds ], [ where_clause ], [ "=", type ], ";" ;
constant      = [ visibility ], "const", IDENT, ":", type,
                "=", const_expression, ";" ;
destructor    = "drop", block ;
```

Members include fields, methods, constructors, associated constants, and one
destructor. Interfaces have associated declarations/default method bodies,
not stored instance fields. An implementation supplies associated definitions.
Bodyless functions are limited to interfaces and external declarations.
They must declare a result with `: Type`, even for `Unit`; no missing body
implies a default result. Definitions with bodies, including methods, generic
functions and public functions, may omit the result under core-semantics
section 8. Resolve and publish their complete inferred signatures before use;
an implementation cannot change an interface's declared contract by inference.

Implicit receiver conventions remain: read `fn`, exclusive `mut fn`, consuming
`take fn`, and no receiver for `static fn`. Advanced receivers use a first
parameter `receiver self: <mode/type>` and cannot also select an implicit
receiver modifier. This makes ownership of heap/pinned receivers explicit.

Generated construction uses fields in declaration order. A custom constructor is
`init(parameters) [throws Error] { ... }`. It initializes `self.field` places;
all fields must be initialized on success. Before that point, `self` cannot
escape or receive ordinary methods. On failure, destroy established fields only.
A custom constructor replaces the corresponding generated call, not the
capability to define other named factories.

Parameter defaults use `name: Type = expression`. In declaration scope they may
read earlier parameters, subject to their access/region contracts, but may not
silently consume them. Explicit consumption must be declared in an applicable
contract; duplicated use is rejected. Supplied arguments evaluate first in source
order, followed by omitted defaults in declaration order.

## 5. Patterns and matching

```ebnf
match_expr    = "match", [ "mut" | "take" ], expression, "{", arms, "}" ;
arm           = pattern, [ "if", expression ], "=>", expression ;
pattern       = or_pattern ;
or_pattern    = binding_pattern, { "|", binding_pattern } ;
binding_pattern = [ IDENT, "@" ], atomic_pattern ;
atomic_pattern = "_" | IDENT | literal
               | "-", INTEGER | "-", FLOAT
               | "none" | "present", "(", pattern, ")"
               | "success", "(", pattern, ")"
               | "failure", "(", pattern, ")"
               | path | path, "(", pattern_list, ")"
               | path, "{", field_patterns, "}"
               | "(", pattern_list, ")"
               | "[", slice_patterns, "]"
               | literal, ( ".." | "..=" ), literal ;
```

Arms are comma/newline separated. Qualified variant paths prevent ambiguity
between bindings and unit variants; bare identifiers bind.
Ordinary match reads, `match mut` lends mutable access, and `match take` consumes.
Pattern bindings follow that selected mode. A guard cannot commit a move that
would make subsequent arms invalid; consuming bindings transfer only after a
successful guard. Guards do not establish exhaustiveness.

Or-pattern alternatives bind identical names with compatible types/modes.
Exhaustiveness considers native optionals/outcomes and open/nonexhaustive types.
The slice rest pattern `..` occurs at most once and may be bound with `name @ ..`.
Pattern destructuring also applies to declarations and function parameters;
bindings there must be irrefutable unless paired with a diverging `else`.

Optional construction `present(value)` adds exactly one presence level.
Contextual injection is permitted only when a unique required level is known;
it must not flatten nested states. `none` is contextual, not a null reference.

## 6. Expressions, errors and control flow

Extend postfixes with indexing, `?.member`, and explicit generic specialization.
Add casts `expression as Type`, ranges `..`/`..=`, and native outcome operators.
From tightest to loosest: postfix; unary; cast; multiplicative; additive; shift;
bitwise and/xor/or; nonchaining comparison; `&&`; `||`; right-associative `??`;
nonchaining range. Parentheses are mandatory where a range/optional combination
would otherwise be unclear to the reader.

Unary forms add `read place`, `mut place`, `*pointer_or_view`, `weak owner`,
`heap expression`, `shared expression`, `local shared expression`, `await`,
`try`, and `capture`. Construction operators use ordinary call/type checking,
not implicit reinterpretation of raw storage. `read` and `mut` borrowing are
never retention operations.

`try expression` propagates a declared typed failure; `capture expression`
turns such a failure into an outcome. `throw expression` exits through a declared
error type. `try` is required at propagation sites; a raw throwing call must be
handled, captured, or propagated rather than silently discarding failure.
`capture` does not catch panic.

`for pattern in expression { ... }` selects the documented iterator protocol.
Label loops with `label name: loop ...`; `break label name value` and
`continue label name` select the target. An unlabeled break targets the nearest
loop. Value-producing `loop` joins its break value types; while/for remain unit.

`let pattern = expression else { ... }` requires the else block to diverge.
`if let pattern = expression { ... }` and its while equivalent use conditional
bindings with explicit branch lifetimes.

Closure syntax is `[async] [take] fn(parameters) [: Result] [throws Error] block`.
Omitting a name distinguishes it from a function declaration. Types and result
may be contextually inferred for closures. `take` selects owned captures;
otherwise captures infer minimal read/exclusive use with an escaping-region
contract. It does not force every escaping closure to allocate. Named function
result inference is body-based; closure contextual inference does not let a
caller's expected type determine a named function's declaration.

## 7. Unsafe, foreign declarations and metadata

Use `unsafe { ... }` for operations whose preconditions the compiler cannot
establish; unsafe does not disable initialization/type rules or permit UB.
`extern "C" { ... }` declares foreign functions/statics, and `extern "C" fn`
defines an exported foreign-callable function. Unsafe-call requirements are
explicit; neither an external declaration nor a C-compatible layout implies
a safe function.

Attributes use `@name(arguments)` before an item/member. Initial defined families:
layout/align/packed, export/link name, target feature, cfg, nonexhaustive,
diagnostic and derive. Argument schemas and valid attachment points are part
of each attribute's specification; unknown required attributes are errors.

Use `union` for overlapping fields and `static` for static storage declarations.
TLS and volatile operations are explicit library/intrinsic facilities, not
ordinary mutable global access. Inline assembly has a dedicated `asm!` token
invocation and target-specific operand rules.

Declarative macros and procedural invocations use `name!` plus a delimited token
tree. Attributes/derives can invoke procedural expansion. Macro matcher and
hygiene rules are defined in advanced-contracts and specification-annex; invocation
spelling alone does not determine metaprogramming semantics.

## 8. Ambiguity resolutions

- Function result effect versus stored outcome: parentheses distinguish them.
- Parameter mode versus a stored reference value: parentheses isolate the
  reference payload, e.g. `x: take (read T from r)`.
- Generic call versus comparison: only `::<...>` explicitly specializes calls.
- Type construction versus condition block: construction uses parentheses.
- Identifier versus unit variant pattern: variants use qualified paths.
- `?` is a type suffix only; `?.`/`??` are expression tokens; error propagation
  is `try`, not another meaning of a standalone `?`.
- `take fn` is an owned-capture closure; `take expression` otherwise consumes.
- Labels use `label name`, avoiding conflict with character literals.

The specification annex supplies macro matchers/hygiene, assembly operands and
attribute schemas. Advanced-contracts supplies the foreign-varargs and pinning
contracts. No conflict-free parser is claimed. No GPU/durable-workflow/
verification language forms were added.

## 9. Composition and list productions

The following replace same-named core productions. Other core precedence tiers
remain in effect. EBNF alternatives describe sets, not ordered parser choices.
Semantic restrictions on attachment, receiver types and irrefutability remain
separate from recognizing a production.

```ebnf
items         = { SEP }, { item, { SEP } } ;
item          = type_item | enum_item | interface | implementation | function
              | module | import | constant | static_item | union_item
              | foreign_block | foreign_function | macro_definition
              | negative_property | alias_item ;
alias_item    = attributes, [ visibility ], "alias", IDENT, [ generics ],
                [ where_clause ], "=", type, ";" ;
negative_property = "impl", [ generics ], type, "not", path,
                    [ where_clause ], ";" ;
generics      = "<", generic, { ",", generic }, [ "," ], ">" ;
parameters    = parameter, { ",", parameter }, [ "," ] ;
parameter     = pattern, ":", [ mode ], type, [ "=", expression ]
              | "receiver", "self", ":", [ mode ], type ;
parameter_types = [ parameter_type, { ",", parameter_type },
                    [ ",", "..." ], [ "," ] ] ;
parameter_type = [ mode ], type ;
region_list   = "region", IDENT, { ",", "region", IDENT }, [ "," ] ;
type_list     = [ type, { ",", type }, [ "," ] ] ;
pattern_list  = [ pattern, { ",", pattern }, [ "," ] ] ;
attributes    = { "@", path, [ "(", TOKEN_TREE_CONTENTS, ")" ] } ;
members       = { SEP }, { member, { SEP } } ;
member        = attributes, [ visibility ], field
              | function | constant | associated_type | constructor | destructor ;
field         = IDENT, ":", type ;
fields        = field, { ( SEP | "," ), field }, [ SEP | "," ] ;
constructor   = "init", "(", [ parameters ], ")", [ "throws", type ], block ;
associated_items = { SEP }, { ( function | associated_type | constant ), { SEP } } ;
variants      = variant, { ( SEP | "," ), variant }, [ SEP | "," ] ;
arms          = arm, { ( SEP | "," ), arm }, [ SEP | "," ] ;
field_patterns = [ field_pattern, { ",", field_pattern }, [ "," ] ] ;
field_pattern = IDENT, [ ":", pattern ] | ".." ;
slice_patterns = [ slice_pattern, { ",", slice_pattern }, [ "," ] ] ;
slice_pattern = pattern | [ IDENT, "@" ], ".." ;
literal       = INTEGER | FLOAT | CHARACTER | BYTE | TEXT | BYTE_TEXT
              | RAW_TEXT | RAW_BYTE_TEXT | "true" | "false" ;
const_expression = expression ;
static_item   = attributes, [ visibility ], "static", [ "mut" ],
                IDENT, ":", type, "=", expression, ";" ;
union_item    = attributes, [ visibility ], "union", IDENT, [ generics ],
                [ where_clause ], "{", fields, "}" ;
foreign_block = "extern", TEXT, "{", { foreign_declaration }, "}" ;
foreign_declaration = [ "unsafe" ], [ visibility ], "fn", IDENT,
                "(", [ parameters ], [ ",", "..." ], ")",
                result_annotation, ";"
              | [ visibility ], "static", [ "mut" ], IDENT, ":", type, ";" ;
foreign_function = "extern", TEXT, function ;
macro_definition = "macro", IDENT, "{", TOKEN_TREE_CONTENTS, "}" ;
```

`TOKEN_TREE_CONTENTS` means a sequence of tokens and recursively balanced
delimiter groups, not arbitrary unvalidated source bytes. Macro matcher content
is parsed by advanced-contracts section 5 and specification-annex section 4.
Attribute payloads use the corresponding built-in schema or extension parser.
Interpolated text has lexer-managed expression holes using the ordinary
expression grammar; it is not an opaque TEXT token.

Empty product/enum/interface bodies are permitted; an empty enum is uninhabited.
Trailing separators may repeat as permitted by the core SEP rule. Module and
member separators never change a function body's tail expression.
Adjacent non-brace-terminated declarations/members require SEP or their explicit
terminator; repetition in the list productions does not waive this separator rule.
Generic type/const defaults may refer only to earlier parameters. Required
parameters cannot follow defaulted parameters; region parameters precede the
type/const parameters. Defaults select omitted arguments, not additional
ownership permissions. Associated-type where clauses constrain each family
instantiation and remain obligations on its definition and use.
Default arguments and destructuring are disallowed on foreign declarations;
varargs require at least one named fixed parameter and a compatible C ABI.
Foreign definitions may name their final variadic cursor `args: ...`; it is not
an ordinary stored type or a facility available to non-foreign native functions.
Only foreign callable types permit a final `...` in parameter_types.

`package` names the current package root; self and super select the current and
parent module. `_` is an inference placeholder only where local inference is
permitted. Optional result annotations are a separate rule; they do not enable
placeholder inference for public parameters, fields or bodyless signatures.
The unsized bound removes
the default Sized requirement; it does not demand that every instantiation have
unknown size. It is not a user-implementable interface.

Negative property declarations are restricted to the native structurally derived
properties. They do not add unrestricted negative user-interface implementations.
Unsafe interfaces require unsafe implementations with documented invariants.
An alias introduces no new nominal type, layout, Copy opt-in or orphan-rule
ownership. Associated bindings in interface arguments use `type Item = T` or
`const N = value`. Region static denotes program-lifetime backing, not a local
storage extension. Erased/opaque environment regions are distinct from the
region of a view of that value; parentheses distinguish the two levels.

Explicit enum discriminants are target-independent required integer constants
within the selected representation. Reject duplicate values and overflow.
Payload variants with explicit discriminants require an explicit integer
representation; native default layout is not a promise of C tag placement.

## 10. Extended statement and expression productions

```ebnf
statement     = binding | assignment | return_stmt | break_stmt
              | continue_stmt | while_stmt | for_stmt | throw_stmt
              | item | expression ;
binding       = ( "let" | "var" ), pattern, [ ":", type ],
                [ "=", expression, [ "else", block ] ] ;
break_stmt    = "break", [ "label", IDENT ], [ expression ] ;
continue_stmt = "continue", [ "label", IDENT ] ;
while_stmt    = [ "label", IDENT, ":" ], "while", condition, block ;
for_stmt      = [ "label", IDENT, ":" ], "for", pattern, "in", expression, block ;
throw_stmt    = "throw", expression ;
condition     = expression | "let", pattern, "=", expression ;
if_expr       = "if", condition, block, [ "else", ( if_expr | block ) ] ;
loop_expr     = [ "label", IDENT, ":" ], "loop", block ;
expression    = range_expr ;
range_expr    = coalesce, [ ( ".." | "..=" ), [ coalesce ] ]
              | ( ".." | "..=" ), [ coalesce ] ;
coalesce      = logical_or, [ "??", coalesce ] ;
product_expr  = cast_expr, { ( "*" | "/" | "%" ), cast_expr } ;
cast_expr     = unary, { "as", type } ;
unary         = ( "-" | "!" | "*" | "take" | "read" | "mut" | "weak"
                | "heap" | "shared" | "await" | "try" | "capture" ), unary
              | "local", "shared", unary | postfix ;
postfix       = primary, { call_suffix | field_suffix | index_suffix
                         | optional_suffix | specialize_suffix } ;
field_suffix  = ".", ( IDENT | INTEGER ) ;
index_suffix  = "[", expression, "]" ;
optional_suffix = "?.", IDENT ;
specialize_suffix = "::", generic_args ;
primary       = path | projection_type | literal | "none" | unit_value
              | "present", "(", expression, ")"
              | "success", "(", expression, ")"
              | "failure", "(", expression, ")"
              | "(", expression, ")" | tuple_expr | array_expr
              | if_expr | match_expr | loop_expr | closure | block
              | "unsafe", block | macro_invocation | INTERPOLATED_TEXT ;
array_expr    = "[", [ expression, { ",", expression }, [ "," ] ], "]"
              | "[", expression, ";", const_expression, "]" ;
closure       = [ "async" ], [ "take" ], "fn", "(", [ closure_parameters ], ")",
                [ result_annotation ], [ "throws", type ], block ;
closure_parameters = closure_parameter, { ",", closure_parameter }, [ "," ] ;
closure_parameter = pattern, [ ":", [ mode ], type ] ;
macro_invocation = path, "!", DELIMITED_TOKEN_TREE ;
```

The range operator cannot chain; an inclusive range requires an upper bound.
Paths stop before `::<`, which starts explicit specialization.
Integer field selectors are unsuffixed decimal tuple positions, not arbitrary
integer expressions; ordinary named members still require identifiers.
`take fn(...)` and `async take fn(...)` use closure parsing, not ordinary unary
take followed by an unrelated function item. A named function requires an
identifier immediately after fn; an unnamed closure requires `(`.

Assignment destinations remain places; consuming patterns do not make arbitrary
expressions assignable. A destructuring assignment first stages the complete
RHS and then assigns destinations left-to-right under the replacement rule.
A separate tuple/array destination pattern is allowed when each leaf is a place;
duplicate overlapping leaves are rejected.

Operator overload resolution uses declaration-known interfaces, not runtime
type tests. Array repetition evaluates its element expression once and requires
Copy for duplication; a generator API provides repeated construction of non-Copy
elements. Const evaluation validates required array lengths after parsing.

## 11. Receiver and pin projection rules

An explicit receiver must be first and unique. Its type is Self or a finite
composition of native heap/shared/pinned/read/mut constructors around Self,
with access rights consistent with the body. Local shared receivers retain
their thread-affinity restrictions. Other arbitrary receiver type families are
not silently introduced by autoderef.

Read receiver methods cannot consume a stored owner. Consuming heap receivers
transfer the owner; consuming shared handles does not grant exclusive access to
the payload. Pinned receivers never authorize moving an address-sensitive
payload out merely because their handle is owned.

Mark structural pinned fields with `@pinned`; the attribute has no payload and
is valid only on a field. Compiler-generated projections preserve pinning for
those fields; unmarked field projections are ordinary references only when the
parent's safe API cannot rely on their fixed addresses. A destructor of a
structurally pinned type receives pinned exclusive self and cannot move marked
fields. Unsafe manual projections must preserve the same guarantee.

## 12. Grammar audit versus parser validation

List productions and every referenced nonterminal are supplied by this document
and core-grammar together. A grammar audit checks closure, overlapping prefixes,
separator handling and coverage of documented syntax. Executing a parser against
fixtures remains a later implementation task, not a result of writing EBNF.

Required ambiguity fixtures include nested `>>`, ranges versus float literals,
named functions versus closures, result effects versus stored outcomes, modes
versus parenthesized borrowed payloads, if/else newlines, macro separators,
optional chaining on nested optionals and specialization versus comparison.
