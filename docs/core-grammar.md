# Mettle core grammar, draft 0.1

Status: selected initial subset, extended by [language-grammar.md](language-grammar.md),
with behavior defined in [core-semantics.md](core-semantics.md).
Implementation evidence is recorded in [implementation-plan.md](implementation-plan.md).

## 1. Scope and conventions

This subset defines single-file values, functions, named products, copyability,
generics, ownership modes, expressions and basic control flow.

The subset is an internal implementation milestone, not reduced V1 scope.
Enums/matching, native optionals/outcomes, interfaces, modules, closures, region
binder syntax, async, macros, FFI, and unsafe syntax remain required extensions.
Do not accept ad hoc spellings for these merely because this draft omits them.

The example corpus uses `.mt`.

EBNF conventions: `=` defines a rule; `|` is choice; `{ ... }` is repetition;
`[ ... ]` is optional; quoted text is a literal token. Uppercase names denote
lexer tokens. Bracketed EBNF notation never denotes literal source brackets.
Rules describe syntax; name resolution, typing, access and initialization checks
may reject a syntactically valid program.

## 2. Lexical rules

Source encoding is UTF-8. LF and CRLF both denote a newline. Whitespace separates
tokens but is otherwise ignored except for the newline rules below.
Identifiers in this core subset use ASCII letters/underscore followed by ASCII
letters, digits, or underscores. `_` alone is a wildcard, permitted here in the
explicit discard `let _ = expression`; it is not an ordinary binding name.
Unicode and escaped identifiers remain full-language lexical obligations.

Comments are `//` through end of line and nested `/* ... */`. Newlines inside a
block comment still participate in statement separation when not suppressed by
an enclosing delimiter. Comments cannot concatenate adjacent identifier tokens.

Core reserved words: `fn`, `type`, `copy`, `let`, `var`, `read`, `mut`, `take`,
`if`, `else`, `while`, `loop`, `break`, `continue`, `return`, `true`, `false`.
`Copy` names a predeclared capability, not a keyword.
Advanced-language keywords will be reserved when their grammar is specified;
this list is not a promise that all other names remain usable forever.

Core integer literals are decimal digits with single underscores between digits.
An optional suffix is one of `i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize`.
A minus sign is a unary operator, not part of the literal. Resolve its interaction
with signed-minimum literals during numeric checking before range rejection.
Unsuffixed integer literals use contextual integer type, otherwise `i32`.
`bool`, integer names, `Unit`, `Never`, and `Copy` are predeclared names, not
keywords.
`Unit` names the unit type; `()` is its sole value, not a type spelling.
`Never` has no values and describes a result that cannot complete normally.
The full language retains floating-point, text, character, byte,
raw, and other literals; their escaping/range rules are not defined here.

Tokenize the longest operator: for example `<=` is not `<` followed by `=`.
In a type-argument context, split closing `>>` into two `>` tokens as needed.
In an expression context, `>>` remains the shift operator.

## 3. Newlines, semicolons, and block values

The lexer/parser cooperation produces `SEP` for a statement/declaration boundary:
either a semicolon or an unsuppressed newline. Preserve whether a separator was
an explicit semicolon because it affects block values.

- Suppress newlines inside parentheses and type argument/parameter lists.
- Suppress a newline after a comma or an operator that requires a right operand.
- A header that requires a block may continue across a newline before `{`.
- `else` attaches to the immediately preceding eligible `if`, across newlines
  and comments but not across an explicit semicolon.
- A newline after a complete expression otherwise creates a separator. A new
  line beginning with `(`, `.`, or an operator does not retroactively continue
  that expression. Put the operator/dot on the preceding line, or parenthesize.
- `return`, `break`, and `continue` end at an unsuppressed newline. Write a
  multiline returned expression inside parentheses.
- Item-level `import`, `module`, `const`, `static`, `alias`, and negative
  `extend` declarations may end at an unsuppressed newline without a semicolon.
- Adjacent simple statements or declarations on the same line require a
  semicolon.

A final expression in a block supplies its value unless followed by an explicit
semicolon. Trailing newlines/comments before `}` do not discard its value.
Earlier expression statements discard their values. A block ending with a
declaration, assignment, loop statement, return, or explicit semicolon has no
ordinary tail value (unit when control reaches its end).

Prefer `let _ = expression` when intentionally ignoring a non-Unit result,
especially at a block tail. It introduces no named binding and makes the discard
visible without relying on a trailing semicolon. Unit-valued calls may remain
ordinary expression statements. Semicolon discard remains valid; this guidance
does not change separator or tail-value semantics.

