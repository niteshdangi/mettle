import std.{ env, fs, io, path }
import std.ffi.os_str_from_text
import std.io.{ Reader, Writer }
import alloc.vec.{ List, new }
import core.text.Text
import mettle_syntax.{ Kind, Token, tokenize, parse, node_name }
import mettle_syntax.reference_kind
import mettle_foundation.{ Phase, Diagnostics, SOURCE_BYTES, invalid_utf8 }
import mettle_packages.{ PackageError, PackagePhase, resolve_locked }
import mettle_pipeline.{ Analysis, CheckError, CheckPhase, analyze_source }

fn phase_name(phase: Phase): read Text from static {
    match phase { Phase.Lex => "lex", Phase.Parse => "parse", Phase.Feature => "feature", Phase.Limit => "limit" }
}

fn report(read diagnostics: Diagnostics): i32 {
    for issue in diagnostics.issues.as_slice() {
        let phase = phase_name(issue.phase)
        let begin = issue.span.begin
        let end = issue.span.end
        let message = issue.message
        io.eprint(f"error[{phase}] {begin}:{end} {message}\n")
    }
    if diagnostics.error_count == 0 { 0 } else { 1 }
}

fn write_printable(mut out: Writer, read bytes: [u8]): Unit throws io.Error {
    var start = 0usize
    while let present(invalid) = invalid_utf8(read bytes[start..]) {
        let end = start + invalid
        try out.write_all(read bytes[start..end])
        try out.write("?")
        start = end + 1usize
    }
    try out.write_all(read bytes[start..])
}

