import alloc.vec.{ List, with_capacity }
import core.text.Text
import mettle_foundation.Diagnostics
import mettle_syntax.{ Kind, Token, NodeKind, Parsed, parse }

pub enum FormatError {
    InvalidSource(Diagnostics), ChangedTokens, ChangedSyntax, NotIdempotent
}

copy type Hint { opaque_end: u32; angle: bool; match_body: bool }
copy type Open { indent: usize; line: usize; brace: bool; match_body: bool }

fn spelling<region r>(read bytes: [u8] from r, token: Token): read [u8] from r {
    read bytes[token.span.begin as usize..token.span.end as usize]
}

fn same_bytes(read left: [u8], read right: [u8]): bool { left == right }

fn symbol(read bytes: [u8], token: Token, read text: Text): bool {
    token.kind.is(Kind.Symbol) && same_bytes(spelling(bytes, token), text.as_bytes())
}

fn spaced_operator(read text: [u8]): bool {
    for op in ["=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=",
        "%=", "&=", "|=", "^=", "<<=", ">>=", "=>", "->", "??"] {
        if same_bytes(text, op.as_bytes()) { return true }
    }
    false
}

fn space_before(read bytes: [u8], left: Token, right: Token): bool {
    let written = left.span.end != right.span.begin
    let l = spelling(bytes, left)
    if right.kind.is(Kind.Comment) {
        return spelling(bytes, right).starts_with("//".as_bytes()) || written
    }
    if left.kind.is(Kind.Comment) { return written }
    let r = spelling(bytes, right)
    let l_single = if left.kind.is(Kind.Symbol) && l.len() == 1usize { l[0usize] } else { 0u8 }
    let r_single = if right.kind.is(Kind.Symbol) && r.len() == 1usize { r[0usize] } else { 0u8 }
    if "([".as_bytes().contains(l_single) || ")],;:".as_bytes().contains(r_single) { return false }
    if ",;:".as_bytes().contains(l_single) { return true }
    if r_single == b'.' || symbol(bytes, right, "?.") {
        return written && (left.kind.is(Kind.Integer) || left.kind.is(Kind.Floating))
    }
    if l_single == b'.' || symbol(bytes, left, "?.") { return false }
    if l_single == b'{' { return r_single != b'}' }
    if r_single == b'}' { return true }
    if r_single == b'{' { return written || !"$@!&*-+|".as_bytes().contains(l_single) }
    if l_single == b'}' { return written || (r_single != b'?' && r_single != b'!') }
    (left.kind.is(Kind.Symbol) && spaced_operator(l)) ||
        (right.kind.is(Kind.Symbol) && spaced_operator(r)) || written
}

fn continues(read bytes: [u8], token: Token, hint: Hint, match_body: bool): bool {
    if !token.kind.is(Kind.Symbol) { return false }
    let text = spelling(bytes, token)
    if text.len() == 1usize {
        let byte = text[0usize]
        if byte == b',' { return !match_body }
        if byte == b'<' || byte == b'>' { return hint.angle }
        return "=|^&+-*/%".as_bytes().contains(byte)
    }
    if same_bytes(text, ">>".as_bytes()) { return hint.angle }
    for op in ["..", "..=", "&&", "||", "<<"] {
        if same_bytes(text, op.as_bytes()) { return true }
    }
    spaced_operator(text)
}

fn layout_hints(read bytes: [u8], read tree: Parsed): List<Hint> {
    var hints = with_capacity<Hint>(tree.tokens.len())
    for _ in tree.tokens.as_slice() { hints.push(Hint(0u32, false, false)) }
    for node in tree.nodes.as_slice() {
        if node.kind.is(NodeKind.TokenTree) || node.kind.is(NodeKind.Interpolation) ||
            node.kind.is(NodeKind.MacroInvocation) {
            let begin = node.tokens.begin as usize
            if hints[begin].opaque_end < node.tokens.end { hints[begin].opaque_end = node.tokens.end }
        } else if node.kind.is(NodeKind.Binary) {
            if let present(operator) = node.operation { hints[operator as usize].angle = true }
        } else if node.kind.is(NodeKind.Match) {
            let subject = tree.nodes[tree.children[node.children.begin as usize].index as usize]
            var index = subject.tokens.end as usize
            while index < node.tokens.end as usize {
                let token = tree.tokens[index]
                if symbol(bytes, token, "{") { hints[index].match_body = true; break }
                index += 1
            }
        }
    }
    hints
}

