import alloc.hash_map.Map
import alloc.string.{ String, from_text, new }
import alloc.vec.List
import core.cmp.Ordering
import core.text.Text
import std.{ env, fs, io, process }
import std.io.Writer
import std.macros.format
import std.path.Path
import super.checksum.hash_tree
import super.data.{ Data, DataError, Kind, Range }
import super.graph.{ PackageGraph, resolve_locked }
import super.inputs.{ PackageError, PackagePhase, error_at, io_result, read_data }
import super.sha256.hex_digit

type LockedPackage {
    name: String
    version: String
    id: String
    source: String
    checksum: String
    features: List<String>
    dependencies: List<String>
    git_selectors: List<String>
    span: Range
}

pub type Lock { version: u32; packages: List<LockedPackage>; indices: Map<String, usize> }

extend Data {
    fn lock_string(object: usize, read key: Text, required: bool): String throws DataError {
        let present(index) = self.field(object, key) else {
            if required { throw DataError(self.nodes[object].span, format(f"lock entry needs '{key}'")) }
            return new()
        }
        let item = read self.nodes[index]
        if !item.kind.is(Kind.String) { throw DataError(item.span, format(f"'{key}' must be a string")) }
        from_text(item.text.as_text())
    }

    fn lock_list(object: usize, read key: Text): List<String> throws DataError {
        var result = List<String>()
        let present(index) = self.field(object, key) else { return result }
        let list = read self.nodes[index]
        if !list.kind.is(Kind.Array) { throw DataError(list.span, format(f"'{key}' must be an array")) }
        var child = index + 1
        while child < list.next {
            let item = read self.nodes[child]
            if !item.kind.is(Kind.String) { throw DataError(item.span, from_text("expected a string")) }
            result.push(from_text(item.text.as_text()))
            child = item.next
        }
        result
    }
}

fn decode(read data: Data): Lock throws DataError {
    let root = read data.nodes[0]
    if !root.kind.is(Kind.Object) { throw DataError(root.span, from_text("lock.mettle must contain an object")) }
    var index = 1usize
    while index < root.next {
        let item = read data.nodes[index]
        let key = item.key.as_text()
        if key != "version" && key != "packages" { throw DataError(item.key_span, format(f"unknown lock key '{key}'")) }
        index = item.next
    }
    let version = data.field(0, "version").or(0usize)
    let item = read data.nodes[version]
    let spelling = item.text.as_text()
    if !item.kind.is(Kind.Integer) || (spelling != "2" && spelling != "3") {
        let span = if version == 0 { Range(0, 0) } else { item.span }
        throw DataError(span, from_text("unsupported or missing lock format version (expected 3)"))
    }
    let format_version = if spelling == "2" { 2u32 } else { 3u32 }
    let list = data.field(0, "packages").or(0usize)
    if !data.nodes[list].kind.is(Kind.Array) {
        throw DataError(data.nodes[list].span, from_text("'packages' must be a list of objects"))
    }
    var packages = List<LockedPackage>()
    var indices = Map<String, usize>()
    index = list + 1
    while index < data.nodes[list].next {
        let package = read data.nodes[index]
        if !package.kind.is(Kind.Object) { throw DataError(package.span, from_text("lock package must be an object")) }
        var field = index + 1
        while field < package.next {
            let key_node = read data.nodes[field]
            let key = key_node.key.as_text()
            if key != "name" && key != "version" && key != "id" && key != "source" && key != "checksum" &&
                key != "features" && key != "dependencies" && !(format_version == 3 && key == "git_selectors") {
                throw DataError(key_node.key_span, format(f"unknown lock package key '{key}'"))
            }
            field = key_node.next
        }
        let id = try data.lock_string(index, "id", true)
        let identity = id.as_text()
        if indices.insert(from_text(identity), packages.len()).is_present() {
            throw DataError(package.span, format(f"duplicate lock package identity '{identity}'"))
        }
        packages.push(LockedPackage(try data.lock_string(index, "name", true), try data.lock_string(index, "version", true),
            take id, try data.lock_string(index, "source", true), try data.lock_string(index, "checksum", false),
            try data.lock_list(index, "features"), try data.lock_list(index, "dependencies"), try data.lock_list(index, "git_selectors"),
            package.span))
        index = package.next
    }
    for package in packages.as_slice() {
        for dependency in package.dependencies.as_slice() {
            let id = dependency.as_text()
            if !indices.contains_key(id) { throw DataError(package.span, format(f"unknown locked dependency '{id}'")) }
        }
    }
    Lock(format_version, take packages, take indices)
}

