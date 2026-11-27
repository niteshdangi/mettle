import alloc.hash_map.{ Map, Set }
import alloc.string
import alloc.string.{ String, from_text }
import alloc.vec.List
import core.text.Text
import std.macros.format
import std.path.path_from_text
import super.data.{ Data, DataError, Kind, Range }
import super.version

pub type Target { pub name: String; pub source: String; pub library: bool; pub span: Range }
pub type Dependency {
    pub name: String
    pub path: String
    pub requirements: List<String>
    pub span: Range
    pub features: List<String>
    pub default_features: bool
    pub optional: bool
}
pub enum FeatureAction { Local(String), Activate(usize), Forward(usize, String) }
pub type Manifest {
    pub name: String
    pub version_text: String
    pub version: version.Version
    pub span: Range
    pub targets: List<Target>
    pub dependencies: List<Dependency>
    pub features: Map<String, List<FeatureAction>>
    pub implicit_features: Map<String, usize>
}

fn valid_name(read text: Text): bool {
    if text.is_empty() { return false }
    let first = text.as_bytes()[0]
    if first < b'a' || first > b'z' { return false }
    for byte in text.as_bytes() {
        if !(byte >= b'a' && byte <= b'z') && !(byte >= b'0' && byte <= b'9') && byte != b'_' && byte != b'-' { return false }
    }
    true
}

fn module_name(read name: Text): String {
    var out = string.new()
    for c in name.chars() { out.push(if c == '-' { '_' } else { c }) }
    out
}