fn layout(read bytes: [u8], read tree: Parsed): List<u8> {
    let hints = layout_hints(bytes, tree)
    var out = with_capacity<u8>(bytes.len())
    var stack = List<Open>()
    var index = 0usize
    var line = 0usize
    var indent = 0usize
    var previous: usize? = none
    var last_code: usize? = none
    var preceding_code: usize? = none
    while index < tree.tokens.len() {
        let token = tree.tokens[index]
        if token.kind.is(Kind.End) { break }
        if token.kind.is(Kind.Space) { index += 1; continue }
        if token.kind.is(Kind.Newline) {
            out.extend_from_slice(spelling(bytes, token))
            line = index + 1
            preceding_code = last_code
            last_code = none
            previous = none
            index += 1
            continue
        }
        let brace = symbol(bytes, token, "{")
        let open = brace || symbol(bytes, token, "(") || symbol(bytes, token, "[")
        let close = symbol(bytes, token, "}") || symbol(bytes, token, ")") || symbol(bytes, token, "]")
        let top = if stack.is_empty() { Open(0usize, line, true, false) } else { stack[stack.len() - 1] }
        if let present(left) = previous {
            if space_before(bytes, tree.tokens[left], token) { out.push(b' ') }
        } else {
            indent = if stack.is_empty() || close { top.indent } else { top.indent + 1 }
            if !close && top.brace {
                if let present(last) = preceding_code {
                    if continues(bytes, tree.tokens[last], hints[last], top.match_body) ||
                        symbol(bytes, token, ".") || symbol(bytes, token, "?.") { indent += 1 }
                }
            }
            var spaces = indent * 4
            while spaces != 0 { out.push(b' '); spaces -= 1 }
        }
        let hint = hints[index]
        if hint.opaque_end != 0u32 {
            index = hint.opaque_end as usize - 1
            out.extend_from_slice(read bytes[token.span.begin as usize..tree.tokens[index].span.end as usize])
        } else {
            out.extend_from_slice(spelling(bytes, token))
            if open {
                let level = if brace && stack.is_empty() { 0usize }
                    else if brace && top.line != line { top.indent + 1 }
                    else { indent }
                stack.push(Open(level, line, brace, hint.match_body))
            } else if close && !stack.is_empty() { let _ = stack.pop() }
        }
        previous = present(index)
        if !token.kind.is(Kind.Comment) { last_code = present(index) }
        index += 1
    }
    out
}

fn same_tokens(read before: [u8], read left: [Token], read after: [u8], read right: [Token]): bool {
    var i = 0usize
    var j = 0usize
    loop {
        while left[i].kind.is(Kind.Space) { i += 1 }
        while right[j].kind.is(Kind.Space) { j += 1 }
        let a = left[i]
        let b = right[j]
        if !a.kind.is(b.kind) || !same_bytes(spelling(before, a), spelling(after, b)) { return false }
        if a.kind.is(Kind.End) { return true }
        i += 1
        j += 1
    }
}

fn token_ranks(read tokens: [Token]): List<u32> {
    var ranks = with_capacity<u32>(tokens.len() + 1)
    var rank = 0u32
    for token in tokens {
        let at = rank
        ranks.push(take at)
        if !token.kind.is(Kind.Space) { rank += 1u32 }
    }
    ranks.push(take rank)
    ranks
}

fn same_syntax(read left: Parsed, read right: Parsed): bool {
    let present(a_root) = left.root else { return false }
    let present(b_root) = right.root else { return false }
    if a_root.index != b_root.index || left.nodes.len() != right.nodes.len() ||
        left.children.len() != right.children.len() { return false }
    let a_rank = token_ranks(left.tokens.as_slice())
    let b_rank = token_ranks(right.tokens.as_slice())
    var index = 0usize
    while index < left.nodes.len() {
        let a = left.nodes[index]
        let b = right.nodes[index]
        if !a.kind.is(b.kind) || a.semicolon != b.semicolon ||
            a.children.begin != b.children.begin || a.children.end != b.children.end ||
            a_rank[a.tokens.begin as usize] != b_rank[b.tokens.begin as usize] ||
            a_rank[a.tokens.end as usize] != b_rank[b.tokens.end as usize] { return false }
        if let present(a_op) = a.operation {
            let present(b_op) = b.operation else { return false }
            if a_rank[a_op as usize] != b_rank[b_op as usize] { return false }
        } else if b.operation.is_present() { return false }
        index += 1
    }
    index = 0usize
    while index < left.children.len() {
        if left.children[index].index != right.children[index].index { return false }
        index += 1
    }
    true
}

