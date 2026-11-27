import std.{ env, fs, io, path }
import std.io.{ Reader, Writer }
import alloc.vec.{ List, new }
import mettle_syntax.{ Kind, Token, tokenize, parse, node_name }
import mettle_syntax.reference_kind
import mettle_foundation.{ Phase, Diagnostics, SOURCE_BYTES }

fn report(read diagnostics: Diagnostics): i32 {
    for issue in diagnostics.issues.as_slice() {
        let phase = match issue.phase { Phase.Lex => "lex", Phase.Parse => "parse", Phase.Feature => "feature", Phase.Limit => "limit" }
        let begin = issue.span.begin
        let end = issue.span.end
        let message = issue.message
        io.eprint(f"error[{phase}] {begin}:{end} {message}\n")
    }
    if diagnostics.error_count == 0 { 0 } else { 1 }
}

fn read_source(mut input: Reader, limit: usize): List<u8>? throws io.Error {
    var bytes = new<u8>()
    var chunk = [0u8; 4096]
    loop {
        let remaining = limit - bytes.len()
        let capacity = if remaining < 4096usize { remaining + 1usize } else { 4096usize }
        let count = try input.read_some(chunk.split_at_mut(capacity).0)
        if count > remaining { return none }
        if count == 0usize { return present(bytes) }
        bytes.extend_from_slice(chunk.split_at(count).0)
    }
}

fn load_source(read source: path.PathInput): List<u8>? throws io.Error {
    var input = try fs.open(source)
    let metadata = try input.metadata()
    if metadata.is_file() && metadata.len() > SOURCE_BYTES as u64 { return none }
    try read_source(mut input, SOURCE_BYTES)
}

fn write_token_text(mut out: Writer, read bytes: [u8], format_piece: bool): Unit throws io.Error {
    let hex = b"0123456789abcdef"
    var start = 0usize
    var index = 0usize
    var escaped = false
    while index < bytes.len() {
        let byte = bytes[index]
        if format_piece && !escaped && (byte == b'{' || byte == b'}') {
            let paired = index + 1usize < bytes.len() && bytes[index + 1usize] == byte
            if paired || byte == b'}' {
                let end = if paired { index + 1usize } else { index }
                try out.write_all(read bytes[start..end])
                index += if paired { 2usize } else { 1usize }
                start = index
                continue
            }
        }
        escaped = byte == b'\\' && !escaped
        if byte == b'"' || byte == b'\\' || byte < 32u8 {
            try out.write_all(read bytes[start..index])
            let spelling = match byte {
                b'"' => present(b'"'), b'\\' => present(b'\\'),
                b'\n' => present(b'n'), b'\r' => present(b'r'), b'\t' => present(b't'),
                _ => none
            }
            if let present(code) = spelling {
                try out.write_all([b'\\', code])
            } else {
                try out.write_all([b'\\', b'u', b'0', b'0',
                    hex[(byte >> 4u8) as usize], hex[(byte & 15u8) as usize]])
            }
            start = index + 1usize
        }
        index += 1usize
    }
    try out.write_all(read bytes[start..])
}

fn write_tokens(mut out: Writer, read bytes: [u8], read tokens: [Token]): Unit throws io.Error {
    try out.write("{\n  \"aliases\": [],\n  \"functions\": [],\n  \"products\": [],\n  \"tokens\": [")
    var separator = false
    for token in tokens {
        if separator { try out.write(",") }
        separator = true
        let kind = reference_kind(token.kind)
        let begin = token.span.begin
        let end = token.span.end
        try out.write(f"\n    {{\n      \"begin\": {begin},\n      \"end\": {end},\n      \"kind\": {kind},\n      \"text\": \"")
        try write_token_text(mut out, read bytes[begin as usize..end as usize], token.kind.is(Kind.FormatPiece))
        try out.write("\"\n    }")
    }
    try out.write("\n  ]\n}\n")
}

@test
fn source_read_limit(): Unit throws io.Error {
    let empty_data = [0u8; 0]
    var empty = io.slice_reader(empty_data)
    let accepted = (try read_source(mut empty, 0usize)).or_panic()
    assert(accepted.is_empty(), "empty input exceeds zero limit")
    let array = [1u8, 2u8, 3u8, 4u8]
    let data = array.split_at(0usize).1
    var exact = io.slice_reader(data)
    let accepted = (try read_source(mut exact, data.len())).or_panic()
    assert(accepted.as_slice() == data, "exact-limit input changed")
    var over = io.slice_reader(data)
    assert((try read_source(mut over, data.len() - 1usize)).is_none(), "over-limit input accepted")
    var zero = io.slice_reader(data)
    assert((try read_source(mut zero, 0usize)).is_none(), "nonempty input accepted at zero limit")
}

@test
fn source_read_chunk_limit(): Unit throws io.Error {
    let array = [42u8; 4097]
    let data = array.split_at(0usize).1
    var exact = io.slice_reader(data)
    let accepted = (try read_source(mut exact, data.len())).or_panic()
    assert(accepted.as_slice() == data, "multi-chunk input changed")
    var over = io.slice_reader(data)
    assert((try read_source(mut over, 4096usize)).is_none(), "over-limit second chunk accepted")
}

fn run(): i32 throws io.Error {
    let args = env.args_os()
    let syntax = args.len() == 3 && args[1].as_os_str().same(std.ffi.os_str_from_text("syntax"))
    let tokens = args.len() == 3 && args[1].as_os_str().same(std.ffi.os_str_from_text("tokens"))
    if args.len() != 2 && !syntax && !tokens { io.eprint("usage: mettle-selfhost [tokens|syntax] SOURCE\n"); return 2 }
    let loaded = try load_source(args[if syntax || tokens { 2usize } else { 1usize }])
    let present(bytes) = loaded else { io.eprint("error[limit] 0:0 source file must be smaller than 4 GiB\n"); return 1 }
    if syntax {
        let result = parse(bytes.as_slice(), 0u32)
        var out = io.buf_writer(io.stdout())
        var index = 0usize
        for node in result.nodes.as_slice() {
            let kind = node_name(node.kind)
            let begin = node.span.begin
            let end = node.span.end
            let first = node.children.begin
            let last = node.children.end
            let operation = match node.operation { present(value) => value as i64, none => -1i64 }
            let semicolon = if node.semicolon { 1u32 } else { 0u32 }
            try out.write_line(f"node {index} {kind} {begin} {end} {first} {last} {operation} {semicolon}")
            index += 1
        }
        for child in result.children.as_slice() {
            let value = child.index
            try out.write_line(f"edge {value}")
        }
        for token in result.tokens.as_slice() {
            let kind = reference_kind(token.kind)
            let begin = token.span.begin
            let end = token.span.end
            try out.write_line(f"token {kind} {begin} {end}")
        }
        try out.flush()
        return report(result.diagnostics)
    }
    let result = tokenize(bytes.as_slice(), 0u32)
    var out = io.buf_writer(io.stdout())
    if tokens {
        try write_tokens(mut out, bytes.as_slice(), result.tokens.as_slice())
        try out.flush()
        return report(result.diagnostics)
    }
    for token in result.tokens.as_slice() {
        let kind = reference_kind(token.kind)
        let begin = token.span.begin
        let end = token.span.end
        try out.write_line(f"{kind} {begin} {end}")
    }
    try out.flush()
    report(result.diagnostics)
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => { let message = error.message(); io.eprint(f"{message}\n"); 1 }
    }
}
