// File create/write/seek/read, metadata, rename, remove and directory listing.
import std.io.{Error, ErrorKind, Reader, Writer}
import std.fs.SeekFrom
import core.iter.Iterator
import std.path.path_from_text

fn run(): i32 throws Error {
    try std.fs.create_dir_all(path_from_text("a/b/c"))
    try std.fs.create_dir_all(path_from_text("a/b/c"))
    {
        var o = std.fs.open_options()
        o.set_read(true)
        o.set_write(true)
        o.set_create(true)
        var f = try o.open(path_from_text("a/b/f.txt"))
        try f.write_all("hello world".as_bytes())
        let pos = try f.seek(SeekFrom.Start(6u64))
        if pos != 6u64 { return 1 }
        try f.write_all("WORLD".as_bytes())
        let m = try f.metadata()
        if m.len() != 11u64 || !m.is_file() { return 2 }
        let end = try f.seek(SeekFrom.End(-5i64))
        if end != 6u64 { return 3 }
        var buf = [0u8; 16]
        let n = try f.read_some(buf)
        if n != 5usize { return 4 }
        let back = try f.seek(SeekFrom.Current(-11i64))
        if back != 0u64 { return 5 }
        var all = alloc.vec.new<u8>()
        let total = try f.read_to_end(all)
        if total != 11usize || all[6usize] != 87u8 { return 6 }
    }
    let text = try std.fs.read_to_string(path_from_text("a/b/f.txt"))
    if text.len() != 11usize { return 7 }
    try std.fs.rename(path_from_text("a/b/f.txt"), path_from_text("a/g.txt"))
    if (try std.fs.exists(path_from_text("a/b/f.txt"))) || !(try std.fs.exists(path_from_text("a/g.txt"))) { return 8 }
    let dm = try std.fs.metadata(path_from_text("a/b"))
    if !dm.is_dir() { return 9 }
    var names = 0
    var rd = try std.fs.read_dir(path_from_text("a"))
    while true {
        let e = try rd.next_entry()
        match e { present(entry) => { names += 1 }, none => { break } }
    }
    match try rd.next_entry() { present(_) => { return 10 }, none => {} }
    if names != 2 { return 10 }
    // The listing is also a core Iterator over fallible entries.
    var listing = try std.fs.read_dir(path_from_text("a"))
    var seen = 0usize
    while true {
        match take listing.next() {
            present(item) => { match take item { success(entry) => { seen += 1usize }, failure(error) => { return 10 } } },
            none => { break }
        }
    }
    if seen != 2usize { return 10 }
    var counted = try std.fs.read_dir(path_from_text("a"))
    if counted.count() != 2usize { return 10 }
    // Removing a non-empty directory fails; removing contents first works.
    let busy = capture std.fs.remove_dir(path_from_text("a"))
    if busy.is_success() { return 11 }
    try std.fs.remove_file(path_from_text("a/g.txt"))
    try std.fs.remove_dir(path_from_text("a/b/c"))
    try std.fs.remove_dir(path_from_text("a/b"))
    try std.fs.remove_dir(path_from_text("a"))
    if try std.fs.exists(path_from_text("a")) { return 12 }
    // Append and truncate through OpenOptions.
    try std.fs.write(path_from_text("t"), "abc".as_bytes())
    {
        var o = std.fs.open_options()
        o.set_append(true)
        var f = try o.open(path_from_text("t"))
        try f.write_all("def".as_bytes())
    }
    let t = try std.fs.read_to_string(path_from_text("t"))
    if t.len() != 6usize { return 13 }
    {
        var f = try std.fs.create(path_from_text("t"))
        try f.set_len(2u64)
        let sz = try f.metadata()
        if sz.len() != 2u64 { return 15 }
    }
    let m2 = try std.fs.metadata(path_from_text("t"))
    if m2.len() != 2u64 { return 14 }
    try std.fs.create_dir_all(path_from_text("ops/nested"))
    try std.fs.write(path_from_text("ops/source"), "copy me".as_bytes())
    match take capture std.fs.create_dir_all(path_from_text("ops/source")) {
        success(_) => { return 27 },
        failure(e) => { if !e.kind().is(ErrorKind.AlreadyExists) { return 28 } }
    }
    if try std.fs.copy(path_from_text("ops/source"), path_from_text("ops/copied")) != 7u64 {
        return 16
    }
    if (try std.fs.read_to_string(path_from_text("ops/copied"))).as_text() != "copy me" { return 17 }
    try std.fs.hard_link(path_from_text("ops/source"), path_from_text("ops/hard"))
    if (try std.fs.read_to_string(path_from_text("ops/hard"))).as_text() != "copy me" { return 18 }
    try std.fs.soft_link(path_from_text("source"), path_from_text("ops/soft"))
    let target = try std.fs.read_link(path_from_text("ops/soft"))
    if !target.same(std.ffi.os_string_from_text("source")) { return 19 }
    let source_path = path_from_text("ops/source")
    if !source_path.exists() || !source_path.is_file() || source_path.is_dir() ||
       !(try source_path.try_exists()) { return 24 }
    if !(try source_path.canonicalize()).is_absolute() ||
       !path_from_text("ops/soft").is_symlink() {
        return 25
    }
    try std.fs.set_permissions(path_from_text("ops/copied"), std.fs.permissions_from_mode(384u32))
    let copied_metadata = try std.fs.metadata(path_from_text("ops/copied"))
    if (copied_metadata.permissions().mode() & 511u32) != 384u32 {
        return 20
    }
    if !(try std.fs.canonicalize(path_from_text("ops/source"))).is_absolute() { return 21 }
    if !try std.fs.try_exists(path_from_text("ops/source")) { return 22 }
    try std.fs.remove_dir_all(path_from_text("ops"))
    if try std.fs.exists(path_from_text("ops")) { return 23 }
    var dirs = std.fs.DirBuilder.new()
    dirs.recursive(true)
    try dirs.create(path_from_text("builder/a/b"))
    if !(try std.fs.metadata(path_from_text("builder/a/b"))).is_dir() { return 26 }
    try std.fs.remove_dir_all(path_from_text("builder"))
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => { match e.raw_os_error() { present(c) => 100 + c, none => 99 } } }
}
