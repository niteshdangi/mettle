// Path decomposition edge cases.
import std.path.path_from_text
import std.path.Path

fn name_is(read p: Path, read want: Text): bool {
    match p.file_name() { present(n) => { match n.to_str() { present(t) => t == want, none => false } }, none => false }
}
fn has_no_name(read p: Path): bool { match p.file_name() { present(n) => false, none => true } }
fn parent_is(read p: Path, read want: Text): bool {
    match p.parent() { present(q) => q.same(path_from_text(want)), none => false }
}
fn ext_is(read p: Path, read want: Text): bool {
    match p.extension() { present(x) => { match x.to_str() { present(t) => t == want, none => false } }, none => false }
}
fn has_no_ext(read p: Path): bool { match p.extension() { present(x) => false, none => true } }

fn main(): i32 {
    if !name_is(path_from_text("/a/b.txt"), "b.txt") { return 1 }
    if !name_is(path_from_text("a/b/"), "b") { return 2 }
    if !has_no_name(path_from_text("/")) { return 3 }
    if !has_no_name(path_from_text("a/..")) { return 4 }
    if !parent_is(path_from_text("a/b"), "a") { return 5 }
    if !parent_is(path_from_text("a"), "") { return 6 }
    if !parent_is(path_from_text("/a"), "/") { return 7 }
    match path_from_text("/").parent() { present(q) => { return 8 }, none => {} }
    if !ext_is(path_from_text("x.tar.gz"), "gz") { return 9 }
    if !has_no_ext(path_from_text(".hidden")) { return 10 }
    if !has_no_ext(path_from_text("noext")) { return 11 }
    if !path_from_text("/a/b").is_absolute() || path_from_text("a").is_absolute() { return 12 }
    if !path_from_text("a/b/c").starts_with(path_from_text("a/b")) { return 13 }
    if path_from_text("a/bc").starts_with(path_from_text("a/b")) { return 14 }
    var buf = path_from_text("a").join(path_from_text("b"))
    if !buf.as_path().same(path_from_text("a/b")) { return 15 }
    // Joining an absolute path replaces the base.
    let abs = path_from_text("a").join(path_from_text("/z"))
    if !abs.as_path().same(path_from_text("/z")) { return 16 }
    buf.push(path_from_text("c"))
    if !buf.as_path().same(path_from_text("a/b/c")) { return 17 }
    let popped = buf.pop()
    if !popped || !buf.as_path().same(path_from_text("a/b")) { return 18 }
    if !path_from_text("/a").has_root() || path_from_text("a").is_absolute() ||
       !path_from_text("a").is_relative() { return 19 }
    if !path_from_text("a/b/").ends_with(path_from_text("b")) ||
       path_from_text("a/bc").ends_with(path_from_text("b")) { return 20 }
    match path_from_text("a/b/c").strip_prefix(path_from_text("a")) {
        present(rest) => { if !rest.same(path_from_text("b/c")) { return 21 } },
        none => { return 21 }
    }
    match path_from_text("file.tar.gz").file_prefix() {
        present(prefix) => {
            match prefix.to_str() {
                present(text) => { if text != "file" { return 22 } },
                none => { return 22 }
            }
        },
        none => { return 22 }
    }
    let replaced = path_from_text("dir/name.txt").with_extension(
        std.ffi.os_str_from_text("log")
    )
    if !replaced.as_path().same(path_from_text("dir/name.log")) { return 23 }
    let added = path_from_text("dir/name.txt").with_added_extension(
        std.ffi.os_str_from_text("bak")
    )
    if !added.as_path().same(path_from_text("dir/name.txt.bak")) { return 24 }
    var changed = path_from_text("dir/name.txt").to_path_buf()
    if !changed.set_file_name(std.ffi.os_str_from_text("other")) ||
       !changed.as_path().same(path_from_text("dir/other")) { return 25 }
    if !changed.set_extension(std.ffi.os_str_from_text("log")) ||
       !changed.as_path().same(path_from_text("dir/other.log")) { return 26 }
    changed.clear()
    if !changed.is_empty() { return 27 }
    0
}
