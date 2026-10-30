// File create/write/seek/read, metadata, rename, remove and directory listing.
import std::io::{Error, ErrorKind, Read, Write};
import std::fs::SeekFrom;
import core::iter::Iterator;
import std::path::path_from_text;

fn run(): i32 throws Error {
    try std::fs::create_dir_all(path_from_text("a/b/c"))
    try std::fs::create_dir_all(path_from_text("a/b/c"))
    {
        var o = std::fs::open_options()
        o.set_read(true)
        o.set_write(true)
        o.set_create(true)
        var f = try o.open(path_from_text("a/b/f.txt"))
        try f.write_all("hello world".as_bytes())
        let pos = try f.seek(SeekFrom::Start(6u64))
        if pos != 6u64 { return 1 }
        try f.write_all("WORLD".as_bytes())
        let m = try f.metadata()
        if m.len() != 11u64 || !m.is_file() { return 2 }
        let end = try f.seek(SeekFrom::End(-5i64))
        if end != 6u64 { return 3 }
        var buf = [0u8; 16]
        let n = try f.read_some(buf)
        if n != 5usize { return 4 }
        let back = try f.seek(SeekFrom::Current(-11i64))
        if back != 0u64 { return 5 }
        var all = alloc::vec::new::<u8>()
        let total = try f.read_to_end(all)
        if total != 11usize || all[6usize] != 87u8 { return 6 }
    }
    let text = try std::fs::read_to_string(path_from_text("a/b/f.txt"))
    if text.len() != 11usize { return 7 }
    try std::fs::rename(path_from_text("a/b/f.txt"), path_from_text("a/g.txt"))
    if std::fs::exists(path_from_text("a/b/f.txt")) || !std::fs::exists(path_from_text("a/g.txt")) { return 8 }
    let dm = try std::fs::metadata(path_from_text("a/b"))
    if !dm.is_dir() { return 9 }
    var names = 0
    var rd = try std::fs::read_dir(path_from_text("a"))
    while true {
        let e = try rd.next_entry()
        match e { present(entry) => { names += 1 }, none => { break } }
    }
    if names != 2 { return 10 }
    // The listing is also a core Iterator over fallible entries.
    var listing = try std::fs::read_dir(path_from_text("a"))
    var seen = 0usize
    while true {
        match take listing.next() {
            present(item) => { match take item { success(entry) => { seen += 1usize }, failure(error) => { return 10 } } },
            none => { break }
        }
    }
    if seen != 2usize { return 10 }
    var counted = try std::fs::read_dir(path_from_text("a"))
    if counted.count() != 2usize { return 10 }
    // Removing a non-empty directory fails; removing contents first works.
    let busy = capture std::fs::remove_dir(path_from_text("a"))
    if busy.is_success() { return 11 }
    try std::fs::remove_file(path_from_text("a/g.txt"))
    try std::fs::remove_dir(path_from_text("a/b/c"))
    try std::fs::remove_dir(path_from_text("a/b"))
    try std::fs::remove_dir(path_from_text("a"))
    if std::fs::exists(path_from_text("a")) { return 12 }
    // Append and truncate through OpenOptions.
    try std::fs::write(path_from_text("t"), "abc".as_bytes())
    {
        var o = std::fs::open_options()
        o.set_append(true)
        var f = try o.open(path_from_text("t"))
        try f.write_all("def".as_bytes())
    }
    let t = try std::fs::read_to_string(path_from_text("t"))
    if t.len() != 6usize { return 13 }
    {
        var f = try std::fs::create(path_from_text("t"))
        try f.set_len(2u64)
        let sz = try f.metadata()
        if sz.len() != 2u64 { return 15 }
    }
    let m2 = try std::fs::metadata(path_from_text("t"))
    if m2.len() != 2u64 { return 14 }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => { match e.raw_os_error() { present(c) => 100 + c, none => 99 } } }
}
