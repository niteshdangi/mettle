import alloc.hash_map.Map
import alloc.string.{ String, from_text, new }
import alloc.vec.List
import core.cmp.Ordering
import core.text.Text
import std.{ env, fs, io, process }
import std.io.Writer
import std.macros.format
import std.path.Path
import super.checksum.{ hash_tree, hash_legacy_tree }
import super.data.{ Data, DataError, Kind, Range }
import super.graph.{ PackageGraph, ResolveOptions, resolve_locked, resolve_with }
import super.inputs.{ PackageError, PackagePhase, error_at, io_result, read_data }
import super.sha256.hex_digit
import super.version

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

pub fn git_commit(read previous: Lock?, read name: Text, read prefix: Text, read selector: Text): String {
    if let present(lock) = previous {
        for package in lock.packages.as_slice() {
            if package.name.as_text() != name { continue }
            if let present(commit) = package.source.as_text().strip_prefix(read prefix) {
                for recorded in package.git_selectors.as_slice() {
                    if recorded.as_text() == selector { return from_text(commit) }
                }
            }
        }
    }
    new()
}

pub fn preferred(read previous: Lock?): Map<String, List<version.Version>> {
    var versions = Map<String, List<version.Version>>()
    if let present(old) = previous {
        for package in old.packages.as_slice() {
            match take version.parse(package.version.as_text()) {
                present(value) => {
                    let name = package.name.as_text()
                    if !versions.contains_key(name) { let _ = versions.insert(from_text(name), List<version.Version>()) }
                    let present(items) = versions.get_mut(name) else { panic("missing preferred version list") }
                    items.push(take value)
                },
                none => {}
            }
        }
    }
    versions
}

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
        var features = List<String>()
        for feature in package.features.as_slice() { features.push(from_text(feature.as_text())) }
        var dependencies = List<String>()
        for edge in package.dependencies.as_slice() {
            dependencies.push(from_text(graph.packages[edge.package].identity.as_text()))
        }
        var selectors = List<String>()
        for selector in package.git_selectors.as_slice() { selectors.push(from_text(selector.as_text())) }
        packages.push(LockedPackage(from_text(package.name.as_text()), from_text(package.version.as_text()),
            from_text(package.identity.as_text()), from_text(package.source.as_text()), take checksum,
            take features, take dependencies, take selectors, Range(0, 0)))
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

