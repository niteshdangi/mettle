// profiles: debug release
import core.cmp.PartialEq
import core.iter.Iterator
import core.default.Default
import core.text.{Text, from_utf8}

fn count_parts(parts: take Iterator): usize {
    var n = 0usize
    for _ in parts { n += 1usize }
    n
}

fn main(): i32 {
    let s = "  a,b,,c  "
    if s.trim() != "a,b,,c" || s.trim_start() != "a,b,,c  " || s.trim_end() != "  a,b,,c" { return 1 }
    if s.trim_matches(' ') != "a,b,,c" || "xxhixx".trim_start_matches('x') != "hixx" { return 2 }
    if "xxhixx".trim_end_matches("x") != "xxhi" { return 3 }
    if !s.contains("b,") || s.contains("zz") || !s.starts_with("  a") || s.ends_with("a") { return 4 }
    match "hello.rs".strip_suffix(".rs") { present(t) => { if t != "hello" { return 5 } }, none => { return 5 } }
    match "hello".strip_prefix("he") { present(_) => {}, none => { return 6 } }
    match "a=b=c".split_once("=") {
        present((l, r)) => { if l != "a" || r != "b=c" { return 7 } },
        none => { return 7 }
    }
    match "a=b=c".rsplit_once("=") {
        present((l, r)) => { if l != "a=b" || r != "c" { return 8 } },
        none => { return 8 }
    }
    match "abcdef".find("cd") { present(i) => { if i != 2usize { return 9 } }, none => { return 9 } }
    match "abcabc".rfind("bc") { present(i) => { if i != 4usize { return 10 } }, none => { return 10 } }
    if !"abc".find("z").is_none() { return 11 }
    let halves = "abcdef".split_at(2usize)
    if halves.0 != "ab" || halves.1 != "cdef" { return 12 }
    if count_parts("a,b,c".split(",")) != 3usize || count_parts("a,b,c".rsplit(",")) != 3usize { return 13 }
    if count_parts("a,b,c".splitn(2usize, ",")) != 2usize || count_parts("a,b,c".rsplitn(2usize, ",")) != 2usize { return 14 }
    if count_parts("a,b,".split_terminator(",")) != 2usize || count_parts("a,b".split_inclusive(",")) != 2usize { return 15 }
    if count_parts("a  b\tc".split_whitespace()) != 3usize || count_parts("x\ny\n".lines()) != 2usize { return 16 }
    if count_parts("a1b1c".matches("1")) != 2usize || count_parts("a1b1c".match_indices("1")) != 2usize { return 17 }
    if "héllo".len() != 6usize || "héllo".char_indices().count() != 5usize { return 18 }
    if !"abc".is_char_boundary(1usize) || "é".is_char_boundary(1usize) { return 19 }
    if "ABC".eq_ignore_ascii_case("abc") != true || !"  x ".trim_ascii().eq_ignore_ascii_case("X") { return 20 }
    let bytes = "hi".as_bytes()
    if bytes.len() != 2usize || bytes[0usize] != 104u8 { return 21 }
    let bad = [0xffu8]
    match from_utf8(read bad) { present(_) => { return 24 }, none => {} }
    if !"abc".get(0usize, 9usize).is_none() { return 25 }
    0
}
