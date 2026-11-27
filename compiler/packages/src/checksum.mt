import alloc.hash_map.Set
import alloc.string.String
import alloc.vec.List
import core.cmp.Ordering
import std.fs
import std.ffi.os_str_from_text
import std.macros.format
import std.path.{ Path, PathBuf }
import super.sha256.Sha256
import super.inputs.{ PackageError, PackagePhase, error_at, io_result }
import super.data.Range

type SourceLink { relative: PathBuf; target: PathBuf }

fn under(read root: Path, read path: Path): PathBuf throws PackageError {
    match capture path.strip_prefix(root) {
        success(relative) => if relative.is_empty() { std.path.path_buf_from_text(".") } else { relative.to_path_buf() },
        failure(_) => {
            let shown = path.display()
            throw error_at(path, Range(0, 0), format(f"source link outside its directory: {shown}"), PackagePhase.Package)
        }
    }
}

pub fn hash_tree(read root: Path): String throws PackageError {
    try hash(root, false)
}

pub fn hash_legacy_tree(read root: Path): String throws PackageError {
    try hash(root, true)
}

fn hash(read root: Path, legacy: bool): String throws PackageError {
    let start = Range(0, 0)
    var files = List<PathBuf>()
    var links = List<SourceLink>()
    var visited = Set<PathBuf>()
    let _ = visited.insert(root.to_path_buf())
    var directories = List<fs.ReadDir>()
    directories.push(try io_result(take capture fs.read_dir(root), root, start, PackagePhase.Package))
    while !directories.is_empty() {
        let depth = directories.len() - 1
        let next = try io_result(take capture directories[depth].next_entry(), root, start, PackagePhase.Package)
        let present(entry) = next else { let _ = directories.pop(); continue }
        let path = entry.path()
        let location = path.as_path()
        let name = entry.file_name()
        let basename = name.as_os_str()
        let kind = try io_result(take capture entry.file_type(), location, start, PackagePhase.Package)
        let linked = kind.is_symlink()
        let resolved = if linked && !legacy {
            let canonical = try io_result(take capture fs.canonicalize(location), location, start, PackagePhase.Package)
            if !canonical.as_path().starts_with(root) {
                let shown = location.display()
                throw error_at(location, start, format(f"source link outside its directory: {shown}"), PackagePhase.Package)
            }
            let target = try under(root, canonical.as_path())
            links.push(SourceLink(try under(root, location), take target))
            present(take canonical)
        } else { none }
        let properties = if linked {
            (try io_result(take capture fs.metadata(location), location, start, PackagePhase.Package)).file_type()
        } else { kind }
        if properties.is_dir() {
            if legacy {
                if linked || basename.as_bytes()[0] == b'.' || basename.same(os_str_from_text("target")) || basename.same(os_str_from_text("build")) { continue }
            } else if basename.same(os_str_from_text(".git")) || (depth == 0 && basename.same(os_str_from_text("target"))) { continue }
            let canonical = match take resolved {
                present(value) => take value,
                none => try io_result(take capture fs.canonicalize(location), location, start, PackagePhase.Package)
            }
            if visited.insert(take canonical) {
                directories.push(try io_result(take capture fs.read_dir(location), location, start, PackagePhase.Package))
            }
        } else if properties.is_file() && !basename.same(os_str_from_text("lock.mettle")) {
            if legacy {
                let present(ext) = location.extension() else { continue }
                if !ext.same(os_str_from_text("mt")) && !ext.same(os_str_from_text("mettle")) { continue }
            } else if depth == 0 && basename.same(os_str_from_text("YANKED")) { continue }
            files.push(try under(root, location))
        }
    }
    files.as_mut_slice().sort_unstable_by(fn(read a: PathBuf, read b: PathBuf): Ordering { a.as_os_str().cmp(b.as_os_str()) })
    links.as_mut_slice().sort_unstable_by(fn(read a: SourceLink, read b: SourceLink): Ordering {
        a.relative.as_os_str().cmp(b.relative.as_os_str())
    })
    var hash = Sha256()
    for relative in files.as_slice() {
        let input = root.join(relative)
        let bytes = try io_result(take capture fs.read_bytes(input), input.as_path(), start, PackagePhase.Package)
        let size = bytes.len()
        let length = format(f"{size}")
        hash.update(relative.as_bytes())
        hash.update([0u8])
        hash.update(length.as_bytes())
        hash.update([0u8])
        hash.update(bytes.as_slice())
    }
    for link in links.as_slice() {
        hash.update("link:".as_bytes())
        hash.update(link.relative.as_bytes())
        hash.update([0u8])
        hash.update(link.target.as_bytes())
    }
    let digest = hash.finish()
    let text = digest.as_text()
    if legacy { format(f"sha256:{text}") } else { format(f"sha256-tree-2:{text}") }
}
