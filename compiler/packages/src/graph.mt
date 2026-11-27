import alloc.hash_map.{ Map, Set }
import alloc.string.{ String, from_text }
import alloc.vec.List
import alloc.vec_deque.{ Deque, new }
import core.cmp.Ordering
import core.text.Text
import std.{ fs, io }
import std.macros.format
import std.path.{ Path, PathBuf }
import super.data.Range
import super.inputs.{ PackageError, PackagePhase, error_at, io_result, read_data, relative_to }
import super.lock
import super.manifest.{ Manifest, Dependency, FeatureAction, decode }
import super.version

pub type DependencyEdge { pub name: String; pub package: usize; span: Range }
pub type ResolvedPackage {
    pub name: String
    pub version: String
    pub identity: String
    pub source: String
    pub directory: PathBuf
    pub entry: PathBuf
    pub is_library: bool
    pub dependencies: List<DependencyEdge>
    pub features: List<String>
}
pub type PackageGraph { pub packages: List<ResolvedPackage> }

pub type ResolveOptions { pub features: List<String>; pub default_features: bool; pub locked: bool }

extend ResolveOptions {
    pub init() {
        self.features = List<String>()
        self.default_features = true
        self.locked = false
    }
}

copy type Frame { index: usize; next: usize }
type SelectedEntry { path: PathBuf; is_library: bool }
type PackageFeatures {
    version: version.Version
    dependencies: List<Dependency>
    selected: List<usize?>
    actions: Map<String, List<FeatureAction>>
    implicit: Map<String, usize>
    enabled: Set<String>
    defaults: bool
}
type Request { parent: usize; slot: usize; forward: String? }
type Solver {
    graph: PackageGraph
    targets: List<PackageFeatures>
    visited: Map<PathBuf, usize>
    work: Deque<Request>
}

fn error(read path: Path, span: Range, take message: String): PackageError {
    error_at(path, span, take message, PackagePhase.Package)
}

fn load(read directory: Path): Manifest throws PackageError {
    let manifest_path = directory.join("package.mettle")
    let path = manifest_path.as_path()
    let start = Range(0, 0)
    let data = (try read_data(path, PackagePhase.Manifest, false)).or_panic()
    let default_entry = if data.field(0, "entry").is_present() || data.field(0, "kind").is_present() ||
        data.field(0, "emit").is_present() { false } else {
        let source = directory.join("src/main.mt")
        match take capture fs.metadata(source) {
            success(_) => true,
            failure(issue) => match issue.kind() {
                io.ErrorKind.NotFound => false,
                _ => { throw error(path, start, issue.message()) }
            },
        }
    }
    match take capture decode(data, default_entry) {
        success(manifest) => take manifest,
        failure(issue) => { throw error(path, issue.span, take issue.message) }
    }
}

fn select_entry(read manifest: Manifest, read directory: Path, read entry: Text, root: bool): SelectedEntry throws PackageError {
    let manifest_path = directory.join("package.mettle")
    for target in manifest.targets.as_slice() {
        if (root && target.name.as_text() == entry) || (!root && target.library) {
            let source = directory.join(target.source.as_text())
            let source_path = source.as_path()
            let properties = try io_result(take capture fs.metadata(source_path), manifest_path.as_path(), target.span, PackagePhase.Package)
            if !properties.is_file() {
                let name = target.source.as_text()
                throw error(manifest_path.as_path(), target.span, format(f"source entry '{name}' is not a regular file"))
            }
            let canonical = try io_result(take capture fs.canonicalize(source_path), manifest_path.as_path(), target.span, PackagePhase.Package)
            return SelectedEntry(take canonical, target.library)
        }
    }
    let name = manifest.name.as_text()
    let reason = if !root { format(f"package '{name}' has no library entry") }
        else if entry.as_bytes() == "main".as_bytes() { format(f"package '{name}' has no source entry") }
        else { format(f"package '{name}' has no entry '{entry}'") }
    throw error(manifest_path.as_path(), manifest.span, take reason)
}

