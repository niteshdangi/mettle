import std.{ env, fs, io, path, process }
import std.ffi.os_str_from_text
import std.io.{ Reader, Writer }
import std.macros.format
import alloc.vec.{ List, new }
import alloc.hash_map.Map
import alloc.string.{ String, from_text }
import core.text.Text
import mettle_syntax.{ Kind, Token, tokenize, parse, node_name }
import mettle_syntax.reference_kind
import mettle_foundation.{ Phase, Diagnostics, SOURCE_BYTES, invalid_utf8 }
import mettle_packages.{ PackageError, PackageGraph, PackagePhase, ResolveOptions, ResolvedPackage, resolve_with }
import mettle_pipeline.{ CheckError, CheckPhase, CompileError, LoweringError, ModuleLink, SourceModule, active_items, check_modules, compile_modules, external_modules }
import mettle_syntax.inspect.{ InspectionError, project, project_recovered }
import mettle_backend_llvm.{ LinkError, OverflowChecks, emit_ir, link_executable }

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

fn line_starts(read bytes: [u8]): List<usize> {
    var starts = new<usize>()
    starts.push(0usize)
    for index in 0usize..bytes.len() {
        if bytes[index] == b'\n' { starts.push(index + 1usize) }
    }
    starts
}

fn write_source_issue(mut out: Writer, read source: path.Path, read bytes: [u8],
    read starts: List<usize>, offset: usize, read phase: Text, read message: Text): Unit throws io.Error {
    let line = starts.as_slice().partition_point(fn(read start: usize): bool { start <= offset })
    let start = starts[line - 1usize]
    let end = if line < starts.len() { starts[line] - 1usize } else { bytes.len() }
    var column = 1usize
    for byte in bytes[start..offset] {
        if (byte & 192u8) != 128u8 { column += 1usize }
    }
    try out.write_path(source)
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

fn report_source(read source: path.PathInput, read bytes: [u8], read diagnostics: Diagnostics): i32 throws io.Error {
    if diagnostics.error_count == 0usize { return 0 }
    let canonical = capture fs.canonicalize(source)
    let display = match read canonical {
        success(resolved) => resolved.as_path(),
        failure(_) => source.as_path()
    }
    let starts = line_starts(bytes)
    var out = io.buf_writer(io.stderr())
    for issue in diagnostics.issues.as_slice() {
        try write_source_issue(mut out, display, bytes, starts, issue.span.begin as usize,
            phase_name(issue.phase), issue.message)
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

fn report_check_error(read source: path.PathInput, read bytes: [u8], error: CheckError): i32 throws io.Error {
    var out = io.buf_writer(io.stderr())
    let phase = match error.phase {
        CheckPhase.Feature => "feature", CheckPhase.Lex => "lex", CheckPhase.Name => "name",
        CheckPhase.Type => "type", CheckPhase.Attribute => "attribute"
    }
    let canonical = capture fs.canonicalize(source)
    let display = match read canonical {
        success(resolved) => resolved.as_path(),
        failure(_) => source.as_path()
    }
    try write_source_issue(mut out, display, bytes, line_starts(bytes), error.span.begin as usize, phase, error.message)
    try out.flush()
    1
}

fn load_module(read source: path.Path, index: usize, package_index: usize, parent: usize?,
    read features: List<String>): SourceModule? throws io.Error {
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
    let items = match take capture active_items(bytes.as_slice(), parsed, features) {
        success(items) => take items,
        failure(error) => {
            let _ = try report_check_error(source, bytes.as_slice(), error)
            return none
        }
    }
    present(SourceModule(take bytes, take parsed, Map<List<u8>, ModuleLink>(), package_index, parent, take items))
}

fn check_source(read source: path.Path, read features: List<String>): i32 throws io.Error {
    let present(loaded) = try load_single_graph(source, features) else { return 1 }
    try check_loaded(loaded, true)
}

fn mount_name(read name: Text): List<u8> {
    var bytes = name.as_bytes().to_vec()
    for index in 0usize..bytes.len() {
        if bytes[index] == b'-' { bytes[index] = b'_' }
    }
    bytes
}

fn package_mounts(read graph: PackageGraph, read source_indices: List<usize?>): List<Map<List<u8>, usize>> {
    var mounts = List<Map<List<u8>, usize>>()
    var roots = Map<List<u8>, usize?>()
    for index in 0usize..graph.packages.len() {
        var aliases = Map<List<u8>, usize>()
        let present(source_index) = source_indices[index] else {
            mounts.push(take aliases)
            continue
        }
        let package = read graph.packages[index]
        let name = mount_name(package.name.as_text())
        if package.is_library {
            if roots.contains_key(name) { let _ = roots.insert(take name, none) }
            else { let _ = roots.insert(take name, present(source_index)) }
        }
        let _ = aliases.insert(mount_name(package.name.as_text()), source_index)
        for edge in package.dependencies.as_slice() {
            if !edge.is_host && graph.packages[edge.package].is_library {
                if let present(dependency) = source_indices[edge.package] {
                    let _ = aliases.insert(mount_name(edge.name.as_text()), dependency)
                }
            }
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

type PackageSources {
    sources: List<SourceModule>
    paths: List<ModulePath>
    mounts: List<Map<List<u8>, usize>>
}

fn load_graph(read graph: PackageGraph): PackageSources? throws io.Error {
    if !graph.build_scripts.is_empty() || !graph.macros.is_empty() {
        io.eprint("mettle: error[feature]: native compilation does not execute build scripts or procedural macros yet\n")
        return none
    }
    var sources = List<SourceModule>()
    var paths = List<ModulePath>()
    var seen = Map<path.PathBuf, Unit>()
    var source_indices = List<usize?>()
    for package_index in 0usize..graph.packages.len() {
        let package = read graph.packages[package_index]
        if package.is_host || (package_index != 0usize && !package.is_library) {
            source_indices.push(none)
            continue
        }
        let source = match read package.entry {
            present(entry) => entry.as_path(),
            none => {
                io.eprint("mettle: error[internal]: selected target package has no source entry\n")
                return none
            }
        }
        if seen.insert(source.to_path_buf(), ()).is_present() {
            io.eprint("error[name]: source file has more than one module identity\n")
            return none
        }
        let index = sources.len()
        let present(module_source) = try load_module(source, index, package_index, none, package.features) else { return none }
        paths.push(ModulePath(source.to_path_buf(), source.parent().or_panic().to_path_buf()))
        sources.push(take module_source)
        source_indices.push(present(index))
    }
    let mounts = package_mounts(graph, source_indices)
    if !try discover_modules(mut sources, mut paths, mut seen, graph.packages.as_slice(), List<String>()) { return none }
    present(PackageSources(take sources, take paths, take mounts))
}

fn discover_modules(mut sources: List<SourceModule>, mut paths: List<ModulePath>,
    mut seen: Map<path.PathBuf, Unit>, read packages: [ResolvedPackage],
    read standalone_features: List<String>): bool throws io.Error {
    var owner = 0usize
    while owner < sources.len() {
        let declarations = match take capture external_modules(sources[owner]) {
            success(declarations) => take declarations,
            failure(error) => {
                let _ = try report_check_error(paths[owner].source.as_path(), sources[owner].bytes.as_slice(), error)
                return false
            }
        }
        for declaration in take declarations {
            let owner_path = paths[owner].source.as_path()
            if sources[owner].modules.contains_key(declaration.name) {
                let _ = try report_check_error(owner_path, sources[owner].bytes.as_slice(),
                    CheckError(CheckPhase.Name, declaration.span, "duplicate module"))
                return false
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
                let _ = try report_check_error(owner_path, sources[owner].bytes.as_slice(),
                    CheckError(CheckPhase.Name, declaration.span, reason))
                return false
            }
            let source = try fs.canonicalize(if flat_exists { flat.as_path() } else { nested.as_path() })
            if seen.insert(source.to_path_buf(), ()).is_present() {
                let _ = try report_check_error(owner_path, sources[owner].bytes.as_slice(),
                    CheckError(CheckPhase.Name, declaration.span, "source file has more than one module identity"))
                return false
            }
            let index = sources.len()
            let package_index = sources[owner].package_index
            let loaded = if packages.is_empty() {
                try load_module(source.as_path(), index, package_index, present(owner), standalone_features)
            } else {
                try load_module(source.as_path(), index, package_index, present(owner), packages[package_index].features)
            }
            let present(module_source) = loaded else { return false }
            let _ = sources[owner].modules.insert(take declaration.name, ModuleLink(index, declaration.exported))
            paths.push(ModulePath(take source, take directory))
            sources.push(take module_source)
        }
        owner += 1usize
    }
    true
}

fn load_single_graph(read source: path.Path, read features: List<String>): PackageSources? throws io.Error {
    let present(module_source) = try load_module(source, 0, 0, none, features) else { return none }
    let canonical = try fs.canonicalize(source)
    var sources = List<SourceModule>()
    sources.push(take module_source)
    var paths = List<ModulePath>()
    let children = canonical.parent().or_panic().to_path_buf()
    var seen = Map<path.PathBuf, Unit>()
    let _ = seen.insert(canonical.to_path_buf(), ())
    paths.push(ModulePath(take canonical, take children))
    if !try discover_modules(mut sources, mut paths, mut seen, List<ResolvedPackage>().as_slice(), features) { return none }
    var mounts = List<Map<List<u8>, usize>>()
    mounts.push(Map<List<u8>, usize>())
    present(PackageSources(take sources, take paths, take mounts))
}

fn check_loaded(read loaded: PackageSources, executable: bool): i32 throws io.Error {
    match take capture check_modules(loaded.sources, loaded.mounts, executable) {
        failure(error) => {
            let index = error.span.source as usize
            try report_check_error(loaded.paths[index].source.as_path(), loaded.sources[index].bytes.as_slice(), error)
        },
        success(_) => 0
    }
}

fn check_graph(read graph: PackageGraph): i32 throws io.Error {
    let present(loaded) = try load_graph(graph) else { return 1 }
    try check_loaded(loaded, !graph.packages[0].is_library)
}

fn check_input(read source: path.Path, read entry: Text, read options: ResolveOptions, package_options: bool): i32 throws io.Error {
    if !package_input(source) {
        if package_options {
            io.eprint("mettle: error[package]: --entry, --no-default-features, --registry, --locked, --offline and --frozen need a package directory or package.mettle\n")
            return 2
        }
        return try check_source(source, options.features)
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
    io.eprint("usage: mettle-selfhost check INPUT [--entry NAME] [--features a,b] [--no-default-features] [--registry PATH] [--locked|--offline|--frozen]\n")
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
        } else if arg.same(os_str_from_text("--no-default-features")) {
            options.default_features = false
            package_options = true
        } else if arg.same(os_str_from_text("--registry")) {
            position += 1usize
            if position == args.len() { return check_usage() }
            let registry = args[position].as_os_str()
            let bytes = registry.as_bytes()
            if bytes.is_empty() || bytes[0usize] == b'-' { return check_usage() }
            options.registries.push(path.path_from_os_str(registry).to_path_buf())
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

enum BuildArtifact { Llvm, Executable }

fn find_linker(read clang: path.Path): path.PathBuf throws io.Error {
    let parent = clang.parent()
    if let present(directory) = parent {
        if !directory.as_os_str().is_empty() { return clang.to_path_buf() }
    }
    if let present(search) = take env.var_os(os_str_from_text("PATH")) {
        for directory in env.split_paths(search.as_os_str()) {
            let candidate = directory.join(clang)
            if try regular_source(candidate.as_path()) { return candidate }
        }
    }
    throw io.from_kind(io.ErrorKind.NotFound)
}

fn report_link_error(take error: LinkError): Unit {
    match take error {
        LinkError.UnsupportedHost => io.eprint("mettle: error[feature]: native linking requires a Linux x86-64 host\n"),
        LinkError.Io(error) => {
            let reason = error.message()
            io.eprint(f"mettle: error[link]: cannot link native executable: {reason}\n")
        },
        LinkError.Failed(status) => {
            io.eprint(f"mettle: error[link]: native linker failed: {status}\n")
        }
    }
}

fn runtime_archive(): path.PathBuf throws io.Error {
    if let present(configured) = take env.var_os(os_str_from_text("METTLE_RUNTIME")) {
        return path.path_from_os_str(configured.as_os_str()).to_path_buf()
    }
    let executable = try env.current_exe()
    executable.parent().or_panic().join("libmettle_runtime.a")
}

fn stage_artifact(read temporary: path.Path, read output: path.Path, read bytes: [u8],
    artifact: BuildArtifact, read clang: path.Path): bool throws io.Error {
    let ir = temporary.join("module.ll")
    {
        var handle = try fs.create_new(ir)
        try handle.write_all(bytes)
        try handle.sync_all()
    }
    var verifier = process.command_text("llvm-as")
    verifier.arg_text("--disable-output")
    verifier.arg(ir.as_os_str())
    if !(try verifier.status()).succeeded() {
        io.eprint("mettle: error[backend]: LLVM rejected the generated module\n")
        return false
    }
    if let BuildArtifact.Executable = artifact {
        let program = temporary.join("program")
        let runtime = try runtime_archive()
        let tool = match take capture find_linker(clang) {
            success(tool) => take tool,
            failure(error) => {
                report_link_error(LinkError.Io(take error))
                return false
            }
        }
        match take capture link_executable(tool.as_path(), ir.as_path(), program.as_path(), runtime.as_path()) {
            success(_) => {},
            failure(error) => {
                report_link_error(take error)
                return false
            }
        }
        try fs.rename(program, output)
    } else {
        try fs.rename(ir, output)
    }
    true
}

fn publish_artifact(read output: path.Path, read bytes: [u8], artifact: BuildArtifact,
    read clang: path.Path): i32 throws io.Error {
    let present(filename) = output.file_name() else {
        io.eprint("mettle: error[io]: build output must be a file path\n")
        return 1
    }
    let parent = output.parent().or_panic()
    let directory = if parent.as_os_str().is_empty() { path.path_from_text(".") } else { parent }
    let pid = process.id()
    var nonce = 0u64
    var builder = fs.dir_builder()
    builder.mode(448u32)
    loop {
        let name = format(f".mettle-llvm-{pid}-{nonce}.tmp")
        nonce += 1u64
        if filename.same(os_str_from_text(name.as_text())) { continue }
        let temporary = directory.join(name.as_text())
        match take capture builder.create(temporary) {
            success(_) => {},
            failure(error) => {
                if error.kind().is(io.ErrorKind.AlreadyExists) { continue }
                throw error
            }
        }
        let result = capture stage_artifact(temporary.as_path(), output, bytes, artifact, clang)
        let published = match read result { success(value) => value, failure(_) => false }
        match take capture fs.remove_dir_all(temporary) {
            success(_) => {},
            failure(error) => {
                let reason = error.message()
                io.eprint(f"mettle: warning[io]: cannot remove staged build output: {reason}\n")
            }
        }
        if published { return 0 }
        match take result {
            failure(error) => {
                let reason = error.message()
                io.eprint(f"mettle: error[io]: cannot verify or publish build output: {reason}\n")
                return 1
            },
            success(_) => { return 1 }
        }
    }
}

fn build_llvm(read loaded: PackageSources, read output: path.Path, checks: OverflowChecks,
    artifact: BuildArtifact, read clang: path.Path): i32 throws io.Error {
    let verified = match take capture compile_modules(loaded.sources, loaded.mounts, true) {
        success(verified) => take verified,
        failure(CompileError.Check(error)) => {
            let index = error.span.source as usize
            return try report_check_error(loaded.paths[index].source.as_path(), loaded.sources[index].bytes.as_slice(), error)
        },
        failure(CompileError.Lower(LoweringError.Unsupported(span))) => {
            let index = span.source as usize
            return try report_check_error(loaded.paths[index].source.as_path(), loaded.sources[index].bytes.as_slice(),
                CheckError(CheckPhase.Feature, span, "native lowering does not support this construct yet"))
        },
        failure(CompileError.Lower(_)) => {
            io.eprint("mettle: error[internal]: lowering did not produce valid IR\n")
            return 1
        }
    }
    let ir = match take capture emit_ir(verified, checks) {
        success(ir) => take ir,
        failure(_) => {
            io.eprint("mettle: error[backend]: cannot emit the verified program as hosted LLVM IR\n")
            return 1
        }
    }
    try publish_artifact(output, ir.as_bytes(), artifact, clang)
}

fn load_build_input(read source: path.Path): PackageSources? throws io.Error {
    if package_input(source) {
        let directory = if source.is_dir() { source.to_path_buf() }
            else if let present(parent) = source.parent() {
                if parent.as_os_str().is_empty() { path.path_buf_from_text(".") } else { parent.to_path_buf() }
            } else { path.path_buf_from_text(".") }
        let graph = match take capture resolve_with(directory.as_path(), "main", ResolveOptions()) {
            success(graph) => take graph,
            failure(error) => { let _ = try report_package_error(error); return none }
        }
        if graph.packages[0].is_library {
            io.eprint("mettle: error[feature]: native build currently requires an executable entry\n")
            return none
        }
        return try load_graph(graph)
    }
    try load_single_graph(source, List<String>())
}

fn build_usage(): i32 {
    io.eprint("usage: mettle-selfhost build INPUT -o OUTPUT [--emit executable|llvm] [--cc CXX] [--profile debug|release] [--overflow-checks on|off]\n")
    2
}

fn run_build(read args: env.ArgsOs): i32 throws io.Error {
    var input: usize? = none
    var output: usize? = none
    var emit: BuildArtifact? = none
    var cc: usize? = none
    var debug: bool? = none
    var override_checks: bool? = none
    var index = 2usize
    while index < args.len() {
        let option = args[index].as_os_str()
        if option.same(os_str_from_text("-o")) {
            index += 1usize
            if index == args.len() || output.is_present() { return build_usage() }
            output = present(index)
        } else if option.same(os_str_from_text("--emit")) {
            index += 1usize
            if index == args.len() || emit.is_present() { return build_usage() }
            let value = args[index].as_os_str()
            if value.same(os_str_from_text("llvm")) { emit = present(BuildArtifact.Llvm) }
            else if value.same(os_str_from_text("executable")) { emit = present(BuildArtifact.Executable) }
            else {
                io.eprint("mettle: error[feature]: native build currently supports only executable and LLVM IR output\n")
                return 1
            }
        } else if option.same(os_str_from_text("--cc")) {
            index += 1usize
            if index == args.len() || cc.is_present() { return build_usage() }
            let tool = args[index].as_os_str().as_bytes()
            if tool.is_empty() || tool[0usize] == b'-' { return build_usage() }
            cc = present(index)
        } else if option.same(os_str_from_text("--profile")) {
            index += 1usize
            if index == args.len() || debug.is_present() { return build_usage() }
            let profile = args[index].as_os_str()
            if profile.same(os_str_from_text("debug")) { debug = present(true) }
            else if profile.same(os_str_from_text("release")) { debug = present(false) }
            else { return build_usage() }
        } else if option.same(os_str_from_text("--overflow-checks")) {
            index += 1usize
            if index == args.len() || override_checks.is_present() { return build_usage() }
            let value = args[index].as_os_str()
            if value.same(os_str_from_text("on")) { override_checks = present(true) }
            else if value.same(os_str_from_text("off")) { override_checks = present(false) }
            else { return build_usage() }
        } else {
            let bytes = option.as_bytes()
            if bytes.is_empty() || bytes[0usize] == b'-' || input.is_present() { return build_usage() }
            input = present(index)
        }
        index += 1usize
    }
    let present(input_index) = input else { return build_usage() }
    let present(output_index) = output else { return build_usage() }
    let source = path.path_from_os_str(args[input_index].as_os_str())
    let present(loaded) = try load_build_input(source) else { return 1 }
    let checks = if override_checks.or(debug.or(true)) { OverflowChecks.On } else { OverflowChecks.Off }
    let clang = if let present(tool) = cc { path.path_from_os_str(args[tool].as_os_str()) }
        else { path.path_from_text("clang++") }
    try build_llvm(loaded, path.path_from_os_str(args[output_index].as_os_str()), checks,
        emit.or(BuildArtifact.Executable), clang)
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
    if args.len() >= 2 && args[1].as_os_str().same(os_str_from_text("build")) {
        return try run_build(args)
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
        let recovered = parsed.diagnostics.error_count != 0usize
        let projected = if recovered {
            capture project_recovered(parsed, bytes.as_slice())
        } else {
            capture project(parsed, bytes.as_slice())
        }
        let view = match take projected {
            success(view) => take view,
            failure(error) => {
                if recovered { return try report_source(source, bytes.as_slice(), parsed.diagnostics) }
                match error {
                    InspectionError.Unsupported(_, span) => {
                        var diagnostics = Diagnostics()
                        diagnostics.report(Phase.Feature, span, "native inspection does not support this syntax yet")
                        return try report_source(source, bytes.as_slice(), diagnostics)
                    },
                    InspectionError.InvalidTree => {
                        io.eprint("mettle: error[internal]: cannot inspect a valid native syntax tree\n")
                        return 1
                    }
                }
            }
        }
        var out = io.buf_writer(io.stdout())
        try inspection.write_inspection(mut out, view)
        try out.flush()
        return try report_source(source, bytes.as_slice(), parsed.diagnostics)
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