fn describe_list(read items: List<String>): String {
    var text = from_text("[")
    var first = true
    for item in items.as_slice() {
        if !first { text.push_str(", ") }
        first = false
        text.push_str(item.as_text())
    }
    text.push(']')
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
        let different_features = then.features.as_slice() != now.features.as_slice()
        let different_dependencies = then.dependencies.as_slice() != now.dependencies.as_slice()
        if different_features {
            let before = describe_list(then.features)
            let after = describe_list(now.features)
            detail.push_str(format(f"; package '{name}' features change from {before} to {after}").as_text())
        }
        if different_dependencies {
            let before = describe_list(then.dependencies)
            let after = describe_list(now.dependencies)
            detail.push_str(format(f"; package '{name}' dependencies change from {before} to {after}").as_text())
        }
        let different_selectors = then.git_selectors.as_slice() != now.git_selectors.as_slice()
        if different_selectors {
            let before = describe_list(then.git_selectors)
            let after = describe_list(now.git_selectors)
            detail.push_str(format(f"; package '{name}' Git selectors change from {before} to {after}").as_text())
        }
        if span.is_none() && (then.name.as_text() != name || then.version.as_text() != version ||
            then.source.as_text() != now.source.as_text() || then.checksum.as_text() != now.checksum.as_text() ||
            different_features || different_dependencies || different_selectors) {
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
        for now in current.packages.as_slice() {
            let source = now.source.as_text()
            if !source.starts_with("registry+") && !source.starts_with("git+") { continue }
            let id = now.id.as_text()
            let present(index) = old.indices.get(id) else { continue }
            let then = read old.packages[*index]
            let release = now.version.as_text()
            let before = then.checksum.as_text()
            let after = now.checksum.as_text()
            if then.source.as_text() != source || then.version.as_text() != release || before == after { continue }
            if before.starts_with("sha256:") {
                var migrated = false
                for package in graph.packages.as_slice() {
                    if package.identity.as_text() == id {
                        let legacy = try hash_legacy_tree(package.directory.as_path())
                        migrated = legacy.as_text() == before
                        break
                    }
                }
                if migrated { continue }
            }
            let name = now.name.as_text()
            throw error_at(path, then.span, format(f"checksum mismatch for immutable package '{name}' {release}: the lock records {before} but its sources hash to {after}; either the package or lock.mettle was altered"), PackagePhase.Lock)
        }
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

fn fixture_file(read root: Path, read fixture: Path, read relative: Text): Unit throws PackageError {
    let start = Range(0, 0)
    let original = fixture.join(relative)
    let destination = root.join(relative)
    let parent = destination.parent().or_panic()
    try io_result(take capture fs.create_dir_all(parent), root, start, PackagePhase.Io)
    let _ = try io_result(take capture fs.copy(original, destination), root, start, PackagePhase.Io)
}

fn migration_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages/path-dependency")
    let inputs = ["app/package.mettle", "app/src/main.mt", "mathlib/package.mettle", "mathlib/src/main.mt",
        "mathlib/src/twice.mt", "units/package.mettle", "units/src/main.mt"]
    for relative in inputs { try fixture_file(root, fixture, relative) }
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

fn feature_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages/features")
    let inputs = ["app/package.mettle", "app/src/main.mt", "widget/package.mettle", "widget/src/main.mt",
        "extra/package.mettle", "extra/src/main.mt"]
    for relative in inputs { try fixture_file(root, fixture, relative) }
    let app = root.join("app")
    let path = app.join("lock.mettle")
    let initial = try resolve_locked(app.as_path(), "main", false)
    assert(initial.packages.len() == 2, "an inactive optional dependency was resolved")
    assert(initial.packages[0].features[0].as_text() == "default" && initial.packages[1].features.is_empty(),
        "root defaults or dependency default suppression were lost")
    let original = try io_result(take capture fs.read_to_string(path), root, start, PackagePhase.Io)
    var options = ResolveOptions()
    options.default_features = false
    options.features.push(from_text("fancy"))
    options.locked = true
    match take capture resolve_with(app.as_path(), "main", options) {
        success(_) => assert(false, "a lock for a different feature context was accepted"),
        failure(issue) => assert(issue.message.as_text().find("features change from [default] to [fancy]").is_present(),
            "wrong feature context diagnostic")
    }

    let unchanged = try io_result(take capture fs.read_to_string(path), root, start, PackagePhase.Io)
    assert(unchanged.as_text() == original.as_text(), "locked feature changes replaced the lock")
    options.locked = false
    let selected = try resolve_with(app.as_path(), "main", options)
    assert(selected.packages.len() == 3 && selected.packages[0].features.len() == 1 &&
        selected.packages[0].features[0].as_text() == "fancy", "root requested/no-default feature context is incorrect")
    assert(selected.packages[1].features.len() == 1 && selected.packages[1].features[0].as_text() == "fancy" &&
        selected.packages[2].name.as_text() == "extra", "forwarded feature did not activate the optional dependency")
    options.locked = true
    let _ = try resolve_with(app.as_path(), "main", options)

    let bridge = root.join("bridge")
    let bridge_src = bridge.join("src")
    try io_result(take capture fs.create_dir_all(bridge_src), root, start, PackagePhase.Io)
    try io_result(take capture fs.write(bridge_src.join("main.mt"), "pub fn value(): i32 { 0 }\n".as_bytes()), root, start, PackagePhase.Io)
    try io_result(take capture fs.write(bridge.join("package.mettle"),
        "name: \"bridge\"\nversion: \"0.1.0\"\nkind: \"library\"\ndependencies { widget { path: \"../widget\", features: [\"fancy\"] } }\n".as_bytes()),
        root, start, PackagePhase.Io)
    try io_result(take capture fs.write(app.join("package.mettle"),
        "name: \"feature-app\"\nversion: \"0.1.0\"\ndependencies { widget { path: \"../widget\", default_features: false }, bridge: \"../bridge\" }\n".as_bytes()),
        root, start, PackagePhase.Io)
    let diamond = try resolve_locked(app.as_path(), "main", false)
    let app_package = read diamond.packages[0]
    let widget = app_package.dependencies[1].package
    let via_bridge = read diamond.packages[app_package.dependencies[0].package]
    assert(via_bridge.dependencies[0].package == widget && diamond.packages.len() == 4, "diamond did not reuse the package instance")
    let features = read diamond.packages[widget].features
    assert(features.len() == 3 && features[0].as_text() == "basic" && features[1].as_text() == "default" &&
        features[2].as_text() == "fancy", "incoming default and explicit features did not unify")
}

fn with_fixture(read suffix: Text, run: fn(read Path): Unit throws PackageError): Unit throws PackageError {
    let pid = process.id()
    let name = format(f"mettle-path-lock-{suffix}-{pid}")
    let root = env.temp_dir().join(name.as_text())
    let path = root.as_path()
    let start = Range(0, 0)
    try io_result(take capture fs.create_dir(path), path, start, PackagePhase.Io)
    let tested = capture run(path)
    try io_result(take capture fs.remove_dir_all(path), path, start, PackagePhase.Io)
    match take tested {
        success(_) => (),
        failure(issue) => { throw issue }
    }
}

@test
fn path_lock_migration_and_drift(): Unit throws PackageError {
    try with_fixture("migration", migration_fixture)
}

@test
fn path_feature_lock_context(): Unit throws PackageError {
    try with_fixture("features", feature_fixture)
}

fn development_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages")
    for relative in ["path-dependency/app/package.mettle", "path-dependency/app/src/main.mt",
            "path-dependency/mathlib/package.mettle", "path-dependency/mathlib/src/main.mt",
            "path-dependency/mathlib/src/twice.mt", "path-dependency/units/package.mettle",
            "path-dependency/units/src/main.mt", "features/extra/package.mettle", "features/extra/src/main.mt"] {
        try fixture_file(root, fixture, relative)
    }
    let app = root.join("path-dependency/app")
    let manifest = app.join("package.mettle")
    let lockfile = app.join("lock.mettle")
    let extra = root.join("features/extra/package.mettle")
    var child = try io_result(take capture fs.read_to_string(extra), root, start, PackagePhase.Io)
    child.push_str("\ndev-dependencies { missing: \"../missing\" }\n")
    try io_result(take capture fs.write(extra, child.as_bytes()), root, start, PackagePhase.Io)
    var source = try io_result(take capture fs.read_to_string(manifest), root, start, PackagePhase.Io)
    source.push_str("\ndev-dependencies { extra: \"../../features/extra\", mathlib: \"../mathlib\" }\n")
    try io_result(take capture fs.write(manifest, source.as_bytes()), root, start, PackagePhase.Io)

    let normal = try resolve_locked(app.as_path(), "main", false)
    assert(normal.packages.len() == 3 && normal.packages[0].dependencies.len() == 1, "normal resolution activated a development dependency")
    let initial = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    var options = ResolveOptions()
    options.include_dev = true
    options.locked = true
    match take capture resolve_with(app.as_path(), "main", options) {
        success(_) => assert(false, "a normal lock was accepted in the development context"),
        failure(issue) => assert(issue.message.as_text().find("package 'extra' 0.1.0 is not in the lock").is_present(),
            "wrong development lock difference")
    }
    let unchanged = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    assert(unchanged.as_text() == initial.as_text(), "locked development resolution rewrote the lock")

    options.locked = false
    let development = try resolve_with(app.as_path(), "main", options)
    let edges = read development.packages[0].dependencies
    assert(development.packages.len() == 4 && edges.len() == 2 && edges[1].name.as_text() == "mathlib",
        "development resolution duplicated an alias or expanded a dependency's own development dependencies")
    let selected = read development.packages[edges[0].package]
    assert(edges[0].name.as_text() == "extra" && selected.dependencies.is_empty(), "wrong root development edge")
    options.locked = true
    let _ = try resolve_with(app.as_path(), "main", options)
    require_lock_failure(app.as_path(), "package 'extra' is no longer used")

    var invalid = from_text(source.as_text().split_once("\ndev-dependencies").or_panic().0)
    invalid.push_str("\ndev-dependencies { extra { path: \"../../features/extra\", optional: true } }\n")
    try io_result(take capture fs.write(manifest, invalid.as_bytes()), root, start, PackagePhase.Io)
    match take capture resolve_locked(app.as_path(), "main", false) {
        success(_) => assert(false, "normal resolution accepted an optional development dependency"),
        failure(issue) => assert(issue.message.as_text() == "development dependencies cannot be optional", "wrong development manifest error")
    }
}

