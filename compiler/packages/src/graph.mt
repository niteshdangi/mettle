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
import super.git
import super.inputs.{ PackageError, PackagePhase, error_at, io_result, read_data, relative_to }
import super.lock
import super.manifest.{ Manifest, Dependency, FeatureAction, Program, MacroDecl, decode }
import super.version

pub type DependencyEdge { pub name: String; pub package: usize; pub is_host: bool; span: Range }
pub type ResolvedPackage {
    pub name: String
    pub version: String
    pub identity: String
    pub source: String
    pub directory: PathBuf
    pub entry: PathBuf?
    pub is_library: bool
    pub is_host: bool
    pub dependencies: List<DependencyEdge>
    pub features: List<String>
    pub git_selectors: List<String>
}
pub type PlannedScript { pub package: usize; pub source: PathBuf }
pub type PlannedMacro { pub package: usize; pub name: String; pub source: PathBuf; pub api: u32 }
pub type PackageGraph {
    pub packages: List<ResolvedPackage>
    pub build_scripts: List<PlannedScript>
    pub macros: List<PlannedMacro>
}

pub type ResolveOptions {
    pub features: List<String>
    pub default_features: bool
    pub locked: bool
    pub registries: List<PathBuf>
    pub include_dev: bool
    pub offline: bool
    pub cache_dir: PathBuf?
}

extend ResolveOptions {
    pub init() {
        self.features = List<String>()
        self.default_features = true
        self.locked = false
        self.registries = List<PathBuf>()
        self.include_dev = false
        self.offline = false
        self.cache_dir = none
    }
}

copy type Frame { index: usize; next: usize }
type SelectedEntry { path: PathBuf?; is_library: bool }
type PackageFeatures {
    version: version.Version
    dependencies: List<Dependency>
    selected: List<usize?>
    actions: Map<String, List<FeatureAction>>
    implicit: Map<String, usize>
    enabled: Set<String>
    defaults: bool
    build_script: Program?
    macros: List<MacroDecl>
    target_aliases: Map<String, usize>
    host_aliases: Map<String, usize>
}
type Request { parent: usize; slot: usize; host: bool; forward: String? }
type RegistryRelease { directory: PathBuf; source: String; manifest: Manifest; yanked: bool }
copy type Choice { index: usize; count: usize }
type Search { choices: List<Choice>; depth: usize; fatal: bool }
type Solver {
    graph: PackageGraph
    targets: List<PackageFeatures>
    target_paths: Map<PathBuf, usize>
    host_paths: Map<PathBuf, usize>
    git_targets: Map<String, usize>
    git_hosts: Map<String, usize>
    git_roots: List<usize>
    work: Deque<Request>
    include_dev: bool
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
            return SelectedEntry(present(take canonical), target.library)
        }
    }
    if !root && !manifest.macros.is_empty() { return SelectedEntry(none, false) }
    let name = manifest.name.as_text()
    let reason = if !root { format(f"package '{name}' has no library entry") }
        else if entry.as_bytes() == "main".as_bytes() { format(f"package '{name}' has no source entry") }
        else { format(f"package '{name}' has no entry '{entry}'") }
    throw error(manifest_path.as_path(), manifest.span, take reason)
}

fn satisfies(read dependency: Dependency, read candidate: version.Version): bool {
    if dependency.requirements.is_empty() { return true }
    for requirement in dependency.requirements.as_slice() {
        if version.matches(requirement.as_text(), candidate) == present(true) { return true }
    }
    false
}

fn check_requirement(read dependency: Dependency, read candidate: version.Version, read path: Path): Unit throws PackageError {
    if satisfies(dependency, candidate) { return }
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
    let lock_path = directory.join("lock.mettle")
    let recorded = if publish_lock { try lock.load(lock_path.as_path(), options.locked) } else { none }
    let preferred = lock.preferred(recorded)
    let graph = try solve(directory, entry, options, preferred, recorded)
    if publish_lock { try lock.reconcile(graph, directory, lock_path.as_path(), take recorded, options.locked) }
    graph
}