The formatter must preserve separators, tail-value status, and parse structure.
Arbitrary newline edits are not claimed to preserve meaning.

```text
fn value(): i32 {
    3
}                         // Returns 3.

fn discard(): Unit {
    let _ = 3
}                         // Returns unit.

fn inferred_value() {
    3
}                         // Inferred result: i32.

fn inferred_unit() {
    let value = 3
}                         // Inferred result: Unit.
```

## 4. Declarations and types

```ebnf
program       = { SEP }, { item, { SEP } }, EOF ;
item          = function | product ;
function      = "fn", IDENT, [ generics ], "(", [ parameters ], ")",
                [ result_annotation ], block ;
result_annotation = ":", type_ref ;
generics      = "<", generic_param, { ",", generic_param }, [ "," ], ">" ;
generic_param = IDENT, [ ":", capability, { "+", capability } ] ;
capability    = IDENT ;
parameters    = parameter, { ",", parameter }, [ "," ] ;
parameter     = IDENT, ":", [ mode ], type_ref ;
mode          = "read" | "mut" | "take" ;
product       = [ "copy" ], "type", IDENT, [ generics ], "{",
                { SEP }, [ fields ], "}" ;
fields        = field, { SEP, { SEP }, field }, { SEP } ;
field         = IDENT, ":", type_ref ;
type_ref      = named_type | tuple_type ;
named_type    = IDENT, [ "<", type_ref, { ",", type_ref }, [ "," ], ">" ] ;
tuple_type    = "(", type_ref, ",", { type_ref, "," }, [ type_ref ], ")" ;
unit_value    = "(", ")" ;
```

`copy type Point` explicitly requests verified bitwise duplication. A non-copy
named type does not become copyable because all its fields happen to be scalars.
Generic opt-in must establish field eligibility using declared constraints.

Function results use `: Type`; omitting the annotation infers the result from
the body, not from callers. Reachable explicit returns and normal block-tail
values constrain one result type. A bare return or reachable fallthrough without
a value contributes `Unit`; incompatible types or unresolved inference require
a diagnostic, not an implicit conversion or a guessed result.
`core-semantics.md` section 8 defines recursion, divergence and contract limits.
Parameter types remain explicit. `->` is not a Mettle result delimiter.

Method syntax remains the blueprint's `fn`, `mut fn`, `take fn`, and `static fn`
inside types, but is outside this first product declaration rule. Fields and
methods share the extended member grammar.

`Unit` is the existing zero-sized unit type, not a newly introduced named
product. It is Copy and is distinct from absence, failure and `Never`.
Use `Unit` in type positions and `()` in expressions. Empty tuple type syntax
such as `fn discard(): ()` is rejected; nonempty tuple types are unchanged.

Parameter modes are contracts, not part of the payload's name. Omitted modes
follow the declaration-known copyability rules in the core semantics.
First-class reference types and region binders need their own grammar; do not
interpret this parameter grammar as fully specifying stored-reference types.

## 5. Blocks and control flow

```ebnf
block         = "{", { SEP }, [ block_contents ], "}" ;
block_contents = statement, { SEP, { SEP }, statement }, { SEP } ;
statement     = binding | assignment | return_stmt | break_stmt
              | continue_stmt | while_stmt | loop_stmt | expression ;
binding       = ( "let" | "var" ), IDENT, [ ":", type_ref ],
                [ "=", expression ] | discard_binding ;
discard_binding = "let", "_", "=", expression ;
assignment    = postfix, assign_op, expression ;
assign_op     = "=" | "+=" | "-=" | "*=" | "/=" | "%="
              | "&=" | "|=" | "^=" | "<<=" | ">>=" ;
return_stmt   = "return", [ expression ] ;
break_stmt    = "break" ;
continue_stmt = "continue" ;
while_stmt    = "while", expression, block ;
loop_stmt     = "loop", block ;
if_expr       = "if", expression, block, [ "else", ( if_expr | block ) ] ;
```

The block-tail rule in section 3 classifies the last expression after parsing
`block_contents`. Assignment lookahead recognizes an assignment operator after a
postfix expression before selecting an ordinary expression statement.
Assignments are unit-producing statements in this core; they cannot be nested
inside arithmetic, argument, or condition expressions.