fn check_requirement(read dependency: Dependency, read candidate: version.Version, read path: Path): Unit throws PackageError {
    if dependency.requirements.is_empty() { return }
    for requirement in dependency.requirements.as_slice() {
        if version.matches(requirement.as_text(), candidate) == present(true) { return }
    }
    let name = dependency.name.as_text()
    throw error(path, dependency.span, format(f"path dependency '{name}' does not satisfy its version requirement"))
}

pub fn resolve(read root: Path, read entry: Text): PackageGraph throws PackageError {
    try plan(root, entry, ResolveOptions(), false)
}

pub fn resolve_locked(read root: Path, read entry: Text, locked: bool): PackageGraph throws PackageError {
    var options = ResolveOptions()
    options.locked = locked
    try resolve_with(root, entry, options)
}

pub fn resolve_with(read root: Path, read entry: Text, read options: ResolveOptions): PackageGraph throws PackageError {
    try plan(root, entry, options, true)
}

fn plan(read root: Path, read entry: Text, read options: ResolveOptions, publish_lock: bool): PackageGraph throws PackageError {
    let start = Range(0, 0)
    let root_directory = try io_result(take capture fs.canonicalize(root), root, start, PackagePhase.Package)
    let directory = root_directory.as_path()
    let manifest = try load(directory)
    let source = try select_entry(manifest, directory, entry, true)
    let lock_path = directory.join("lock.mettle")
    let recorded = if publish_lock { try lock.load(lock_path.as_path(), options.locked) } else { none }
    let manifest_path = directory.join("package.mettle")
    let span = manifest.span
    var solver = Solver(PackageGraph(List<ResolvedPackage>()), List<PackageFeatures>(), Map<PathBuf, usize>(), new<Request>())
    let _ = solver.register(take manifest, take root_directory, take source, from_text("root"))
    try solver.enable(0, feature_queue(options.features), options.default_features, manifest_path.as_path(), span)
    loop {
        let request = match take solver.work.pop_front() {
            present(item) => take item,
            none => { break }
        }
        try solver.resolve_edge(take request)
    }
    try solver.finish()
    if publish_lock {
        let root = solver.graph.packages[0].directory.as_path()
        try lock.reconcile(solver.graph, root, lock_path.as_path(), take recorded, options.locked)
    }
    take solver.graph
}

fn feature_queue(read features: List<String>): Deque<String> {
    var pending = new<String>()
    for feature in features.as_slice() { pending.push_back(from_text(feature.as_text())) }
    pending
}