pub fn load(read path: Path, locked: bool): Lock? throws PackageError {
    let present(data) = try read_data(path, PackagePhase.Lock, true) else {
        if locked {
            throw error_at(path, Range(0, 0), from_text("lock.mettle is missing and --locked forbids creating it"), PackagePhase.Lock)
        }
        return none
    }
    match take capture decode(data) {
        success(lock) => present(take lock),
        failure(issue) => { throw error_at(path, issue.span, take issue.message, PackagePhase.Lock) }
    }
}

fn fresh(read graph: PackageGraph): Lock throws PackageError {
    var packages = List<LockedPackage>()
    for package in graph.packages.as_slice() {
        let checksum = if package.source.as_text() == "root" { new() } else { try hash_tree(package.directory.as_path()) }
        var dependencies = List<String>()
        for edge in package.dependencies.as_slice() {
            dependencies.push(from_text(graph.packages[edge.package].identity.as_text()))
        }
        packages.push(LockedPackage(from_text(package.name.as_text()), from_text(package.version.as_text()),
            from_text(package.identity.as_text()), from_text(package.source.as_text()), take checksum,
            List<String>(), take dependencies, List<String>(), Range(0, 0)))
    }
    {
        var entries = packages.as_mut_slice()
        var dependencies = mut entries[1usize..]
        dependencies.sort_unstable_by(fn(read a: LockedPackage, read b: LockedPackage): Ordering {
            a.id.as_text().cmp(b.id.as_text())
        })
    }
    var indices = Map<String, usize>()
    var i = 0usize
    while i < packages.len() {
        let index = i
        i += 1
        let _ = indices.insert(from_text(packages[index].id.as_text()), index)
    }
    Lock(3, take packages, take indices)
}

fn quote(mut out: String, read text: Text): Unit {
    out.push('"')
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            _ => {
                let value = c as u32
                if value < 32 {
                    out.push_str("\\x")
                    out.push(hex_digit(value >> 4))
                    out.push(hex_digit(value & 15))
                } else { out.push(c) }
            }
        }
    }
    out.push('"')
}

fn field(mut out: String, read key: Text, read value: Text): Unit {
    out.push_str("        ")
    out.push_str(key)
    out.push_str(": ")
    quote(mut out, value)
    out.push('\n')
}

fn list(mut out: String, read key: Text, read items: List<String>): Unit {
    out.push_str("        ")
    out.push_str(key)
    out.push_str(": [")
    var first = true
    for item in items.as_slice() {
        if !first { out.push_str(", ") }
        first = false
        quote(mut out, item.as_text())
    }
    out.push_str("]\n")
}

fn serialize(read lock: Lock): String {
    var text = from_text("// Generated by mettle; edit package.mettle to change dependencies.\n")
    let version = lock.version
    let header = format(f"version: {version}\npackages: [\n")
    text.push_str(header.as_text())
    for package in lock.packages.as_slice() {
        text.push_str("    {\n")
        field(mut text, "name", package.name.as_text())
        field(mut text, "version", package.version.as_text())
        field(mut text, "id", package.id.as_text())
        field(mut text, "source", package.source.as_text())
        if !package.checksum.is_empty() { field(mut text, "checksum", package.checksum.as_text()) }
        if !package.git_selectors.is_empty() { list(mut text, "git_selectors", package.git_selectors) }
        list(mut text, "features", package.features)
        list(mut text, "dependencies", package.dependencies)
        text.push_str("    }\n")
    }
    text.push_str("]\n")
    text
}

