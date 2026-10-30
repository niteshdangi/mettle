// Path decomposition edge cases.
import std.path.path_from_text
import std.path.Path

fn name_is(p: read Path, want: read Text): bool {
    match p.file_name() { present(n) => { match n.to_str() { present(t) => t == want, none => false } }, none => false }
}
fn has_no_name(p: read Path): bool { match p.file_name() { present(n) => false, none => true } }
fn parent_is(p: read Path, want: read Text): bool {
    match p.parent() { present(q) => q.same(path_from_text(want)), none => false }
}
fn ext_is(p: read Path, want: read Text): bool {
    match p.extension() { present(x) => { match x.to_str() { present(t) => t == want, none => false } }, none => false }
}
fn has_no_ext(p: read Path): bool { match p.extension() { present(x) => false, none => true } }

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
    0
}