extend Search {
    mut fn select(count: usize): usize {
        if count == 1 { return 0 }
        let depth = self.depth
        self.depth += 1
        if depth == self.choices.len() { self.choices.push(Choice(0, count)) }
        self.choices[depth].index
    }

    mut fn advance(): bool {
        self.choices.truncate(self.depth)
        while !self.choices.is_empty() {
            let last = self.choices.len() - 1
            if self.choices[last].index + 1 < self.choices[last].count {
                self.choices[last].index += 1
                self.depth = 0
                return true
            }
            let _ = self.choices.pop()
        }
        false
    }
}

fn solve(read directory: Path, read entry: Text, read options: ResolveOptions,
        read preferred: Map<String, List<version.Version>>, read recorded: lock.Lock?): PackageGraph throws PackageError {
    var search = Search(List<Choice>(), 0, false)
    loop {
        match take capture attempt(directory, entry, options, preferred, recorded, mut search) {
            success(graph) => { return take graph },
            failure(issue) => {
                if search.fatal || !search.advance() { throw take issue }
            }
        }
    }
}

fn attempt(read directory: Path, read entry: Text, read options: ResolveOptions,
        read preferred: Map<String, List<version.Version>>, read recorded: lock.Lock?, mut search: Search): PackageGraph throws PackageError {
    let manifest = try load(directory)
    let source = try select_entry(manifest, directory, entry, true)
    var registries = List<PathBuf>()
    for path in options.registries.as_slice() { registries.push(path.to_path_buf()) }
    if let present(path) = manifest.registry { registries.push(directory.join(path.as_text())) }
    let manifest_path = directory.join("package.mettle")
    let span = manifest.span
    var solver = Solver(PackageGraph(List<ResolvedPackage>(), List<PlannedScript>(), List<PlannedMacro>()),
        List<PackageFeatures>(), Map<PathBuf, usize>(), Map<PathBuf, usize>(), Map<String, usize>(), Map<String, usize>(),
        List<usize>(), new<Request>(), options.include_dev)
    let _ = solver.target_paths.insert(directory.to_path_buf(), 0usize)
    let _ = solver.register(take manifest, directory.to_path_buf(), take source, from_text("root"), false)
    try solver.enable(0, feature_queue(options.features), options.default_features, manifest_path.as_path(), span)
    loop {
        let request = match take solver.work.pop_front() {
            present(item) => take item,
            none => { break }
        }
        try solver.resolve_edge(take request, registries, preferred, options, recorded, mut search)
    }
    let ordered = try solver.finish()
    match take capture solver.plan_tools(ordered) {
        success(_) => (),
        failure(issue) => { search.fatal = true; throw take issue }
    }
    take solver.graph
}

