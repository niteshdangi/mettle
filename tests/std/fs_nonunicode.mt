// Paths and OS strings hold arbitrary bytes and round-trip them losslessly.
// linux-expect-stdout: non-utf8 name on disk
import std.io.{Error, ErrorKind, Writer};
import std.path.path;
import std.path.path_from_text;
import std.ffi;

fn on_disk(p: read std.path.Path, raw: read [u8]): i32 throws Error {
    if !std.fs.exists(p) { return 3 }
    let text = try std.fs.read_to_string(p)
    if text.len() != 7usize { return 4 }
    // The listing returns the name byte for byte.
    var found = 0
    var rd = try std.fs.read_dir(path_from_text("."))
    while true {
        let e = try rd.next_entry()
        match e {
            present(entry) => {
                if ffi.bytes_equal(entry.file_name().as_bytes(), raw) { found += 1 }
            },
            none => { break }
        }
    }
    if found != 1 { return 5 }
    try std.fs.rename(p, path_from_text("plain"))
    if std.fs.exists(p) { return 11 }
    try std.fs.remove_file(path_from_text("plain"))
    0
}

fn run(): i32 throws Error {
    let raw: [u8; 6] = [102u8, 0xffu8, 0xfeu8, 46u8, 116u8, 120u8]
    // Bytes that are not UTF-8 are kept; to_str reports none, lossy substitutes.
    let p = path(raw)
    match p.to_str() { present(t) => { return 1 }, none => {} }
    let lossy = p.to_string_lossy()
    if lossy.len() != 10usize { return 2 }
    // The same on-disk checks with a multi-byte UTF-8 name run everywhere.
    let utf: [u8; 6] = [99u8, 0xc3u8, 0xa9u8, 46u8, 116u8, 120u8]
    try std.fs.write(path(utf), "payload".as_bytes())
    let code0 = try on_disk(path(utf), utf)
    if code0 != 0 { return code0 }
    // Some file systems (APFS) reject non-UTF-8 names with EILSEQ (92 on macOS, 84 on
    // Linux); the error must then carry that raw number and the on-disk part is skipped.
    let made = capture std.fs.write(p, "payload".as_bytes())
    if made.is_failure() {
        match take made { success(u) => { return 20 }, failure(e) => { if e.raw_os_error() != present(92) && e.raw_os_error() != present(84) { return 21 } } }
    } else {
        let code = try on_disk(p, raw)
        if code != 0 { return code }
        var out = std.io.stdout()
        try out.write_all("non-utf8 name on disk\n".as_bytes())
    }
    // Joining keeps the bytes, and file_name / extension split on them.
    let joined = path_from_text("dir").join(p)
    let name = joined.as_path().file_name()
    match name { present(n) => { if !ffi.bytes_equal(n.as_bytes(), raw) { return 6 } }, none => { return 7 } }
    match joined.as_path().extension() { present(x) => { if !x.same(ffi.os_str_from_text("tx")) { return 8 } }, none => { return 9 } }
    // An OsString built from bytes returns the same bytes.
    let os = ffi.os_string_from_bytes(raw)
    if os.len() != 6usize || !ffi.bytes_equal(os.as_bytes(), raw) { return 10 }
    // Interior NUL cannot name a file.
    let bad: [u8; 3] = [97u8, 0u8, 98u8]
    let r = capture std.fs.write(path(bad), "x".as_bytes())
    match take r {
        success(u) => { return 12 },
        failure(e) => { if !e.kind().is(ErrorKind.InvalidInput) { return 13 } }
    }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => { match e.raw_os_error() { present(c) => 100 + c, none => 99 } } }
}