fn changes(read old: Lock, read current: Lock, read path: Path): PackageError {
    var detail = from_text("lock.mettle needs updating but --locked forbids changing it")
    var span: Range? = none
    if old.version != current.version {
        detail.push_str("; lock format requires an unlocked update from version 2 to 3")
    }
    for now in current.packages.as_slice() {
        let id = now.id.as_text()
        let name = now.name.as_text()
        let version = now.version.as_text()
        let present(index) = old.indices.get(id) else {
            detail.push_str(format(f"; package '{name}' {version} is not in the lock").as_text())
            if span.is_none() { span = present(Range(0, 0)) }
            continue
        }
        let then = read old.packages[*index]
        if then.version.as_text() != version {
            let before = then.version.as_text()
            detail.push_str(format(f"; package '{name}' changes from {before} to {version}").as_text())
        }
        if then.source.as_text() != now.source.as_text() {
            let before = then.source.as_text()
            let after = now.source.as_text()
            detail.push_str(format(f"; package '{name}' changes source from {before} to {after}").as_text())
        }
        if then.checksum.as_text() != now.checksum.as_text() {
            let before = then.checksum.as_text()
            let after = now.checksum.as_text()
            detail.push_str(format(f"; package '{name}' content changed ({before} -> {after})").as_text())
        }
        if !then.features.is_empty() { detail.push_str(format(f"; package '{name}' features changed").as_text()) }
        if then.dependencies.as_slice() != now.dependencies.as_slice() {
            detail.push_str(format(f"; package '{name}' dependencies changed").as_text())
        }
        if !then.git_selectors.is_empty() { detail.push_str(format(f"; package '{name}' Git selectors changed").as_text()) }
        if span.is_none() && (then.name.as_text() != name || then.version.as_text() != version ||
            then.source.as_text() != now.source.as_text() || then.checksum.as_text() != now.checksum.as_text() ||
            !then.features.is_empty() || then.dependencies.as_slice() != now.dependencies.as_slice() || !then.git_selectors.is_empty()) {
            span = present(then.span)
        }
    }
    for then in old.packages.as_slice() {
        if !current.indices.contains_key(then.id.as_text()) {
            let name = then.name.as_text()
            detail.push_str(format(f"; package '{name}' is no longer used").as_text())
        }
    }
    error_at(path, span.or(Range(0, 0)), take detail, PackagePhase.Lock)
}

fn stage_and_replace(take file: fs.File, read content: Text, read temporary: Path, read path: Path): Unit throws io.Error {
    {
        var handle = take file
        try handle.write_all(content.as_bytes())
        try handle.sync_all()
    }
    try fs.rename(temporary, path)
}

fn publish(read root: Path, read path: Path, read content: Text): Unit throws PackageError {
    let start = Range(0, 0)
    let pid = process.id()
    var nonce = 0u64
    var options = fs.open_options()
    options.set_write(true)
    options.set_create_new(true)
    options.set_mode(384u32)
    loop {
        let name = format(f"lock.mettle.tmp.{pid}.{nonce}")
        let temporary = root.join(name.as_text())
        let file = match take capture options.open(temporary) {
            success(handle) => take handle,
            failure(issue) => {
                if issue.kind().is(io.ErrorKind.AlreadyExists) {
                    nonce += 1
                    continue
                }
                throw error_at(path, start, issue.message(), PackagePhase.Io)
            }
        }
        let update = capture stage_and_replace(take file, content, temporary.as_path(), path)
        match take update {
            success(_) => { return },
            failure(issue) => {
                match capture fs.remove_file(temporary) {
                    success(_) => { throw error_at(path, start, issue.message(), PackagePhase.Io) },
                    failure(cleanup) => {
                        let original = issue.message()
                        let cleanup_message = cleanup.message()
                        let reason = original.as_text()
                        let reason_cleanup = cleanup_message.as_text()
                        throw error_at(path, start, format(f"{reason}; cannot remove temporary lock: {reason_cleanup}"), PackagePhase.Io)
                    }
                }
            }
        }
    }
}

