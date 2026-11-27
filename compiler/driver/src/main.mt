import std.{ env, fs, io, path }
import std.ffi.os_str_from_text
import std.io.{ Reader, Writer }
import alloc.vec.{ List, new }
import alloc.hash_map.Map
import alloc.string.from_text
import core.text.Text
import mettle_syntax.{ Kind, Token, tokenize, parse, node_name }
import mettle_syntax.reference_kind
import mettle_foundation.{ Phase, Diagnostics, SOURCE_BYTES, invalid_utf8 }
import mettle_packages.{ PackageError, PackageGraph, PackagePhase, ResolveOptions, resolve_with }
import mettle_pipeline.{ CheckError, CheckPhase, SourceModule, check_modules, external_modules }
import mettle_syntax.inspect.{ InspectionError, project }

module inspection;

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

fn load_module(read source: path.Path, index: usize, package_index: usize): SourceModule? throws io.Error {
    if index > 4294967295usize {
        io.eprint("error[limit]: source indices exceed the 32-bit span representation\n")
        return none
    }
    let loaded = match take capture load_source(source) {
        success(content) => take content,
        failure(error) => {
            let _ = try report_read_error(source, error)
            return none
        }
    }
    let present(bytes) = loaded else {
        io.eprint("error[limit] 0:0 source file must be smaller than 4 GiB\n")
        return none
    }
    let parsed = parse(bytes.as_slice(), index as u32)
    if try report_source(source, bytes.as_slice(), parsed.diagnostics) != 0 { return none }
    present(SourceModule(take bytes, take parsed, Map<List<u8>, usize>(), package_index))
}

fn check_source(read source: path.Path): i32 throws io.Error {
    let present(module_source) = try load_module(source, 0, 0) else { return 1 }
    var modules = List<SourceModule>()
    modules.push(take module_source)
    var mounts = List<Map<List<u8>, usize>>()
    mounts.push(Map<List<u8>, usize>())
    match take capture check_modules(modules, mounts, true) {
        failure(error) => { try report_check_error(source, error) },
        success(_) => 0
    }
}

fn mount_name(read name: Text): List<u8> {
    var bytes = name.as_bytes().to_vec()
    for index in 0usize..bytes.len() {
        if bytes[index] == b'-' { bytes[index] = b'_' }
    }
    bytes
}

fn package_mounts(read graph: PackageGraph): List<Map<List<u8>, usize>> {
    var mounts = List<Map<List<u8>, usize>>()
    var roots = Map<List<u8>, usize?>()
    for index in 0usize..graph.packages.len() {
        let package = read graph.packages[index]
        let name = mount_name(package.name.as_text())
        if roots.contains_key(name) { let _ = roots.insert(take name, none) }
        else { let _ = roots.insert(take name, present(index)) }
        var aliases = Map<List<u8>, usize>()
        let _ = aliases.insert(mount_name(package.name.as_text()), index)
        for edge in package.dependencies.as_slice() {
            let _ = aliases.insert(mount_name(edge.name.as_text()), edge.package)
        }
        mounts.push(take aliases)
    }
    for root in roots {
        if let present(index) = root.value {
            if !mounts[0].contains_key(root.key) {
                let _ = mounts[0].insert(root.key.as_slice().to_vec(), index)
            }
        }
    }
    mounts
}

fn regular_source(read source: path.Path): bool throws io.Error {
    match take capture fs.metadata(source) {
        success(info) => info.is_file(),
        failure(error) => match error.kind() {
            io.ErrorKind.NotFound | io.ErrorKind.NotADirectory => false,
            _ => { throw error }
        }
    }
}

type ModulePath {
    source: path.PathBuf
    children: path.PathBuf
}

fn check_graph(read graph: PackageGraph): i32 throws io.Error {
    var sources = List<SourceModule>()
    var paths = List<ModulePath>()
    var seen = Map<path.PathBuf, Unit>()
    let mounts = package_mounts(graph)
    for package in graph.packages.as_slice() {
        let source = package.entry.as_path()
        if seen.insert(source.to_path_buf(), ()).is_present() {
            io.eprint("error[name]: source file has more than one module identity\n")
            return 1
        }
        let index = sources.len()
        let present(module_source) = try load_module(source, index, index) else { return 1 }
        paths.push(ModulePath(source.to_path_buf(), source.parent().or_panic().to_path_buf()))
        sources.push(take module_source)
    }
    var owner = 0usize
    while owner < sources.len() {
        let declarations = match take capture external_modules(sources[owner].bytes.as_slice(), sources[owner].syntax) {
            success(declarations) => take declarations,
            failure(error) => { return try report_check_error(paths[owner].source.as_path(), error) }
        }
        for declaration in take declarations {
            let owner_path = paths[owner].source.as_path()
            if sources[owner].modules.contains_key(declaration.name) {
                return try report_check_error(owner_path, CheckError(CheckPhase.Name, declaration.span, "duplicate module"))
            }
            let directory = paths[owner].children.join(path.path_buf_from_bytes(declaration.name.as_slice()))
            var filename = declaration.name.as_slice().to_vec()
            filename.extend_from_slice(b".mt")
            let flat = paths[owner].children.join(path.path_buf_from_bytes(filename.as_slice()))
            let nested = directory.join("module.mt")
            let flat_exists = try regular_source(flat.as_path())
            let nested_exists = try regular_source(nested.as_path())
            if flat_exists == nested_exists {
                let reason = if flat_exists { "external module matches both source paths" }
                    else { "external module source file does not exist" }
                return try report_check_error(owner_path, CheckError(CheckPhase.Name, declaration.span, reason))
            }
            let source = try fs.canonicalize(if flat_exists { flat.as_path() } else { nested.as_path() })
            if seen.insert(source.to_path_buf(), ()).is_present() {
                return try report_check_error(owner_path, CheckError(CheckPhase.Name, declaration.span, "source file has more than one module identity"))
            }
            let index = sources.len()
            let present(module_source) = try load_module(source.as_path(), index, sources[owner].package_index) else { return 1 }
            let _ = sources[owner].modules.insert(take declaration.name, take index)
            paths.push(ModulePath(take source, take directory))
            sources.push(take module_source)
        }
        owner += 1usize
    }
    match take capture check_modules(sources, mounts, !graph.packages[0].is_library) {
        failure(error) => { try report_check_error(paths[error.span.source as usize].source.as_path(), error) },
        success(_) => 0
    }
}

