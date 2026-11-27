import alloc.hash_map.Map
import alloc.string.{ String, from_text }
import alloc.vec.List
import core.cmp.Ordering
import core.text.Text
import std.{ fs, io }
import std.macros.format
import std.path.{ Path, PathBuf }
import super.data.Range
import super.inputs.{ PackageError, PackagePhase, error_at, io_result, read_data, relative_to }
import super.lock
import super.manifest.{ Manifest, Dependency, decode }
import super.version

pub type DependencyEdge { pub name: String; pub package: usize }
pub type ResolvedPackage {
    pub name: String
    pub version: String
    pub identity: String
    pub source: String
    pub directory: PathBuf
    pub entry: PathBuf
    pub dependencies: List<DependencyEdge>
}
pub type PackageGraph { pub packages: List<ResolvedPackage> }

type Frame { index: usize; next: usize; dependencies: List<Dependency> }
type Visit { index: usize; version: version.Version }

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

fn entry_path(read manifest: Manifest, read directory: Path, read entry: Text, root: bool): PathBuf throws PackageError {
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
            return try io_result(take capture fs.canonicalize(source_path), manifest_path.as_path(), target.span, PackagePhase.Package)
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
    let start = Range(0, 0)
    let root_directory = try io_result(take capture fs.canonicalize(root), root, start, PackagePhase.Package)
    let directory = root_directory.as_path()
    let manifest = try load(directory)
    let source = try entry_path(manifest, directory, entry, true)
    try build_graph(directory, take manifest, take source)
}

pub fn resolve_locked(read root: Path, read entry: Text, locked: bool): PackageGraph throws PackageError {
    let start = Range(0, 0)
    let root_directory = try io_result(take capture fs.canonicalize(root), root, start, PackagePhase.Package)
    let directory = root_directory.as_path()
    let manifest = try load(directory)
    let source = try entry_path(manifest, directory, entry, true)
    let path = directory.join("lock.mettle")
    let recorded = try lock.load(path.as_path(), locked)
    let graph = try build_graph(directory, take manifest, take source)
    try lock.reconcile(graph, directory, path.as_path(), take recorded, locked)
    graph
}

fn build_graph(read root_directory: Path, take manifest: Manifest, take source: PathBuf): PackageGraph throws PackageError {
    var visits = Map<PathBuf, Visit>()
    let _ = visits.insert(root_directory.to_path_buf(), Visit(0, take manifest.version))
    var packages = List<ResolvedPackage>()
    let root_name = manifest.name.as_text()
    let root_version = manifest.version_text.as_text()
    let root_id = format(f"{root_name}@{root_version}|root|target")
    packages.push(ResolvedPackage(take manifest.name, take manifest.version_text, take root_id, from_text("root"),
        root_directory.to_path_buf(), take source, List<DependencyEdge>()))
    var active = List<bool>()
    active.push(true)
    var work = List<Frame>()
    work.push(Frame(0, 0, take manifest.dependencies))
    while !work.is_empty() {
        let frame = work.len() - 1
        let owner = work[frame].index
        let next = work[frame].next
        if next == work[frame].dependencies.len() {
            active[owner] = false
            packages[owner].dependencies.as_mut_slice().sort_unstable_by(fn(read a: DependencyEdge, read b: DependencyEdge): Ordering {
                a.name.as_text().cmp(b.name.as_text())
            })
            let _ = work.pop()
            continue
        }
        work[frame].next += 1
        let dependency = read work[frame].dependencies[next]
        let name = dependency.name.as_text()
        let owner_path = packages[owner].directory.join("package.mettle")
        let declared_by = owner_path.as_path()
        let path = packages[owner].directory.join(dependency.path.as_text())
        let directory = try io_result(take capture fs.canonicalize(path), declared_by, dependency.span, PackagePhase.Package)
        if let present(visit) = visits.get(directory) {
            if active[visit.index] { throw error(declared_by, dependency.span, format(f"dependency cycle involving '{name}'")) }
            let actual = packages[visit.index].name.as_text()
            if actual != name { throw error(declared_by, dependency.span, format(f"path dependency '{name}' is the package '{actual}'")) }
            try check_requirement(dependency, visit.version, declared_by)
            packages[owner].dependencies.push(DependencyEdge(from_text(name), visit.index))
            continue
        }
        let child = try load(directory.as_path())
        let actual = child.name.as_text()
        if actual != name { throw error(declared_by, dependency.span, format(f"path dependency '{name}' is the package '{actual}'")) }
        try check_requirement(dependency, child.version, declared_by)
        let source = try entry_path(child, directory.as_path(), "main", false)
        let relative = relative_to(root_directory, directory.as_path())
        let present(relative_text) = relative.to_str() else {
            throw error(declared_by, dependency.span, from_text("package path is not valid UTF-8"))
        }
        let version_text = child.version_text.as_text()
        let identity = format(f"{name}@{version_text}|path+{relative_text}|target")
        let lock_source = format(f"path+{relative_text}")
        let index = packages.len()
        let _ = visits.insert(directory.to_path_buf(), Visit(index, take child.version))
        active.push(true)
        packages[owner].dependencies.push(DependencyEdge(from_text(name), index))
        packages.push(ResolvedPackage(take child.name, take child.version_text, take identity, take lock_source, take directory, take source, List<DependencyEdge>()))
        work.push(Frame(index, 0, take child.dependencies))
    }
    PackageGraph(take packages)
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