fn report_source(read source: path.PathInput, read bytes: [u8], read diagnostics: Diagnostics): i32 throws io.Error {
    if diagnostics.error_count == 0usize { return 0 }
    let canonical = capture fs.canonicalize(source)
    let display = match read canonical {
        success(resolved) => resolved.as_path(),
        failure(_) => source.as_path()
    }
    var starts = new<usize>()
    starts.push(0usize)
    for index in 0usize..bytes.len() {
        if bytes[index] == b'\n' { starts.push(index + 1usize) }
    }
    var out = io.buf_writer(io.stderr())
    for issue in diagnostics.issues.as_slice() {
        let offset = issue.span.begin as usize
        let line = starts.as_slice().partition_point(fn(read start: usize): bool { start <= offset })
        let start = starts[line - 1usize]
        let end = if line < starts.len() { starts[line] - 1usize } else { bytes.len() }
        var column = 1usize
        for byte in bytes[start..offset] {
            if (byte & 192u8) != 128u8 { column += 1usize }
        }
        try out.write_path(display)
        let phase = phase_name(issue.phase)
        let message = issue.message
        try out.write_line(f":{line}:{column}: error[{phase}]: {message}")
        try write_printable(mut out, read bytes[start..end])
        try out.write("\n")
        for byte in bytes[start..offset] {
            if (byte & 192u8) != 128u8 {
                try out.write_all([if byte == b'\t' { b'\t' } else { b' ' }])
            }
        }
        try out.write_line("^")
    }
    try out.flush()
    1
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

fn package_input(read source: path.Path): bool {
    if let present(name) = source.file_name() {
        if name.same(std.ffi.os_str_from_text("package.mettle")) { return true }
    }
    source.is_dir()
}

fn report_read_error(read source: path.Path, read error: io.Error): i32 throws io.Error {
    var out = io.buf_writer(io.stderr())
    let message = error.message()
    try out.write("mettle: error[io]: cannot read ")
    try out.write_path(source)
    try out.write_line(f": {message}")
    try out.flush()
    1
}

fn report_package_error(read error: PackageError): i32 throws io.Error {
    var out = io.buf_writer(io.stderr())
    try out.write_path(error.path)
    let begin = error.begin
    let end = error.end
    let message = error.message.as_text()
    let phase = match error.phase {
        PackagePhase.Manifest => "manifest", PackagePhase.Package => "package",
        PackagePhase.Lock => "lock", PackagePhase.Io => "io"
    }
    try out.write_line(f":{begin}:{end}: error[{phase}]: {message}")
    try out.flush()
    1
}

fn report_check_error(read source: path.Path, error: CheckError): i32 throws io.Error {
    var out = io.buf_writer(io.stderr())
    let begin = error.span.begin
    let end = error.span.end
    let message = error.message
    let phase = match error.phase {
        CheckPhase.Feature => "feature", CheckPhase.Lex => "lex", CheckPhase.Name => "name", CheckPhase.Type => "type"
    }
    try out.write_path(source)
    try out.write_line(f":{begin}:{end}: error[{phase}]: {message}")
    try out.flush()
    1
}

fn check_source(read source: path.Path, package: bool): i32 throws io.Error {
    let loaded = match take capture load_source(source) {
        success(content) => take content,
        failure(error) => { return try report_read_error(source, error) }
    }
    let present(bytes) = loaded else {
        io.eprint("error[limit] 0:0 source file must be smaller than 4 GiB\n")
        return 1
    }
    if package {
        let parsed = parse(bytes.as_slice(), 0u32)
        let status = try report_source(source, bytes.as_slice(), parsed.diagnostics)
        if status != 0 { return status }
        io.eprint("mettle: error[feature]: native package semantic checking is not implemented\n")
        return 1
    }
    match take analyze_source(bytes.as_slice(), 0u32) {
        Analysis.SyntaxErrors(diagnostics) => { try report_source(source, bytes.as_slice(), diagnostics) },
        Analysis.SemanticError(error) => { try report_check_error(source, error) },
        Analysis.Checked(_) => 0
    }
}

fn check_input(read source: path.Path, read entry: Text, locked: bool, package_options: bool): i32 throws io.Error {
    if !package_input(source) {
        if package_options {
            io.eprint("mettle: error[package]: --entry, --no-default-features, --registry, --locked, --offline and --frozen need a package directory or package.mettle\n")
            return 2
        }
        return try check_source(source, false)
    }
    if source.is_dir() { return try check_package(source, entry, locked) }
    if let present(parent) = source.parent() {
        if !parent.as_os_str().is_empty() { return try check_package(parent, entry, locked) }
    }
    try check_package(path.path_from_text("."), entry, locked)
}

fn check_package(read directory: path.Path, read entry: Text, locked: bool): i32 throws io.Error {
    match take capture resolve_locked(directory, entry, locked) {
        success(graph) => { try check_source(graph.packages[0].entry.as_path(), true) },
        failure(error) => { try report_package_error(error) }
    }
}

fn check_usage(): i32 {
    io.eprint("usage: mettle-selfhost check INPUT [--entry NAME] [--locked|--offline|--frozen]\n")
    2
}

fn run_check(read args: env.ArgsOs): i32 throws io.Error {
    var position = 2usize
    var input: usize? = none
    var entry: usize? = none
    var locked = false
    var package_options = false
    while position < args.len() {
        let arg = args[position].as_os_str()
        if arg.same(os_str_from_text("--entry")) {
            position += 1usize
            if position == args.len() || entry.is_present() { return check_usage() }
            entry = present(position)
            package_options = true
        } else if arg.same(os_str_from_text("--locked")) || arg.same(os_str_from_text("--frozen")) {
            locked = true
            package_options = true
        } else if arg.same(os_str_from_text("--offline")) {
            package_options = true
        } else {
            let bytes = arg.as_bytes()
            if (!bytes.is_empty() && bytes[0usize] == b'-') || input.is_present() { return check_usage() }
            input = present(position)
        }
        position += 1usize
    }
    let present(index) = input else { return check_usage() }
    let source = path.path_from_os_str(args[index].as_os_str())
    if let present(selected) = entry {
        let present(name) = args[selected].as_os_str().to_str() else { return check_usage() }
        if name.is_empty() || name.as_bytes()[0usize] == b'-' { return check_usage() }
        return try check_input(source, name, locked, package_options)
    }
    try check_input(source, "main", locked, package_options)
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
    if args.len() >= 2 && args[1].as_os_str().same(os_str_from_text("check")) {
        return try run_check(args)
    }
    let syntax = args.len() == 3 && args[1].as_os_str().same(std.ffi.os_str_from_text("syntax"))
    let tokens = args.len() == 3 && args[1].as_os_str().same(std.ffi.os_str_from_text("tokens"))
    if args.len() != 2 && !syntax && !tokens {
        io.eprint("usage: mettle-selfhost [tokens|syntax|check] INPUT\n")
        return 2
    }
    let source = path.path_from_os_str(args[if args.len() == 3 { 2usize } else { 1usize }].as_os_str())
    if tokens && package_input(source) {
        io.eprint("mettle: error[package]: only 'check', 'lint' and 'build' accept a package\n")
        return 2
    }
    let loaded = match take capture load_source(source) {
        success(content) => take content,
        failure(error) => {
            if tokens { return try report_read_error(source, error) }
            throw error
        }
    }
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
        return try report_source(source, bytes.as_slice(), result.diagnostics)
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