extend Data {
    fn required(object: usize, read name: Text): usize throws DataError {
        let present(index) = self.field(object, name) else {
            throw DataError(self.nodes[object].span, format(f"package.mettle needs '{name}'"))
        }
        index
    }

    fn string(index: usize, read description: Text): String throws DataError {
        let node = read self.nodes[index]
        if !node.kind.is(Kind.String) { throw DataError(node.span, format(f"{description} must be a string")) }
        from_text(node.text.as_text())
    }

    fn target_name(read name: Text, path: usize?, fields: usize, span: Range): Target throws DataError {
        if !valid_name(name) { throw DataError(span, format(f"invalid entry name '{name}'")) }
        let kind = if let present(index) = self.field(fields, "kind") { try self.string(index, "'kind'") }
            else { from_text("executable") }
        let library = kind.as_text() == "library"
        if !library && kind.as_text() != "executable" { throw DataError(span, from_text("entry kind must be 'library' or 'executable'")) }
        let source = if let present(index) = path { try self.string(index, "an entry path") } else { from_text("src/main.mt") }
        if source.is_empty() || source.as_text().find_byte(0u8).is_present() {
            throw DataError(span, from_text("an entry must be a nonempty path without NUL bytes"))
        }
        if let present(index) = self.field(fields, "emit") {
            let array = self.nodes[index].kind.is(Kind.Array)
            var i = if array { index + 1 } else { index }
            let end = if array { self.nodes[index].next } else { index + 1 }
            if i == end { throw DataError(self.nodes[index].span, from_text("'emit' must not be empty")) }
            var emits = Set<String>()
            while i < end {
                let emit = try self.string(i, "an emit format")
                let text = emit.as_text()
                if text != "object" && text != "llvm" && text != "ir" &&
                    !(library && (text == "static" || text == "shared" || text == "package")) &&
                    !(!library && text == "executable") {
                    let target_kind = kind.as_text()
                    throw DataError(self.nodes[i].span, format(f"emit format '{text}' is incompatible with '{target_kind}'"))
                }
                if !emits.insert(from_text(text)) { throw DataError(self.nodes[i].span, format(f"duplicate emit format '{text}'")) }
                i += 1
            }
        }
        Target(from_text(name), take source, library, span)
    }

    fn targets(default_entry: bool): List<Target> throws DataError {
        var result = List<Target>()
        let map = self.field(0, "entry").or(0usize)
        if map != 0 && self.nodes[map].kind.is(Kind.Object) {
            if self.field(0, "kind").is_present() || self.field(0, "emit").is_present() {
                throw DataError(self.nodes[map].span, from_text("an entry map declares 'kind' and 'emit' per entry"))
            }
            if self.field(map, "main").is_none() { throw DataError(self.nodes[map].span, from_text("an entry map must define 'main'")) }
            var i = map + 1
            var library = false
            while i < self.nodes[map].next {
                let node = read self.nodes[i]
                let name = node.key.as_text()
                if node.kind.is(Kind.Object) {
                    var field = i + 1
                    while field < node.next {
                        let child = read self.nodes[field]
                        let key = child.key.as_text()
                        if key != "kind" && key != "path" && key != "emit" { throw DataError(child.key_span, format(f"unknown key '{key}' in an entry")) }
                        field = child.next
                    }
                    let path = self.field(i, "path")
                    if name != "main" && path.is_none() { throw DataError(node.span, from_text("a named entry requires 'path'")) }
                    let target = try self.target_name(name, path, i, node.span)
                    if library && target.library { throw DataError(node.span, from_text("a package has at most one library entry")) }
                    library = library || target.library
                    result.push(take target)
                } else {
                    result.push(try self.target_name(name, present(i), 0, node.span))
                }
                i = node.next
            }
        } else if map != 0 || default_entry || self.field(0, "kind").is_present() || self.field(0, "emit").is_present() {
            let path = if map == 0 { none } else { present(map) }
            result.push(try self.target_name("main", path, 0, self.nodes[map].span))
        }
        result
    }

    fn requirements(index: usize, read candidate: version.Version): List<String> throws DataError {
        var result = List<String>()
        let array = self.nodes[index].kind.is(Kind.Array)
        var i = if array { index + 1 } else { index }
        let end = if array { self.nodes[index].next } else { index + 1 }
        if i == end { throw DataError(self.nodes[index].span, from_text("a version requirement list must not be empty")) }
        while i < end {
            let item = try self.string(i, "a version requirement")
            let text = item.as_text()
            if version.matches(text, candidate).is_none() { throw DataError(self.nodes[i].span, format(f"invalid version requirement '{text}'")) }
            result.push(take item)
            i = self.nodes[i].next
        }
        result
    }

    fn dependencies(read owner: Text, read candidate: version.Version): List<Dependency> throws DataError {
        var result = List<Dependency>()
        let present(table) = self.field(0, "dependencies") else { return result }
        if !self.nodes[table].kind.is(Kind.Object) {
            throw DataError(self.nodes[table].span, from_text("[dependencies] must be a table"))
        }
        let normalized_owner = module_name(owner)
        var aliases = Set<String>()
        var i = table + 1
        while i < self.nodes[table].next {
            let node = read self.nodes[i]
            let name = node.key.as_text()
            let mount = module_name(name)
            if !valid_name(name) { throw DataError(node.key_span, format(f"invalid package name '{name}' (expected [a-z][a-z0-9_-]*)")) }
            if mount.as_text() == normalized_owner.as_text() {
                throw DataError(node.key_span, format(f"dependency '{name}' has the name of its own package; a package name and its dependency names share one namespace"))
            }
            if !aliases.insert(take mount) { throw DataError(node.key_span, format(f"dependency '{name}' collides with another module root")) }
            var requirements = List<String>()
            var features = List<String>()
            var optional = false
            var default_features = true
            let path = if node.kind.is(Kind.String) && (node.text.as_text().starts_with("./") ||
                node.text.as_text().starts_with("../") || path_from_text(node.text.as_text()).is_absolute()) {
                from_text(node.text.as_text())
            } else if node.kind.is(Kind.Object) {
                var f = i + 1
                while f < node.next {
                    let field = read self.nodes[f]
                    let key = field.key.as_text()
                    if key == "version" { requirements = try self.requirements(f, candidate) }
                    else if key == "features" {
                        if !field.kind.is(Kind.Array) { throw DataError(field.span, from_text("'features' must be an array of strings")) }
                        var member = f + 1
                        while member < field.next {
                            features.push(try self.string(member, "a feature name"))
                            member = self.nodes[member].next
                        }
                    } else if key == "optional" || key == "default_features" {
                        if !field.kind.is(Kind.Boolean) { throw DataError(field.span, format(f"'{key}' must be a boolean")) }
                        let value = field.text.as_text() == "true"
                        if key == "optional" { optional = value } else { default_features = value }
                    } else if key == "git" || key == "rev" || key == "tag" || key == "branch" {
                        throw DataError(field.key_span, format(f"native package resolution does not yet support dependency '{key}'"))
                    } else if key != "path" { throw DataError(field.key_span, format(f"unknown key '{key}' in a dependency")) }
                    f = field.next
                }
                let present(p) = self.field(i, "path") else {
                    if requirements.is_empty() { throw DataError(node.key_span, format(f"dependency '{name}' needs a 'path' or a 'version' requirement")) }
                    throw DataError(node.key_span, from_text("native package resolution does not yet support registry dependencies"))
                }
                try self.string(p, "'path'")
            } else {
                let _ = try self.requirements(i, candidate)
                throw DataError(node.key_span, from_text("native package resolution does not yet support registry dependencies"))
            }
            if path.as_text().find_byte(0u8).is_present() {
                throw DataError(node.span, from_text("dependency path contains a NUL byte"))
            }
            result.push(Dependency(from_text(name), take path, take requirements, node.key_span, take features, default_features, optional))
            i = node.next
        }
        result
    }
}