fn registry_releases(read root: Path, read registries: List<PathBuf>, read name: Text, read origin: Path, span: Range): List<RegistryRelease> throws PackageError {
    var releases = List<RegistryRelease>()
    for registry in registries.as_slice() {
        let package = registry.join(name)
        var entries = match take capture fs.read_dir(package) {
            success(items) => take items,
            failure(issue) => match issue.kind() {
                io.ErrorKind.NotFound => { continue },
                _ => { throw error(origin, span, issue.message()) }
            }
        }
        let canonical = try io_result(take capture fs.canonicalize(registry), origin, span, PackagePhase.Package)
        let relative = relative_to(root, canonical.as_path())
        let present(location) = relative.to_str() else { throw error(origin, span, from_text("registry path is not valid UTF-8")) }
        var directories = List<PathBuf>()
        loop {
            let present(item) = try io_result(take capture entries.next_entry(), origin, span, PackagePhase.Package) else { break }
            let path = item.path()
            let basename = item.file_name()
            let present(text) = basename.as_os_str().to_str() else { continue }
            if version.parse(text).is_none() { continue }
            if (try io_result(take capture fs.metadata(path), origin, span, PackagePhase.Package)).is_dir() { directories.push(take path) }
        }
        directories.as_mut_slice().sort_unstable_by(fn(read a: PathBuf, read b: PathBuf): Ordering { a.as_os_str().cmp(b.as_os_str()) })
        for path in directories.as_slice() {
            let basename = path.file_name().or_panic()
            let parsed = version.parse(basename.to_str().or_panic()).or_panic()
            var duplicate = false
            for release in releases.as_slice() {
                if version.compare(release.manifest.version, parsed) == 0 { duplicate = true; break }
            }
            if duplicate { continue }
            let directory = try io_result(take capture fs.canonicalize(path), origin, span, PackagePhase.Package)
            let manifest = try load(directory.as_path())
            let actual = manifest.name.as_text()
            if actual != name || version.compare(manifest.version, parsed) != 0 {
                let shown = path.display()
                let release = manifest.version_text.as_text()
                let input = directory.join("package.mettle")
                throw error(input.as_path(), manifest.span, format(f"registry entry '{shown}' contains package '{actual}' {release}"))
            }
            let marker = directory.join("YANKED")
            let yanked = match take capture fs.metadata(marker) {
                success(_) => true,
                failure(issue) => match issue.kind() {
                    io.ErrorKind.NotFound => false,
                    _ => { throw error(origin, span, issue.message()) }
                }
            }
            releases.push(RegistryRelease(take directory, format(f"registry+{location}"), take manifest, yanked))
        }
    }
    releases.as_mut_slice().sort_unstable_by(fn(read a: RegistryRelease, read b: RegistryRelease): Ordering {
        let order = version.compare(a.manifest.version, b.manifest.version)
        if order > 0 { Ordering.Less } else if order < 0 { Ordering.Greater } else { Ordering.Equal }
    })
    releases
}

fn feature_queue(read features: List<String>): Deque<String> {
    var pending = new<String>()
    for feature in features.as_slice() { pending.push_back(from_text(feature.as_text())) }
    pending
}

fn enqueue_feature_edge(mut work: Deque<Request>, index: usize, slot: usize, host: bool, mirror: bool, forward: bool, read feature: Text): Unit {
    work.push_back(Request(index, slot, host, none))
    if forward { work.push_back(Request(index, slot, host, present(from_text(feature)))) }
    if mirror {
        work.push_back(Request(index, slot, true, none))
        if forward { work.push_back(Request(index, slot, true, present(from_text(feature)))) }
    }
}

