import std.{ env, fs, io }
import std.io.Writer
import mettle_syntax.{ tokenize, parse, node_name }
import mettle_syntax.reference_kind
import mettle_foundation.{ Phase, Diagnostics }

fn report(read diagnostics: Diagnostics): i32 {
    for issue in diagnostics.issues.as_slice() {
        let phase = match issue.phase { Phase.Lex => "lex", Phase.Parse => "parse", Phase.Feature => "feature", Phase.Limit => "limit" }
        let begin = issue.span.begin
        let end = issue.span.end
        let message = issue.message
        io.eprint(f"error[{phase}] {begin}:{end} {message}\n")
    }
    let omitted = diagnostics.error_count - diagnostics.issues.len()
    if omitted != 0 { io.eprint(f"{omitted} additional diagnostics suppressed\n") }
    if diagnostics.error_count == 0 { 0 } else { 1 }
}

fn run(): i32 throws io.Error {
    let args = env.args()
    let syntax = args.len() == 3 && args[1].as_os_str().same(std.ffi.os_str_from_text("syntax"))
    if args.len() != 2 && !syntax { io.eprint("usage: mettle-selfhost [syntax] SOURCE\n"); return 2 }
    let bytes = try fs.read_bytes(args[if syntax { 2usize } else { 1usize }])
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