@test
fn root_development_dependencies_change_lock_reachability(): Unit throws PackageError {
    try with_fixture("development", development_fixture)
}

fn registry_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages")
    for relative in ["registry-resolution/app/package.mettle", "registry-resolution/app/src/main.mt",
            "registry/shapes/1.2.0/package.mettle", "registry/shapes/1.2.0/src/main.mt",
            "registry/util/1.3.0/package.mettle", "registry/util/1.3.0/src/main.mt",
            "registry/util/1.4.0/package.mettle", "registry/util/1.4.0/src/main.mt", "registry/util/1.4.0/YANKED"] {
        try fixture_file(root, fixture, relative)
    }
    let app = root.join("registry-resolution/app")
    let lockfile = app.join("lock.mettle")
    let chosen = try resolve_locked(app.as_path(), "main", false)
    let shapes = read chosen.packages[chosen.packages[0].dependencies[0].package]
    let util = read chosen.packages[shapes.dependencies[0].package]
    assert(shapes.identity.as_text() == "shapes@1.2.0|registry+../../registry|target" &&
        util.identity.as_text() == "util@1.3.0|registry+../../registry|target", "wrong transitive registry provenance or yanked choice")
    let initial = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    let previous = (try load(lockfile.as_path(), true)).or_panic()
    let legacy = try hash_legacy_tree(util.directory.as_path())
    let index = previous.indices.get(util.identity.as_text()).or_panic()
    let checksum = previous.packages[*index].checksum.as_text()
    assert(checksum == "sha256-tree-2:5ad960b760e1a46a3de0bf5f62cd521748a6a6bd2762a870d4583bed1a9c8b10",
        "registry checksum differs from the bootstrap lock")
    let (prefix, suffix) = initial.as_text().split_once(checksum).or_panic()
    var legacy_lock = from_text(prefix)
    legacy_lock.push_str(legacy.as_text())
    legacy_lock.push_str(suffix)
    try io_result(take capture fs.write(lockfile, legacy_lock.as_bytes()), root, start, PackagePhase.Io)
    require_lock_failure(app.as_path(), "content changed")
    let _ = try resolve_locked(app.as_path(), "main", false)

    let marker = root.join("registry/util/1.4.0/YANKED")
    try io_result(take capture fs.remove_file(marker), root, start, PackagePhase.Io)
    let marker = util.directory.join("YANKED")
    try io_result(take capture fs.write(marker, "".as_bytes()), root, start, PackagePhase.Io)
    let _ = try resolve_locked(app.as_path(), "main", true)
    let input = util.directory.join("data.txt")
    try io_result(take capture fs.write(input, "changed build input\n".as_bytes()), root, start, PackagePhase.Io)
    require_lock_failure(app.as_path(), "checksum mismatch for immutable package 'util' 1.3.0")
    match take capture resolve_locked(app.as_path(), "main", false) {
        success(_) => assert(false, "an unlocked resolution replaced a tampered checksum"),
        failure(issue) => assert(issue.message.as_text().find("checksum mismatch for immutable package 'util' 1.3.0").is_present(),
            "wrong unlocked registry checksum error")
    }
    let current = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    assert(current.as_text() == initial.as_text(), "registry pin, migration or tampering changed the lock")
}