extend Solver {
    mut fn register(take manifest: Manifest, take directory: PathBuf, take entry: SelectedEntry, take source: String, host: bool): usize {
        let index = self.graph.packages.len()
        let name = manifest.name.as_text()
        let version_text = manifest.version_text.as_text()
        let source_text = source.as_text()
        let context = if host { "host" } else { "target" }
        let id = format(f"{name}@{version_text}|{source_text}|{context}")
        var dependencies = take manifest.dependencies
        let normal = dependencies.len()
        var i = 0usize
        while i < normal {
            if !dependencies[i].optional { self.work.push_back(Request(index, i, host, none)) }
            i += 1
        }
        var build = take manifest.build_dependencies
        dependencies.append(mut build)
        while i < dependencies.len() {
            self.work.push_back(Request(index, i, true, none))
            i += 1
        }
        if index == 0 && self.include_dev {
            var development = take manifest.dev_dependencies
            dependencies.append(mut development)
            while i < dependencies.len() {
                self.work.push_back(Request(index, i, false, none))
                i += 1
            }
        }
        if !host && !manifest.macros.is_empty() {
            i = 0
            while i < normal {
                if !dependencies[i].optional { self.work.push_back(Request(index, i, true, none)) }
                i += 1
            }
        }
        var selected = List<usize?>()
        selected.resize(dependencies.len() * 2, none)
        self.graph.packages.push(ResolvedPackage(take manifest.name, take manifest.version_text, take id, take source,
            take directory, take entry.path, entry.is_library, host, List<DependencyEdge>(), List<String>(), List<String>()))
        self.targets.push(PackageFeatures(take manifest.version, take dependencies, take selected, take manifest.features,
            take manifest.implicit_features, Set<String>(), false, take manifest.build_script, take manifest.macros,
            Map<String, usize>(), Map<String, usize>()))
        index
    }

    mut fn enable(index: usize, take requested: Deque<String>, defaults: bool, read origin: Path, span: Range): Unit throws PackageError {
        var pending = take requested
        let host = self.graph.packages[index].is_host
        let mirror = !host && !self.targets[index].macros.is_empty()
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
                        FeatureAction.Activate(slot) => enqueue_feature_edge(mut self.work, index, slot, host, mirror, false, ""),
                        FeatureAction.Forward(slot, feature) => enqueue_feature_edge(mut self.work, index, slot, host, mirror, true, feature.as_text())
                    }
                }
            } else if let present(slot) = self.targets[index].implicit.get(name) {
                enqueue_feature_edge(mut self.work, index, *slot, host, mirror, false, "")
            } else {
                let package_name = self.graph.packages[index].name.as_text()
                throw error(origin, span, format(f"package '{package_name}' has no feature '{name}'"))
            }
            self.graph.packages[index].features.push(take feature)
        }
    }

    mut fn resolve_edge(take request: Request, read registries: List<PathBuf>, read preferred: Map<String, List<version.Version>>,
            read options: ResolveOptions, read recorded: lock.Lock?, mut search: Search): Unit throws PackageError {
        let owner = request.parent
        let slot = request.slot
        let host = request.host
        let selection = if host { slot + self.targets[owner].dependencies.len() } else { slot }
        let span = self.targets[owner].dependencies[slot].span
        let owner_path = self.graph.packages[owner].directory.join("package.mettle")
        let origin = owner_path.as_path()
        let index = match self.targets[owner].selected[selection] {
            present(chosen) => chosen,
            none => {
                let dependency = read self.targets[owner].dependencies[slot]
                let name = from_text(dependency.name.as_text())
                let defaults = dependency.default_features
                let pending = feature_queue(dependency.features)
                let git_selector = if let present(source) = dependency.git { present(from_text(source.selector.as_text())) } else { none }
                let existing_edge = if host { self.targets[owner].host_aliases.get(name.as_text()) }
                    else { self.targets[owner].target_aliases.get(name.as_text()) }
                let selected = match existing_edge {
                    present(index) => present(self.graph.packages[owner].dependencies[*index].package),
                    none => none
                }
                let target: usize = if let present(location) = dependency.path {
                    let path = self.graph.packages[owner].directory.join(location.as_text())
                    match take capture self.activate_path(owner, slot, host, path.as_path(), origin, span) {
                        success(index) => index,
                        failure(issue) => { search.fatal = true; throw take issue }
                    }
                } else if dependency.git.is_present() {
                    match take capture self.activate_git(owner, slot, host, origin, span, options, recorded) {
                        success(index) => index,
                        failure(issue) => { search.fatal = true; throw take issue }
                    }
                } else {
                    try self.activate_registry(owner, slot, host, origin, span, registries, preferred, selected, mut search)
                }
                if let present(existing) = selected {
                    if existing != target {
                        let dependency_name = name.as_text()
                        throw error(origin, span, format(f"conflicting requirements for dependency alias '{dependency_name}'"))
                    }
                } else {
                    let edge = self.graph.packages[owner].dependencies.len()
                    if host { let _ = self.targets[owner].host_aliases.insert(from_text(name.as_text()), edge) }
                    else { let _ = self.targets[owner].target_aliases.insert(from_text(name.as_text()), edge) }
                    self.graph.packages[owner].dependencies.push(DependencyEdge(take name, target, host, span))
                }
                match take git_selector {
                    present(selector) => {
                        var seen = false
                        for existing in self.graph.packages[target].git_selectors.as_slice() {
                            if existing.as_text() == selector.as_text() { seen = true; break }
                        }
                        if !seen { self.graph.packages[target].git_selectors.push(take selector) }
                    },
                    none => {}
                }
                self.targets[owner].selected[selection] = present(target)
                try self.enable(target, take pending, defaults, origin, span)
                target
            }
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

    mut fn activate_path(owner: usize, slot: usize, host: bool, read path: Path, read origin: Path, span: Range): usize throws PackageError {
        let dependency = read self.targets[owner].dependencies[slot]
        let expected = dependency.name.as_text()
        let directory = try io_result(take capture fs.canonicalize(path), origin, span, PackagePhase.Package)
        let existing = if host { self.host_paths.get(directory) } else { self.target_paths.get(directory) }
        if let present(chosen) = existing {
            let actual = self.graph.packages[*chosen].name.as_text()
            if actual != expected { throw error(origin, span, format(f"path dependency '{expected}' is the package '{actual}'")) }
            try check_requirement(dependency, self.targets[*chosen].version, origin)
            return *chosen
        }
        let child = try load(directory.as_path())
        let actual = child.name.as_text()
        if actual != expected { throw error(origin, span, format(f"path dependency '{expected}' is the package '{actual}'")) }
        try check_requirement(dependency, child.version, origin)
        let source = try select_entry(child, directory.as_path(), "main", false)
        let relative = relative_to(self.graph.packages[0].directory.as_path(), directory.as_path())
        let present(relative_text) = relative.to_str() else {
            throw error(origin, span, from_text("package path is not valid UTF-8"))
        }
        let source_name = try self.path_source(directory.as_path(), relative_text, origin, span)
        let next = self.graph.packages.len()
        if host { let _ = self.host_paths.insert(directory.to_path_buf(), next) }
        else { let _ = self.target_paths.insert(directory.to_path_buf(), next) }
        self.register(take child, take directory, take source, take source_name, host)
    }

    fn path_source(read directory: Path, read relative_text: Text, read origin: Path, span: Range): String throws PackageError {
        var best: usize? = none
        var length = 0usize
        for index in self.git_roots.as_slice() {
            let root = self.graph.packages[index].directory.as_path()
            if root.as_bytes().len() > length && directory.starts_with(root) {
                best = present(index)
                length = root.as_bytes().len()
            }
        }
        if let present(index) = best {
            let root = read self.graph.packages[index]
            let source = root.source.as_text()
            let relative = relative_to(root.directory.as_path(), directory)
            let present(path) = relative.to_str() else { throw error(origin, span, from_text("package path is not valid UTF-8")) }
            return format(f"path+{source}/{path}")
        }
        format(f"path+{relative_text}")
    }

    mut fn activate_git(owner: usize, slot: usize, host: bool, read origin: Path, span: Range,
            read options: ResolveOptions, read recorded: lock.Lock?): usize throws PackageError {
        let dependency = read self.targets[owner].dependencies[slot]
        if let present(spec) = dependency.git {
            let name = dependency.name.as_text()
            let url = spec.url.as_text()
            let selector = spec.selector.as_text()
            let prefix = format(f"git+{url}#")
            let pinned_commit = if options.offline { lock.git_commit(recorded, name, prefix.as_text(), selector) } else { from_text("") }
            let checkout = try git.checkout(options.cache_dir, options.offline, url, selector, pinned_commit.as_text(), origin, span)
            let commit = checkout.commit.as_text()
            let source = format(f"git+{url}#{commit}")
            let existing = if host { self.git_hosts.get(source.as_text()) } else { self.git_targets.get(source.as_text()) }
            if let present(index) = existing {
                let actual = self.graph.packages[*index].name.as_text()
                if actual != name { throw error(origin, span, format(f"git dependency '{name}' at '{url}' is the package '{actual}'")) }
                if !satisfies(dependency, self.targets[*index].version) {
                    throw error(origin, span, format(f"git dependency '{name}' does not satisfy its version requirement"))
                }
                return *index
            }
            let manifest = try load(checkout.directory.as_path())
            let actual = manifest.name.as_text()
            if actual != name { throw error(origin, span, format(f"git dependency '{name}' at '{url}' is the package '{actual}'")) }
            if !satisfies(dependency, manifest.version) {
                throw error(origin, span, format(f"git dependency '{name}' does not satisfy its version requirement"))
            }
            let entry = try select_entry(manifest, checkout.directory.as_path(), "main", false)
            self.git_roots.push(self.graph.packages.len())
            let index = self.graph.packages.len()
            if host { let _ = self.git_hosts.insert(from_text(source.as_text()), index) }
            else { let _ = self.git_targets.insert(from_text(source.as_text()), index) }
            return self.register(take manifest, take checkout.directory, take entry, take source, host)
        }
        panic("expected a Git dependency")
    }

    mut fn activate_registry(owner: usize, slot: usize, host: bool, read origin: Path, span: Range, read registries: List<PathBuf>,
            read preferred: Map<String, List<version.Version>>, selected: usize?, mut search: Search): usize throws PackageError {
        let dependency = read self.targets[owner].dependencies[slot]
        let name = dependency.name.as_text()
        if registries.is_empty() { throw error(origin, span, format(f"package '{name}' was not found: no registry is configured")) }
        var releases = match take capture registry_releases(self.graph.packages[0].directory.as_path(), registries, name, origin, span) {
            success(items) => take items,
            failure(issue) => { search.fatal = true; throw take issue }
        }
        var preferred_releases = List<usize>()
        var fresh = List<usize>()
        var conflict = false
        var index = 0usize
        while index < releases.len() {
            let release = read releases[index]
            let candidate = read release.manifest.version
            let choice = index
            index += 1
            if !satisfies(dependency, candidate) { continue }
            var pin = false
            if let present(versions) = preferred.get(name) {
                for locked in versions.as_slice() {
                    if version.compare(candidate, locked) == 0 { pin = true; break }
                }
            }
            if release.yanked && !pin { continue }
            if let present(target) = selected {
                let existing = read self.graph.packages[target]
                if existing.source.as_text() == release.source.as_text() &&
                    existing.version.as_text() == release.manifest.version_text.as_text() { return target }
                continue
            }
            var compatible = false
            var target = 1usize
            while target < self.graph.packages.len() {
                let selected = read self.graph.packages[target]
                if selected.is_host == host && selected.source.as_text() == release.source.as_text() && selected.name.as_text() == name {
                    let chosen = read self.targets[target].version
                    if version.compare(chosen, candidate) == 0 { return target }
                    if chosen.compatible(candidate) { compatible = true; break }
                }
                target += 1
            }
            if compatible { conflict = true; continue }
            if pin { preferred_releases.push(choice) } else { fresh.push(choice) }
        }
        let count = preferred_releases.len() + fresh.len()
        if count == 0 {
            let message = if selected.is_present() { format(f"conflicting requirements for dependency alias '{name}'") }
                else if releases.is_empty() { format(f"package '{name}' was not found: not present in the local registries") }
                else if conflict { format(f"no version of '{name}' satisfies all requirements") }
                else { format(f"no available version of '{name}' satisfies its version requirement") }
            throw error(origin, span, take message)
        }
        let at = search.select(count)
        let choice = if at < preferred_releases.len() { preferred_releases[preferred_releases.len() - at - 1] }
            else { fresh[at - preferred_releases.len()] }
        let release = releases.remove(choice)
        let entry = try select_entry(release.manifest, release.directory.as_path(), "main", false)
        self.register(take release.manifest, take release.directory, take entry, take release.source, host)
    }

    mut fn finish(): List<usize> throws PackageError {
        var i = 0usize
        while i < self.graph.packages.len() {
            self.graph.packages[i].dependencies.as_mut_slice().sort_unstable_by(fn(read a: DependencyEdge, read b: DependencyEdge): Ordering {
                let order = a.name.as_text().cmp(b.name.as_text())
                match order {
                    Ordering.Equal => if a.is_host == b.is_host { Ordering.Equal }
                        else if a.is_host { Ordering.Greater } else { Ordering.Less },
                    _ => order
                }
            })
            self.graph.packages[i].features.as_mut_slice().sort_unstable_by(fn(read a: String, read b: String): Ordering {
                a.as_text().cmp(b.as_text())
            })
            self.graph.packages[i].git_selectors.as_mut_slice().sort_unstable_by(fn(read a: String, read b: String): Ordering {
                a.as_text().cmp(b.as_text())
            })
            i += 1
        }
        try dependency_order(self.graph)
    }

    mut fn plan_tools(read ordered: List<usize>): Unit throws PackageError {
        var owners = Map<String, usize>()
        for index in ordered.as_slice() {
            let package = read self.graph.packages[index]
            let metadata = read self.targets[index]
            let directory = package.directory.as_path()
            if let present(script) = metadata.build_script {
                let source = try tool_source(directory, script, "build script")
                self.graph.build_scripts.push(PlannedScript(index, take source))
            }
            if package.is_host { continue }
            for declaration in metadata.macros.as_slice() {
                let name = declaration.name.as_text()
                let source = try tool_source(directory, declaration.program, "macro source")
                if let present(other) = owners.get(name) {
                    let previous = self.graph.packages[*other].name.as_text()
                    let current = package.name.as_text()
                    let manifest = directory.join("package.mettle")
                    throw error(manifest.as_path(), declaration.program.span, format(f"macro '{name}' is declared by both '{previous}' and '{current}'"))
                }
                let owner = index
                let _ = owners.insert(from_text(name), owner)
                self.graph.macros.push(PlannedMacro(index, from_text(name), take source, 1u32))
            }
        }
    }
}

fn tool_source(read directory: Path, read program: Program, read kind: Text): PathBuf throws PackageError {
    let name = program.source.as_text()
    let location = directory.join(name)
    let manifest = directory.join("package.mettle")
    let path = manifest.as_path()
    match take capture fs.metadata(location) {
        success(info) => {
            if info.is_file() { return try io_result(take capture fs.canonicalize(location), path, program.span, PackagePhase.Package) }
        },
        failure(issue) => match issue.kind() {
            io.ErrorKind.NotFound => (),
            _ => { throw error(path, program.span, issue.message()) }
        }
    }
    throw error(path, program.span, format(f"{kind} '{name}' does not exist"))
}

fn dependency_order(read graph: PackageGraph): List<usize> throws PackageError {
    var ordered = List<usize>()
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
            ordered.push(node)
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
    ordered
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
    if let present(entry) = units.entry {
        assert(entry.file_name().or_panic().same(std.ffi.os_str_from_text("main.mt")), "wrong dependency library source")
    } else { assert(false, "missing dependency library source") }
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
fn registry_backtracks_to_unify_compatible_releases(): Unit throws PackageError {
    let graph = try resolve(std.path.path_from_text("tests/packages/resolution/app"), "main")
    let root = read graph.packages[0]
    let left = read graph.packages[root.dependencies[0].package]
    let right = read graph.packages[root.dependencies[1].package]
    let chosen = left.dependencies[0].package
    assert(graph.packages.len() == 4 && chosen == right.dependencies[0].package, "compatible requirements did not unify")
    assert(graph.packages[chosen].identity.as_text() == "util@1.0.0|registry+../../registry|target",
        "the resolver did not backtrack to the shared release")
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