extend Solver {
    mut fn register(take manifest: Manifest, take directory: PathBuf, take entry: SelectedEntry, take source: String): usize {
        let index = self.graph.packages.len()
        let name = manifest.name.as_text()
        let version_text = manifest.version_text.as_text()
        let source_text = source.as_text()
        let id = format(f"{name}@{version_text}|{source_text}|target")
        var selected = List<usize?>()
        selected.resize(manifest.dependencies.len(), none)
        var i = 0usize
        while i < manifest.dependencies.len() {
            if !manifest.dependencies[i].optional { self.work.push_back(Request(index, i, none)) }
            i += 1
        }
        let _ = self.visited.insert(directory.to_path_buf(), self.graph.packages.len())
        self.graph.packages.push(ResolvedPackage(take manifest.name, take manifest.version_text, take id, take source,
            take directory, take entry.path, entry.is_library, List<DependencyEdge>(), List<String>()))
        self.targets.push(PackageFeatures(take manifest.version, take manifest.dependencies, take selected, take manifest.features,
            take manifest.implicit_features, Set<String>(), false))
        index
    }

    mut fn enable(index: usize, take requested: Deque<String>, defaults: bool, read origin: Path, span: Range): Unit throws PackageError {
        var pending = take requested
        if defaults && !self.targets[index].defaults {
            self.targets[index].defaults = true
            if self.targets[index].actions.contains_key("default") { pending.push_back(from_text("default")) }
        }
        loop {
            let feature = match take pending.pop_front() {
                present(item) => take item,
                none => { break }
            }
            let name = feature.as_text()
            if !self.targets[index].enabled.insert(from_text(name)) { continue }
            if let present(actions) = self.targets[index].actions.get(name) {
                for action in actions.as_slice() {
                    match read action {
                        FeatureAction.Local(local_feature) => pending.push_back(from_text(local_feature.as_text())),
                        FeatureAction.Activate(slot) => self.work.push_back(Request(index, slot, none)),
                        FeatureAction.Forward(slot, name) => self.work.push_back(Request(index, slot, present(from_text(name.as_text()))))
                    }
                }
            } else if let present(slot) = self.targets[index].implicit.get(name) {
                self.work.push_back(Request(index, *slot, none))
            } else {
                let package_name = self.graph.packages[index].name.as_text()
                throw error(origin, span, format(f"package '{package_name}' has no feature '{name}'"))
            }
            self.graph.packages[index].features.push(take feature)
        }
    }

    mut fn resolve_edge(take request: Request): Unit throws PackageError {
        let owner = request.parent
        let slot = request.slot
        let span = self.targets[owner].dependencies[slot].span
        let owner_path = self.graph.packages[owner].directory.join("package.mettle")
        let origin = owner_path.as_path()
        let index = match self.targets[owner].selected[slot] {
            present(chosen) => chosen,
            none => try self.activate_dependency(owner, slot, origin, span)
        }
        match take request.forward {
            present(feature) => {
                var pending = new<String>()
                pending.push_back(take feature)
                try self.enable(index, take pending, false, origin, span)
            },
            none => {}
        }
    }

    mut fn activate_dependency(owner: usize, slot: usize, read origin: Path, span: Range): usize throws PackageError {
        let dependency = read self.targets[owner].dependencies[slot]
        let name = from_text(dependency.name.as_text())
        let defaults = dependency.default_features
        let pending = feature_queue(dependency.features)
        let path = self.graph.packages[owner].directory.join(dependency.path.as_text())
        let directory = try io_result(take capture fs.canonicalize(path), origin, span, PackagePhase.Package)
        let index = if let present(chosen) = self.visited.get(directory) {
            let actual = self.graph.packages[*chosen].name.as_text()
            let expected = name.as_text()
            if actual != expected { throw error(origin, span, format(f"path dependency '{expected}' is the package '{actual}'")) }
            try check_requirement(dependency, self.targets[*chosen].version, origin)
            *chosen
        } else {
            let child = try load(directory.as_path())
            let actual = child.name.as_text()
            let expected = name.as_text()
            if actual != expected { throw error(origin, span, format(f"path dependency '{expected}' is the package '{actual}'")) }
            try check_requirement(dependency, child.version, origin)
            let source = try select_entry(child, directory.as_path(), "main", false)
            let relative = relative_to(self.graph.packages[0].directory.as_path(), directory.as_path())
            let present(relative_text) = relative.to_str() else {
                throw error(origin, span, from_text("package path is not valid UTF-8"))
            }
            let source_name = format(f"path+{relative_text}")
            self.register(take child, take directory, take source, take source_name)
        }
        self.targets[owner].selected[slot] = present(index)
        self.graph.packages[owner].dependencies.push(DependencyEdge(take name, index, span))
        try self.enable(index, take pending, defaults, origin, span)
        index
    }

    mut fn finish(): Unit throws PackageError {
        var i = 0usize
        while i < self.graph.packages.len() {
            self.graph.packages[i].dependencies.as_mut_slice().sort_unstable_by(fn(read a: DependencyEdge, read b: DependencyEdge): Ordering {
                a.name.as_text().cmp(b.name.as_text())
            })
            self.graph.packages[i].features.as_mut_slice().sort_unstable_by(fn(read a: String, read b: String): Ordering {
                a.as_text().cmp(b.as_text())
            })
            i += 1
        }
        try validate_cycles(self.graph)
    }
}