pub fn format_source(read bytes: [u8], source: u32): List<u8> throws FormatError {
    var before = parse(bytes, source)
    if before.diagnostics.error_count != 0usize { throw FormatError.InvalidSource(take before.diagnostics) }
    if !before.root.is_present() { throw FormatError.ChangedSyntax }
    let formatted = layout(bytes, before)
    let after = parse(formatted.as_slice(), source)
    if !same_tokens(bytes, before.tokens.as_slice(), formatted.as_slice(), after.tokens.as_slice()) {
        throw FormatError.ChangedTokens
    }
    if after.diagnostics.error_count != 0usize || !same_syntax(before, after) { throw FormatError.ChangedSyntax }
    if layout(formatted.as_slice(), after) != formatted { throw FormatError.NotIdempotent }
    formatted
}

@test
fn preserves_line_breaks_and_statement_tails(): Unit {
    let input = "\r\nfn compare(a  : i32,b : i32):bool{\r\na>\r\nb\r\n}\r\n\r\n\r\nfn discard(){\n1;\n}"
    let expected = "\r\nfn compare(a: i32, b: i32): bool {\r\n    a>\r\n        b\r\n}\r\n\r\n\r\nfn discard() {\n    1;\n}"
    let success(formatted) = capture format_source(input.as_bytes(), 0u32) else {
        assert(false, "valid input refused")
        return
    }
    assert(same_bytes(formatted.as_slice(), expected.as_bytes()), "layout changed a separator or used the wrong indentation")
    let success(repeated) = capture format_source(formatted.as_slice(), 0u32) else {
        assert(false, "formatter refused its own output")
        return
    }
    assert(formatted == repeated, "second format changed the output")
}

@test
fn distinguishes_match_arms_from_generic_continuations(): Unit {
    let input = "type Item{\nvalue: Heap<Inner<i32>>\nenabled: bool\n}\nfn f(){\nmatch 1{\n0=>0,\n1=>1,\n}\n}"
    let expected = "type Item {\n    value: Heap<Inner<i32>>\n    enabled: bool\n}\nfn f() {\n    match 1 {\n        0 => 0,\n        1 => 1,\n    }\n}"
    let success(formatted) = capture format_source(input.as_bytes(), 0u32) else {
        assert(false, "valid match or generic refused")
        return
    }
    assert(same_bytes(formatted.as_slice(), expected.as_bytes()), "match arms or generic closers changed continuation indentation")
}

@test
fn leaves_macro_trees_interpolations_and_comments_intact(): Unit {
    let input = "macro echo{\n($x:expr) => { $x  };\n}\nfn f(){\nlet a=echo!( 1 ) // note  \nshow(f\"{ a  + 1 }\")\n}"
    let expected = "macro echo {\n($x:expr) => { $x  };\n}\nfn f() {\n    let a = echo!( 1 ) // note  \n    show(f\"{ a  + 1 }\")\n}"
    let success(formatted) = capture format_source(input.as_bytes(), 0u32) else {
        assert(false, "valid opaque syntax refused")
        return
    }
    assert(same_bytes(formatted.as_slice(), expected.as_bytes()), "opaque syntax or comment bytes changed")
}

@test
fn refuses_invalid_source_and_token_merging(): Unit {
    match capture format_source("fn broken() {".as_bytes(), 17u32) {
        failure(FormatError.InvalidSource(diagnostics)) => {
            assert(diagnostics.error_count != 0usize && diagnostics.issues[0usize].span.source == 17u32,
                "original parse diagnostics lost")
        },
        _ => assert(false, "malformed input did not produce a parse diagnostic")
    }
    match capture format_source("\r \n".as_bytes(), 0u32) {
        failure(FormatError.ChangedTokens) => {},
        _ => assert(false, "two distinct line endings would merge into CRLF")
    }
}