fn check_input(read source: path.Path, read entry: Text, read options: ResolveOptions, package_options: bool): i32 throws io.Error {
    if !package_input(source) {
        if package_options {
            io.eprint("mettle: error[package]: --entry, --no-default-features, --registry, --locked, --offline and --frozen need a package directory or package.mettle\n")
            return 2
        }
        return try check_source(source)
    }
    if source.is_dir() { return try check_package(source, entry, options) }
    if let present(parent) = source.parent() {
        if !parent.as_os_str().is_empty() { return try check_package(parent, entry, options) }
    }
    try check_package(path.path_from_text("."), entry, options)
}

fn check_package(read directory: path.Path, read entry: Text, read options: ResolveOptions): i32 throws io.Error {
    match take capture resolve_with(directory, entry, options) {
        success(graph) => { try check_graph(graph) },
        failure(error) => { try report_package_error(error) }
    }
}

fn check_usage(): i32 {
    io.eprint("usage: mettle-selfhost check INPUT [--entry NAME] [--features a,b] [--no-default-features] [--locked|--offline|--frozen]\n")
    2
}

fn run_check(read args: env.ArgsOs): i32 throws io.Error {
    var position = 2usize
    var input: usize? = none
    var entry: usize? = none
    var options = ResolveOptions()
    var package_options = false
    while position < args.len() {
        let arg = args[position].as_os_str()
        if arg.same(os_str_from_text("--entry")) {
            position += 1usize
            if position == args.len() || entry.is_present() { return check_usage() }
            entry = present(position)
            package_options = true
        } else if arg.same(os_str_from_text("--features")) {
            position += 1usize
            if position == args.len() { return check_usage() }
            let present(value) = args[position].as_os_str().to_str() else { return check_usage() }
            if !value.is_empty() && value.as_bytes()[0usize] == b'-' { return check_usage() }
            for feature in value.split(",") {
                if !feature.is_empty() { options.features.push(from_text(feature)) }
            }
            package_options = true
        } else if arg.same(os_str_from_text("--no-default-features")) {
            options.default_features = false
            package_options = true
        } else if arg.same(os_str_from_text("--locked")) || arg.same(os_str_from_text("--frozen")) {
            options.locked = true
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
        return try check_input(source, name, options, package_options)
    }
    try check_input(source, "main", options, package_options)
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
        try inspection.write_json_text(mut out, read bytes[begin as usize..end as usize], token.kind.is(Kind.FormatPiece))
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
    let syntax_tree = args.len() == 3 && args[1].as_os_str().same(std.ffi.os_str_from_text("syntax-tree"))
    let tokens = args.len() == 3 && args[1].as_os_str().same(std.ffi.os_str_from_text("tokens"))
    if args.len() != 2 && !syntax && !syntax_tree && !tokens {
        io.eprint("usage: mettle-selfhost [tokens|syntax|check] INPUT\n")
        return 2
    }
    let source = path.path_from_os_str(args[if args.len() == 3 { 2usize } else { 1usize }].as_os_str())
    if (tokens || syntax) && package_input(source) {
        io.eprint("mettle: error[package]: only 'check', 'lint' and 'build' accept a package\n")
        return 2
    }
    let loaded = match take capture load_source(source) {
        success(content) => take content,
        failure(error) => {
            if tokens || syntax { return try report_read_error(source, error) }
            throw error
        }
    }
    let present(bytes) = loaded else { io.eprint("error[limit] 0:0 source file must be smaller than 4 GiB\n"); return 1 }
    if syntax {
        let parsed = parse(bytes.as_slice(), 0u32)
        if parsed.diagnostics.error_count != 0usize {
            return try report_source(source, bytes.as_slice(), parsed.diagnostics)
        }
        let view = match take capture project(parsed, bytes.as_slice()) {
            success(view) => take view,
            failure(InspectionError.Unsupported(_, span)) => {
                var diagnostics = Diagnostics()
                diagnostics.report(Phase.Feature, span, "native inspection does not support this syntax yet")
                return try report_source(source, bytes.as_slice(), diagnostics)
            },
            failure(InspectionError.InvalidTree) => {
                io.eprint("mettle: error[internal]: cannot inspect a valid native syntax tree\n")
                return 1
            }
        }
        var out = io.buf_writer(io.stdout())
        try inspection.write_inspection(mut out, view)
        try out.flush()
        return 0
    }
    if syntax_tree {
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