fn validate_cycles(read graph: PackageGraph): Unit throws PackageError {
    var color = List<u8>()
    color.resize(graph.packages.len(), 0u8)
    color[0] = 1u8
    var stack = List<Frame>()
    stack.push(Frame(0, 0))
    while !stack.is_empty() {
        let top = stack.len() - 1
        let node = stack[top].index
        let next = stack[top].next
        let package = read graph.packages[node]
        if next == package.dependencies.len() {
            color[node] = 2u8
            let _ = stack.pop()
            continue
        }
        stack[top].next += 1
        let edge = read package.dependencies[next]
        if color[edge.package] == 0 {
            color[edge.package] = 1u8
            stack.push(Frame(edge.package, 0))
        } else if color[edge.package] == 1 {
            var message = from_text("dependency cycle: ")
            var in_cycle = false
            for frame in stack.as_slice() {
                in_cycle = in_cycle || frame.index == edge.package
                if in_cycle {
                    let step = read graph.packages[frame.index]
                    let name = step.name.as_text()
                    let release = step.version.as_text()
                    message.push_str(format(f"{name} {release} -> ").as_text())
                }
            }
            let target = read graph.packages[edge.package]
            let name = target.name.as_text()
            let release = target.version.as_text()
            message.push_str(format(f"{name} {release}; cyclic package compilation is not supported").as_text())
            let path = package.directory.join("package.mettle")
            throw error(path.as_path(), edge.span, take message)
        }
    }
}

@test
fn transitive_path_graph(): Unit throws PackageError {
    let graph = try resolve(std.path.path_from_text("tests/packages/path-dependency/app"), "main")
    assert(graph.packages.len() == 3, "transitive dependency is missing")
    let app = read graph.packages[0]
    assert(app.name.as_text() == "path-app" && app.dependencies.len() == 1, "incorrect root package")
    let math = read graph.packages[app.dependencies[0].package]
    assert(math.name.as_text() == "mathlib" && math.dependencies.len() == 1, "incorrect direct dependency")
    let units = read graph.packages[math.dependencies[0].package]
    assert(units.name.as_text() == "units" && units.version.as_text() == "0.1.4", "incorrect transitive dependency")
    assert(!app.is_library && units.is_library, "selected target kind was discarded")
    assert(units.entry.file_name().or_panic().same(std.ffi.os_str_from_text("main.mt")), "wrong dependency library source")
    match take capture resolve(std.path.path_from_text("tests/packages/path-dependency/app"), "missing") {
        success(_) => assert(false, "undeclared entry resolved"),
        failure(issue) => assert(issue.message.as_text() == "package 'path-app' has no entry 'missing'", "wrong entry diagnostic")
    }
}

@test
fn coexisting_path_versions(): Unit throws PackageError {
    let graph = try resolve(std.path.path_from_text("tests/packages/coexisting-versions/app"), "main")
    let root = read graph.packages[0]
    let direct = root.dependencies[0].package
    let bridge = read graph.packages[root.dependencies[1].package]
    let indirect = bridge.dependencies[0].package
    let first = read graph.packages[direct]
    let second = read graph.packages[indirect]
    assert(first.name.as_text() == "alpha" && second.name.as_text() == "alpha", "wrong dependency identity")
    assert(first.version.as_text() == "1.0.0" && second.version.as_text() == "2.0.0", "path versions were merged")
}

@test
fn suppressed_optional_alias(): Unit {
    var options = ResolveOptions()
    options.features.push(from_text("extra"))
    match take capture plan(std.path.path_from_text("tests/packages/features/widget"), "main", options, false) {
        success(_) => assert(false, "dep:extra left an implicit feature behind"),
        failure(issue) => assert(issue.message.as_text() == "package 'widget' has no feature 'extra'", "wrong suppressed feature diagnostic")
    }
}