@test
fn registry_lock_preserves_release_and_rejects_tampering(): Unit throws PackageError {
    try with_fixture("registry", registry_fixture)
}

fn host_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages/host-target-separation")
    for relative in ["app/package.mettle", "app/src/main.mt", "app/build.mt", "helper/package.mettle", "helper/src/main.mt"] {
        try fixture_file(root, fixture, relative)
    }
    let app = root.join("app")
    let lockfile = app.join("lock.mettle")
    let graph = try resolve_locked(app.as_path(), "main", false)
    let edges = read graph.packages[0].dependencies
    let target = read graph.packages[edges[0].package]
    let host = read graph.packages[edges[1].package]
    assert(edges.len() == 2 && !edges[0].is_host && edges[1].is_host && !target.is_host && host.is_host,
        "build-script mounting context was not separated")
    assert(target.identity.as_text() == "helper@0.1.0|path+../helper|target" &&
        host.identity.as_text() == "helper@0.1.0|path+../helper|host", "host and target identities differ from bootstrap")
    assert(target.features.len() == 1 && target.features[0].as_text() == "target" &&
        host.features.len() == 1 && host.features[0].as_text() == "host", "features leaked between host and target")
    assert(graph.build_scripts.len() == 1 && graph.build_scripts[0].package == 0, "wrong build script owner")
    let current = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    assert(current.as_text().find("dependencies: [\"helper@0.1.0|path+../helper|target\", \"helper@0.1.0|path+../helper|host\"]").is_present(),
        "host and target edges were not locked in bootstrap order")
    let _ = try resolve_locked(app.as_path(), "main", true)
    let manifest = app.join("package.mettle")
    let input = try io_result(take capture fs.read_to_string(manifest), root, start, PackagePhase.Io)
    let (target_only, _) = input.as_text().split_once("\"build-dependencies\"").or_panic()
    try io_result(take capture fs.write(manifest, target_only.as_bytes()), root, start, PackagePhase.Io)
    require_lock_failure(app.as_path(), "dependencies change from")
    let unchanged = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    assert(unchanged.as_text() == current.as_text(), "locked host drift rewrote the lock")
}