pub fn reconcile(read graph: PackageGraph, read root: Path, read path: Path, take previous: Lock?, locked: bool): Unit throws PackageError {
    let current = try fresh(graph)
    let text = serialize(current)
    if let present(old) = previous {
        let old_text = serialize(old)
        if old_text.as_text() == text.as_text() { return }
        if locked { throw changes(old, current, path) }
    }
    try publish(root, path, text.as_text())
}

@test
fn bootstrap_path_lock(): Unit throws PackageError {
    let graph = try resolve_locked(std.path.path_from_text("compiler/packages"), "main", true)
    assert(graph.packages[0].identity.as_text() == "mettle-packages@0.1.0|root|target", "root identity differs from bootstrap")
    assert(graph.packages[1].identity.as_text() == "mettle-foundation@0.1.0|path+../foundation|target", "path identity differs from bootstrap")
}

fn require_lock_failure(read root: Path, read reason: Text): Unit {
    match take capture resolve_locked(root, "main", true) {
        success(_) => assert(false, "expected a locked check to fail"),
        failure(issue) => assert((issue.phase as u32) == (PackagePhase.Lock as u32) &&
            issue.message.as_text().find(read reason).is_present(), "wrong lock error")
    }
}

fn migration_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages/path-dependency")
    let inputs = ["app/package.mettle", "app/src/main.mt", "mathlib/package.mettle", "mathlib/src/main.mt",
        "mathlib/src/twice.mt", "units/package.mettle", "units/src/main.mt"]
    for relative in inputs {
        let original = fixture.join(relative)
        let destination = root.join(relative)
        let parent = destination.parent().or_panic()
        try io_result(take capture fs.create_dir_all(parent), root, start, PackagePhase.Io)
        let _ = try io_result(take capture fs.copy(original, destination), root, start, PackagePhase.Io)
    }
    let app = root.join("app")
    let path = app.join("lock.mettle")
    require_lock_failure(app.as_path(), "lock.mettle is missing")
    let _ = try resolve_locked(app.as_path(), "main", false)
    let initial = try io_result(take capture fs.read_to_string(path), root, start, PackagePhase.Io)
    let _ = try resolve_locked(app.as_path(), "main", true)
    var old = from_text("version: 2\n")
    old.push_str(initial.as_text().split_once("version: 3\n").or_panic().1)
    try io_result(take capture fs.write(path, old.as_bytes()), root, start, PackagePhase.Io)
    require_lock_failure(app.as_path(), "requires an unlocked update from version 2 to 3")
    let unchanged = try io_result(take capture fs.read_to_string(path), root, start, PackagePhase.Io)
    assert(unchanged.as_text() == old.as_text(), "locked migration overwrote the lock")
    let _ = try resolve_locked(app.as_path(), "main", false)
    let migrated = try io_result(take capture fs.read_to_string(path), root, start, PackagePhase.Io)
    assert(migrated.as_text() == initial.as_text(), "version 2 did not migrate to the bootstrap layout")
    let extra = root.join("units/data.txt")
    try io_result(take capture fs.write(extra, "new input".as_bytes()), root, start, PackagePhase.Io)
    require_lock_failure(app.as_path(), "package 'units' content changed")
    let unchanged = try io_result(take capture fs.read_to_string(path), root, start, PackagePhase.Io)
    assert(unchanged.as_text() == initial.as_text(), "locked drift overwrote the lock")
    let _ = try resolve_locked(app.as_path(), "main", false)
    let _ = try resolve_locked(app.as_path(), "main", true)
}

@test
fn path_lock_migration_and_drift(): Unit throws PackageError {
    let pid = process.id()
    let name = format(f"mettle-path-lock-{pid}")
    let root = env.temp_dir().join(name.as_text())
    let path = root.as_path()
    let start = Range(0, 0)
    try io_result(take capture fs.create_dir(path), path, start, PackagePhase.Io)
    let tested = capture migration_fixture(path)
    try io_result(take capture fs.remove_dir_all(path), path, start, PackagePhase.Io)
    match take tested {
        success(_) => (),
        failure(issue) => { throw issue }
    }
}
