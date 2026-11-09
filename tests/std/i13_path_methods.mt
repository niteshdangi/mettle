// Path and PathBuf accessors, iteration, builders and mutators.
import core.iter.Iterator
import std.ffi.os_str_from_text
import std.io.{Error, ErrorKind}
import std.path.{Path, PathBuf, path_from_text, path_buf_from_text}

fn text_is(p: read Path, want: read Text): bool {
    match p.to_str() { present(t) => t == want, none => false }
}
fn file_name_is(p: read Path, want: read Text): bool {
    match p.file_name() { present(n) => match n.to_str() { present(t) => t == want, none => false }, none => false }
}
fn stem_is(p: read Path, want: read Text): bool {
    match p.file_stem() { present(n) => match n.to_str() { present(t) => t == want, none => false }, none => false }
}
fn prefix_is(p: read Path, want: read Text): bool {
    match p.file_prefix() { present(n) => match n.to_str() { present(t) => t == want, none => false }, none => false }
}
fn extension_is(p: read Path, want: read Text): bool {
    match p.extension() { present(x) => match x.to_str() { present(t) => t == want, none => false }, none => false }
}
fn parent_is(p: read Path, want: read Text): bool {
    match p.parent() { present(q) => q.same(path_from_text(want)), none => false }
}
fn buf_text_is(p: read PathBuf, want: read Text): bool {
    match p.to_str() { present(t) => t == want, none => false }
}

fn run(): i32 throws Error {
    // Accessors on an absolute path.
    let p = path_from_text("/usr/lib/libz.so.1")
    if !p.is_absolute() || p.is_relative() || !p.has_root() { return 1 }
    if p.is_empty() || p.as_bytes().len() != 18usize { return 2 }
    if !text_is(p, "/usr/lib/libz.so.1") { return 3 }
    if !file_name_is(p, "libz.so.1") { return 4 }
    if !stem_is(p, "libz.so") { return 5 }
    if !prefix_is(p, "libz") { return 6 }
    if !extension_is(p, "1") { return 7 }
    if !parent_is(p, "/usr/lib") { return 8 }
    if !p.to_path_buf().as_path().same(p) { return 9 }
    if p.display().len() != 18usize { return 10 }

    // Ancestors walk the lexical parents down to the root.
    var ancestors = p.ancestors()
    match ancestors.next() {
        present(a) => { if !a.same(p) { return 11 } },
        none => { return 11 }
    }
    match ancestors.next() {
        present(a) => { if !a.same(path_from_text("/usr/lib")) { return 12 } },
        none => { return 12 }
    }
    match ancestors.next() {
        present(a) => { if !a.same(path_from_text("/usr")) { return 13 } },
        none => { return 13 }
    }
    match ancestors.next() {
        present(a) => { if !a.same(path_from_text("/")) { return 14 } },
        none => { return 14 }
    }
    match ancestors.next() {
        none => {},
        _ => { return 15 }
    }

    // Relative paths and empty paths have no root.
    let relative = path_from_text("docs/readme.md")
    if relative.is_absolute() || !relative.is_relative() { return 16 }
    if !parent_is(relative, "docs") { return 17 }
    if !path_from_text("").is_empty() || !path_from_text("").is_relative() { return 18 }

    // Builders return new paths and leave the receiver alone.
    let base = path_from_text("/usr")
    let joined = base.join(path_from_text("lib"))
    if !text_is(read joined.as_path(), "/usr/lib") || !text_is(base, "/usr") { return 19 }
    let renamed = relative.with_file_name(os_str_from_text("guide.txt"))
    if !text_is(read renamed.as_path(), "docs/guide.txt") { return 20 }
    let retyped = path_from_text("archive.tar.gz").with_extension(os_str_from_text("zst"))
    if !text_is(read retyped.as_path(), "archive.tar.zst") { return 21 }
    let added = path_from_text("notes.txt").with_added_extension(os_str_from_text("bak"))
    if !text_is(read added.as_path(), "notes.txt.bak") { return 22 }

    // PathBuf constructors and mutators.
    var buffer = PathBuf.new()
    if !buffer.is_empty() || buffer.is_absolute() || !buffer.is_relative() { return 23 }
    buffer.push(path_from_text("/srv"))
    if !buf_text_is(read buffer, "/srv") || !buffer.is_absolute() || !buffer.has_root() { return 24 }
    buffer.push(path_from_text("data"))
    buffer.push(path_from_text("logs"))
    if !buf_text_is(read buffer, "/srv/data/logs") { return 25 }
    if !buffer.pop() || !buf_text_is(read buffer, "/srv/data") { return 26 }
    if !buffer.set_file_name(os_str_from_text("cache")) || !buf_text_is(read buffer, "/srv/cache") {
        return 27
    }
    if !buffer.set_extension(os_str_from_text("d")) || !buf_text_is(read buffer, "/srv/cache.d") {
        return 28
    }
    buffer.add_extension(os_str_from_text("old"))
    if !buf_text_is(read buffer, "/srv/cache.d.old") { return 29 }
    if !buffer.as_path().same(path_from_text("/srv/cache.d.old")) { return 30 }
    let owned = path_buf_from_text("/tmp/owned")
    if !owned.to_path_buf().same(read owned) { return 32 }
    if !parent_is(owned.as_path(), "/tmp") { return 33 }
    buffer.clear()
    if !buffer.is_empty() || !buffer.as_path().is_empty() { return 34 }
    var sized = PathBuf.with_capacity(64usize)
    if sized.capacity() < 64usize { return 36 }
    sized.reserve(128usize)
    sized.shrink_to_fit()
    if !sized.is_empty() { return 37 }
    let converted = capture owned.into_string()
    match take converted {
        success(text) => {},
        failure(error) => { return 38 }
    }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
