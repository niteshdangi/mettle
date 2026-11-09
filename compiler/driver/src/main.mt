import std.{env, fs, io}
import std.io.Writer
import mettle_syntax.tokenize
import mettle_syntax.reference_kind
import mettle_foundation.Phase

fn run(): i32 throws io.Error {
    let args = env.args()
    if args.len() != 2 { io.eprint("usage: mettle-selfhost SOURCE\n"); return 2 }
    let bytes = try fs.read_bytes(args[1])
    let result = tokenize(bytes.as_slice(), 0u32)
    var out = io.buf_writer(io.stdout())
    for token in result.tokens.as_slice() {
        let kind = reference_kind(token.kind)
        let begin = token.span.begin
        let end = token.span.end
        try out.write_line(f"{kind} {begin} {end}")
    }
    try out.flush()
    for issue in result.diagnostics.issues.as_slice() {
        let phase = match issue.phase { Phase.Lex => "lex", Phase.Feature => "feature", Phase.Limit => "limit" }
        let begin = issue.span.begin
        let end = issue.span.end
        let message = issue.message
        io.eprint(f"error[{phase}] {begin}:{end} {message}\n")
    }
    if result.diagnostics.error_count == 0 { 0 } else { 1 }
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => { let message = error.message(); io.eprint(f"{message}\n"); 1 }
    }
}