@test
fn host_instances_keep_separate_features_and_lock_edges(): Unit throws PackageError {
    try with_fixture("host", host_fixture)
}

fn macro_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages")
    for relative in ["proc-macro/app/package.mettle", "proc-macro/app/src/main.mt", "proc-macro/genfn/package.mettle",
            "proc-macro/genfn/macros/make_fn.mt", "host-target-separation/helper/package.mettle",
            "host-target-separation/helper/src/main.mt"] {
        try fixture_file(root, fixture, relative)
    }
    let manifest = root.join("proc-macro/genfn/package.mettle")
    var source = try io_result(take capture fs.read_to_string(manifest), root, start, PackagePhase.Io)
    source.push_str("\ndependencies { helper { path: \"../../host-target-separation/helper\", optional: true, default_features: false } }\n")
    source.push_str("features { default: [\"helper/host\"] }\n")
    try io_result(take capture fs.write(manifest, source.as_bytes()), root, start, PackagePhase.Io)
    let app = root.join("proc-macro/app")
    let graph = try super.graph.resolve(app.as_path(), "main")
    let planned = read graph.macros[0]
    let package = read graph.packages[planned.package]
    assert(graph.macros.len() == 1 && package.entry.is_none() && !package.is_library && !package.is_host &&
        planned.name.as_text() == "make_fn" && planned.api == 1u32, "wrong procedural macro owner or API")
    assert(planned.source.is_absolute() && planned.source.file_name().or_panic().same(std.ffi.os_str_from_text("make_fn.mt")),
        "macro program path was not resolved")
    assert(package.dependencies.len() == 2 && !package.dependencies[0].is_host && package.dependencies[1].is_host,
        "macro feature forwarding did not mirror dependency activation")
    for edge in package.dependencies.as_slice() {
        let features = read graph.packages[edge.package].features
        assert(features.len() == 1 && features[0].as_text() == "host", "forwarded macro feature was lost")
    }
    let program = root.join("proc-macro/genfn/macros/make_fn.mt")
    try io_result(take capture fs.remove_file(program), root, start, PackagePhase.Io)
    match take capture resolve_locked(app.as_path(), "main", false) {
        success(_) => assert(false, "a missing macro source was accepted"),
        failure(issue) => assert(issue.message.as_text() == "macro source 'macros/make_fn.mt' does not exist", "wrong missing macro diagnostic")
    }
}

@test
fn procedural_macro_plans_host_feature_edges_without_a_library(): Unit throws PackageError {
    try with_fixture("macros", macro_fixture)
}

@test
fn host_script_plan_is_dependency_first(): Unit throws PackageError {
    let graph = try super.graph.resolve(std.path.path_from_text("tests/packages/driver-contracts/host-script-order/app"), "main")
    let scripts = read graph.build_scripts
    assert(scripts.len() == 2 && scripts[1].package == 0 && graph.packages[scripts[0].package].is_host,
        "host dependency script must precede the root script")
}

fn fixture_git(read repository: Path, read operation: Text, read argument: Text, read value: Text = ""): Unit throws PackageError {
    var git = process.command_text("git")
    git.current_dir(repository)
    for option in ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false", "-c", "tag.gpgSign=false"] {
        git.arg_text(option)
    }
    git.arg_text(operation)
    git.arg_text(argument)
    if !value.is_empty() { git.arg_text(value) }
    let output = try io_result(take capture git.output(), repository, Range(0, 0), PackagePhase.Package)
    if !output.status.succeeded() {
        let detail = alloc.string.from_utf8_lossy(output.stderr.as_slice())
        let message = detail.as_text()
        throw error_at(repository, Range(0, 0), format(f"fixture git command failed: {message}"), PackagePhase.Package)
    }
}

fn require_git_failure(read app: Path, read options: ResolveOptions, read reason: Text): Unit {
    match take capture resolve_with(app, "main", options) {
        success(_) => assert(false, "Git resolution should have failed"),
        failure(issue) => assert(issue.message.as_text().find(read reason).is_present(), "wrong Git resolution error")
    }
}