A binding without an initializer requires a type annotation. Initializer types
are inferred when the annotation is omitted. Conditions must have type `bool`;
there is no implicit integer truthiness.
An explicit discard requires its initializer, evaluates it under ordinary
ownership/effect rules, and introduces no local. The wildcard does not itself
copy, borrow, consume or destroy an existing place. Operations in the initializer
retain their own effects; fresh temporary results have their ordinary statement
cleanup. Ignoring a result does not handle an unhandled typed failure.

An `if` without `else` is unit-valued and its then block must be unit-valued.
An `if` with `else` requires compatible branch types (including divergence).
`while` and the core `loop` statement produce unit; `break` exits the nearest
loop and `continue` starts its next iteration.
Value-producing loops, break values, labels, and `for` remain required grammar
extensions. A loop condition or if condition stops before its required block;
struct construction uses calls, not braces, so there is no struct-literal/header
ambiguity in this subset.

## 6. Expressions and precedence

```ebnf
expression    = logical_or ;
logical_or    = logical_and, { "||", logical_and } ;
logical_and   = comparison, { "&&", comparison } ;
comparison    = bit_or, [ compare_op, bit_or ] ;
compare_op    = "==" | "!=" | "<" | "<=" | ">" | ">=" ;
bit_or        = bit_xor, { "|", bit_xor } ;
bit_xor       = bit_and, { "^", bit_and } ;
bit_and       = shift, { "&", shift } ;
shift         = additive, { ( "<<" | ">>" ), additive } ;
additive      = product_expr, { ( "+" | "-" ), product_expr } ;
product_expr  = unary, { ( "*" | "/" | "%" ), unary } ;
unary         = ( "-" | "!" | "take" ), unary | postfix ;
postfix       = primary, { call_suffix | field_suffix } ;
call_suffix   = "(", [ arguments ], ")" ;
arguments     = call_argument, { ",", call_argument }, [ "," ] ;
call_argument = [ IDENT, ":" ], expression ;
field_suffix  = ".", IDENT ;
primary       = IDENT | INTEGER | "true" | "false" | unit_value
              | "(", expression, ")" | tuple_expr | if_expr | block ;
tuple_expr    = "(", expression, ",", { expression, "," }, [ expression ], ")" ;
```

Binary tiers are left associative. Comparisons do not chain: `a < b < c` is a
syntax error rather than a boolean-to-integer conversion. Postfix operations bind
most tightly. `take x.field` consumes the field, not the containing value.

Empty parentheses, grouped expressions, and tuple expressions are disambiguated
by the closing parenthesis/comma. A one-element tuple needs a comma.
The grammar above shares prefixes intentionally; a parser must use delimiter
lookahead instead of treating the EBNF alternatives as ordered PEG choices.

Core generic calls infer type arguments from arguments and expected result types.
The extended grammar's `function<T>(arguments)` gives explicit call arguments
under the syntax-only generic-follower rule in language-grammar section 13.3;
ambiguous expressions are not retried as a different parse.

Generated construction uses `Type(...)` in field declaration order, with optional
field labels. Positional arguments precede named arguments; reject duplicates,
unknown labels, and missing fields. Evaluate supplied expressions in written
order even when labels reorder fields. User functions support parameter labels
under the same rule. Defaults and custom constructors remain grammar extensions.

Implicit receiver/member access through read/mutable parameters does not copy or
retain the payload. Reading a copyable scalar field may duplicate that field.
Indexing, first-class borrow expressions, casts, and user-defined operators are
not yet expression productions; they remain capability obligations.

## 7. Entry point and errors

For this hosted example corpus, `fn main(): i32` is the entry point; an omitted
result annotation is also valid when the body infers i32. Its returned integer
becomes the process exit status through a target adapter. Examples use only
small nonnegative codes to avoid platform-specific truncation questions.
Other startup forms and freestanding entry points are separate ABI work.

Reject malformed tokens, missing operands/delimiters, ambiguous unsupported
forms, duplicate declarations in a namespace, unresolved names, invalid arity,
type mismatches, and ownership violations. Parsing must not repair a program by
inserting a clone, retain, or ownership-mode change.
Parser recovery may create marked error nodes for editor use, not runnable code.
Semantic diagnostic identifiers are not frozen yet.

## 8. Rust comparison and performance

Labels and generic modes resolve statically; constructors initialize fields.
These require no runtime name dictionary, type test, clone or retain.
Comparison gates are defined in [performance.md](performance.md).

## 9. Grammar completion gate

Validate examples, ambiguous prefixes, separators and negative diagnostics
through the parser before claiming grammar enforcement.

The extended productions in language-grammar.md supply the other V1 constructs.
Changes to accepted core meanings require a recorded compatibility decision.