fn feature_actions(read data: Data, read dependencies: List<Dependency>): (Map<String, List<FeatureAction>>, Map<String, usize>) throws DataError {
    let table = data.field(0, "features").or(0usize)
    var declared = Set<String>()
    var suppressed = Set<String>()
    if table != 0 {
        if !data.nodes[table].kind.is(Kind.Object) {
            throw DataError(data.nodes[table].span, from_text("[features] must be a table"))
        }
        var feature = table + 1
        while feature < data.nodes[table].next {
            let node = read data.nodes[feature]
            let name = node.key.as_text()
            if !node.kind.is(Kind.Array) {
                throw DataError(node.span, format(f"feature '{name}' must list its enabled items"))
            }
            let _ = declared.insert(from_text(name))
            var member = feature + 1
            while member < node.next {
                let item = read data.nodes[member]
                if !item.kind.is(Kind.String) { throw DataError(item.span, from_text("a feature item must be a string")) }
                if let present(name) = item.text.as_text().strip_prefix("dep:") {
                    let _ = suppressed.insert(from_text(name))
                }
                member = item.next
            }
            feature = node.next
        }
    }
    var indices = Map<String, usize>()
    var implicit = Map<String, usize>()
    var i = 0usize
    while i < dependencies.len() {
        let index = i
        i += 1
        let dep = read dependencies[index]
        let name = dep.name.as_text()
        if dep.optional && !suppressed.contains(name) {
            let slot = index
            let _ = implicit.insert(from_text(name), slot)
        }
        let _ = indices.insert(from_text(name), index)
    }
    var actions = Map<String, List<FeatureAction>>()
    if table == 0 { return (take actions, take implicit) }
    var feature = table + 1
    while feature < data.nodes[table].next {
        let node = read data.nodes[feature]
        let name = node.key.as_text()
        var enables = List<FeatureAction>()
        var member = feature + 1
        while member < node.next {
            let item = read data.nodes[member]
            let text = item.text.as_text()
            if let present(target) = text.strip_prefix("dep:") {
                let present(dep) = indices.get(target) else {
                    throw DataError(node.key_span, format(f"feature '{name}': '{text}' must name an optional dependency"))
                }
                if !dependencies[*dep].optional {
                    throw DataError(node.key_span, format(f"feature '{name}': '{text}' must name an optional dependency"))
                }
                enables.push(FeatureAction.Activate(*dep))
            } else if let present((target, requested)) = text.split_once("/") {
                let present(dep) = indices.get(target) else {
                    throw DataError(node.key_span, format(f"feature '{name}': '{text}' names no dependency"))
                }
                enables.push(FeatureAction.Forward(*dep, from_text(requested)))
            } else {
                if text == name {
                    throw DataError(node.key_span, format(f"feature '{name}': a feature cannot enable itself"))
                }
                if !declared.contains(text) && !implicit.contains_key(text) {
                    throw DataError(node.key_span, format(f"feature '{name}': '{text}' is not a feature of this package"))
                }
                enables.push(FeatureAction.Local(from_text(text)))
            }
            member = item.next
        }
        let _ = actions.insert(from_text(name), take enables)
        feature = node.next
    }
    (take actions, take implicit)
}

pub fn decode(read data: Data, default_entry: bool): Manifest throws DataError {
    let root = read data.nodes[0]
    if !root.kind.is(Kind.Object) { throw DataError(root.span, from_text("package.mettle must contain an object")) }
    var i = 1usize
    while i < root.next {
        let node = read data.nodes[i]
        let key = node.key.as_text()
        if key == "mettle-version" || key == "build-dependencies" || key == "build" || key == "macros" {
            throw DataError(node.key_span, format(f"native package resolution does not yet support '{key}'"))
        }
        if key != "name" && key != "version" && key != "description" && key != "kind" && key != "entry" &&
            key != "emit" && key != "dependencies" && key != "dev-dependencies" && key != "registry" && key != "features" {
            throw DataError(node.key_span, format(f"unknown key '{key}' in package.mettle"))
        }
        i = node.next
    }
    let name_index = try data.required(0, "name")
    let name = try data.string(name_index, "'name'")
    let package_name = name.as_text()
    let span = data.nodes[name_index].span
    if !valid_name(package_name) { throw DataError(span, format(f"invalid package name '{package_name}' (expected [a-z][a-z0-9_-]*)")) }
    if package_name == "core" || package_name == "alloc" || package_name == "std" || package_name == "package" || package_name == "self" || package_name == "super" {
        throw DataError(span, format(f"package name '{package_name}' collides with a reserved module root"))
    }
    let index = try data.required(0, "version")
    let version_text = try data.string(index, "'version'")
    let text = version_text.as_text()
    let present(parsed) = version.parse(text) else { throw DataError(data.nodes[index].span, format(f"invalid SemVer version '{text}'")) }
    let targets = try data.targets(default_entry)
    let dependencies = try data.dependencies(package_name, parsed)
    let (features, implicit) = try feature_actions(data, dependencies)
    Manifest(take name, take version_text, take parsed, span, take targets, take dependencies, take features, take implicit)
}