fn git_fixture(read root: Path): Unit throws PackageError {
    let start = Range(0, 0)
    let fixture = std.path.path_from_text("tests/packages/driver-contracts/git-script")
    for relative in ["app/package.mettle", "app/src/main.mt", "repository/package.mettle", "repository/src/main.mt",
            "repository/build.mt", "repository/macros/git_value.mt", "repository/nested/helper/package.mettle",
            "repository/nested/helper/src/main.mt", "repository/nested/helper/build.mt", "repository/spec.txt"] {
        try fixture_file(root, fixture, relative)
    }
    let repository = root.join("repository")
    let directory = repository.as_path()
    let repository_manifest = repository.join("package.mettle")
    let text = try io_result(take capture fs.read_to_string(repository_manifest), root, start, PackagePhase.Io)
    let (before, after) = text.as_text().split_once("    outside { path: \"../outside\" }\n").or_panic()
    var input = from_text(before)
    input.push_str(after)
    try io_result(take capture fs.write(repository_manifest, input.as_bytes()), root, start, PackagePhase.Io)
    try fixture_git(directory, "init", "-b", "main")
    try fixture_git(directory, "config", "user.name", "Mettle fixture")
    try fixture_git(directory, "config", "user.email", "fixture@example.invalid")
    try fixture_git(directory, "add", ".")
    try fixture_git(directory, "commit", "-m", "first fixture revision")
    try fixture_git(directory, "tag", "first")

    let app = root.join("app")
    let manifest = app.join("package.mettle")
    let template = try io_result(take capture fs.read_to_string(manifest), root, start, PackagePhase.Io)
    let (before, after) = template.as_text().split_once("__GIT_URL__").or_panic()
    let url = repository.to_str().or_panic()
    let quoted = format(f"{before}{url}{after}")
    try io_result(take capture fs.write(manifest, quoted.as_bytes()), root, start, PackagePhase.Io)
    var options = ResolveOptions()
    options.cache_dir = present(root.join("cache"))
    options.offline = true
    require_git_failure(app.as_path(), options, "offline mode has no cached repository")
    options.offline = false
    let graph = try resolve_with(app.as_path(), "main", options)
    let package = read graph.packages[graph.packages[0].dependencies[0].package]
    let provenance = package.source.as_text()
    assert(package.git_selectors.len() == 1 && package.git_selectors[0].as_text() == "branch=main", "branch selector was not tracked")
    let expected = format(f"path+{provenance}/nested/helper")
    assert(package.dependencies.len() == 2 && graph.packages[package.dependencies[0].package].source.as_text() == expected.as_text() &&
        graph.packages[package.dependencies[1].package].source.as_text() == expected.as_text(), "nested host/target Git path depends on the cache location")
    let lockfile = app.join("lock.mettle")
    let initial = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    assert(initial.as_text().find("git_selectors: [\"branch=main\"]").is_present(), "lock omitted Git selector provenance")

    try io_result(take capture fs.write(repository.join("spec.txt"), "second revision".as_bytes()), root, start, PackagePhase.Io)
    try fixture_git(directory, "add", "spec.txt")
    try fixture_git(directory, "commit", "-m", "second fixture revision")
    options.locked = true
    require_git_failure(app.as_path(), options, "--locked forbids changing it")
    options.offline = true
    let frozen = try resolve_with(app.as_path(), "main", options)
    assert(frozen.packages[frozen.packages[0].dependencies[0].package].source.as_text() == provenance,
        "offline resolution used the updated branch rather than its locked commit")

    let (before, after) = quoted.as_text().split_once("branch: \"main\"").or_panic()
    let changed = format(f"{before}tag: \"first\"{after}")
    try io_result(take capture fs.write(manifest, changed.as_bytes()), root, start, PackagePhase.Io)
    require_git_failure(app.as_path(), options, "Git selectors change from [branch=main] to [tag=first]")
    try io_result(take capture fs.write(manifest, quoted.as_bytes()), root, start, PackagePhase.Io)
    try io_result(take capture fs.write(package.directory.join("untracked.txt"), "dirty".as_bytes()), root, start, PackagePhase.Io)
    require_git_failure(app.as_path(), options, "cached checkout contains modified or untracked files")
    let unchanged = try io_result(take capture fs.read_to_string(lockfile), root, start, PackagePhase.Io)
    assert(unchanged.as_text() == initial.as_text(), "Git errors altered the lock")
}

@test
fn git_revisions_lock_provenance_and_never_fetch_offline(): Unit throws PackageError {
    try with_fixture("git", git_fixture)
}
