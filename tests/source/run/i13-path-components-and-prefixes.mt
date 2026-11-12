// profiles: debug release
// Path and PathBuf component iteration, prefix and suffix tests, prefix
// stripping, capacity, and lossy conversion.

import core.iter.{BidirectionalIterator, Iterator}
import alloc.string.ToString
import std.ffi.os_str_from_text
import std.path.{Component, Path, PathBuf, StripPrefixError, path, path_from_text, path_buf_from_text}

fn normal_is(c: Component, read want: Text): bool {
    match c {
        Component.Normal(name) => match name.to_str() { present(t) => t == want, none => false },
        _ => false
    }
}

fn component_count(read p: Path): usize {
    var n = 0usize
    var it = p.components()
    while true {
        match it.next() {
            present(_) => { n += 1usize },
            none => { break }
        }
    }
    n
}

fn checks_components(): i32 {
    let p = path_from_text("/a/./b/../c")
    if component_count(p) != 5usize { return 1 }
    var it = p.components()
    match it.next() {
        present(c) => { match c { Component.RootDir => {}, _ => { return 2 } } },
        none => { return 2 }
    }
    match it.next_back() {
        present(c) => { if !normal_is(c, "c") { return 3 } },
        none => { return 3 }
    }
    match it.next() {
        present(c) => { if !normal_is(c, "a") { return 4 } },
        none => { return 4 }
    }
    let leading = path_from_text("./x")
    var lead = leading.components()
    match lead.next() {
        present(c) => { match c { Component.CurDir => {}, _ => { return 5 } } },
        none => { return 5 }
    }
    if component_count(path_from_text("")) != 0usize { return 6 }
    if component_count(path_from_text("/")) != 1usize { return 7 }

    var walked = 0usize
    var iterated = path_from_text("x/../y").iter()
    while true {
        match iterated.next() {
            present(_) => { walked += 1usize },
            none => { break }
        }
    }
    if walked != 3usize { return 8 }
    0
}

fn checks_prefix_and_suffix(): i32 {
    let p = path_from_text("/usr/lib")
    if !p.starts_with(path_from_text("/usr")) || !p.starts_with(path_from_text("/usr/lib")) { return 10 }
    if p.starts_with(path_from_text("/us")) || p.starts_with(path_from_text("usr")) { return 11 }
    if !p.ends_with(path_from_text("lib")) || !p.ends_with(path_from_text("usr/lib")) { return 12 }
    if p.ends_with(path_from_text("ib")) || p.ends_with(path_from_text("/lib/x")) { return 13 }
    if !path_from_text("a/b/").starts_with(path_from_text("a/b")) { return 14 }
    match capture p.strip_prefix(path_from_text("/usr")) {
        success(rest) => { if !rest.same(path_from_text("lib")) { return 15 } },
        failure(_) => { return 15 }
    }
    match capture p.strip_prefix(path_from_text("/var")) {
        success(_) => { return 16 },
        failure(error) => { let _error: StripPrefixError = error }
    }
    if !p.same(path_from_text("/usr/lib")) { return 47 }

    let buf = path_buf_from_text("/srv/data")
    if !buf.starts_with(path_from_text("/srv")) || !buf.ends_with(path_from_text("data")) { return 17 }
    match capture buf.strip_prefix(path_from_text("/srv")) {
        success(rest) => { if !rest.same(path_from_text("data")) { return 18 } },
        failure(_) => { return 18 }
    }
    match capture buf.strip_prefix(path_from_text("/var")) {
        success(_) => { return 48 },
        failure(error) => { let _error: StripPrefixError = error }
    }
    if !buf.as_path().same(path_from_text("/srv/data")) { return 49 }
    if component_count(buf.as_path()) != 3usize { return 19 }
    0
}

fn checks_buffers(): i32 {
    var buf = PathBuf.new()
    buf.push(path_from_text("/root"))
    buf.push(path_from_text("/etc"))
    if buf.as_bytes().len() != 4usize { return 20 }
    buf.push(path_from_text("hosts"))
    if !buf.to_path_buf().same(read buf) || !buf.as_path().same(path_from_text("/etc/hosts")) { return 21 }
    var ancestors = buf.ancestors()
    var seen = 0usize
    while true {
        match ancestors.next() {
            present(_) => { seen += 1usize },
            none => { break }
        }
    }
    if seen != 3usize { return 22 }
    if !buf.iter().next().is_present() { return 23 }

    let file = path_buf_from_text("/srv/data.tar.gz")
    if !file.file_name().is_present() || !file.extension().is_present() { return 40 }
    if !file.file_stem().is_present() || !file.file_prefix().is_present() { return 41 }
    match file.parent() {
        present(q) => { if !q.same(path_from_text("/srv")) { return 42 } },
        none => { return 42 }
    }
    if !file.join(path_from_text("x")).same(path_buf_from_text("/srv/data.tar.gz/x")) { return 43 }
    if !file.with_extension(os_str_from_text("zip")).same(path_buf_from_text("/srv/data.tar.zip")) { return 44 }
    if !file.with_file_name(os_str_from_text("n")).same(path_buf_from_text("/srv/n")) { return 45 }
    if !file.with_added_extension(os_str_from_text("bak")).same(path_buf_from_text("/srv/data.tar.gz.bak")) { return 46 }

    buf.reserve_exact(64usize)
    if buf.capacity() < 64usize { return 24 }
    match capture buf.try_reserve(16usize) {
        success(_) => {},
        failure(_) => { return 25 }
    }
    match capture buf.try_reserve_exact(16usize) {
        success(_) => {},
        failure(_) => { return 26 }
    }
    buf.shrink_to(0usize)
    if buf.as_os_str().len() != 10usize { return 27 }
    let owned = buf.into_os_string()
    if owned.len() != 10usize { return 28 }
    0
}

fn checks_lossy(): i32 {
    let bytes: [u8; 3] = [0x61u8, 0xffu8, 0x62u8]
    let raw = path(bytes)
    if raw.to_string_lossy().as_text() != "a\u{fffd}b" { return 30 }
    if raw.display().to_string().as_text() != "a\u{fffd}b" { return 31 }
    if raw.to_str().is_present() { return 32 }
    let owned = raw.into_path_buf()
    if owned.to_string_lossy().as_text() != "a\u{fffd}b" { return 33 }
    0
}

fn main(): i32 {
    let first = checks_components()
    if first != 0 { return first }
    let second = checks_prefix_and_suffix()
    if second != 0 { return second }
    let third = checks_buffers()
    if third != 0 { return third }
    checks_lossy()
}
