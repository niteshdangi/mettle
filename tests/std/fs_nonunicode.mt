// Paths and OS strings hold arbitrary bytes and round-trip them losslessly.
// linux-expect-stdout: non-utf8 name on disk
import std.io.{Error, ErrorKind, Writer}
import std.path.path
import std.path.path_from_text
import std.ffi

fn on_disk(read p: std.path.Path, read raw: [u8]): i32 throws Error {
    if !(try std.fs.exists(p)) { return 3 }
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
    if try std.fs.exists(p) { return 11 }
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
    let raw_view = ffi.os_str(raw)
    if !os.as_os_str().same(raw_view) ||
       !raw_view.to_os_string().same(read os) { return 14 }
    var appended = ffi.new_os_string()
    appended.push(ffi.os_str_from_text("prefix"))
    appended.push_bytes(raw)
    let appended_bytes = appended.into_bytes()
    if appended_bytes.len() != 12usize ||
       !ffi.bytes_equal(appended_bytes.as_slice().split_at(6usize).1, raw) {
        return 15
    }
    let rebuilt = ffi.os_string_from_vec(appended_bytes)
    let expected: [u8; 12] = [
        112u8, 114u8, 101u8, 102u8, 105u8, 120u8,
        102u8, 0xffu8, 0xfeu8, 46u8, 116u8, 120u8
    ]
    if !ffi.bytes_equal(rebuilt.as_bytes(), expected) { return 16 }
    let empty_os = ffi.new_os_string()
    if !empty_os.is_empty() || empty_os.len() != 0usize { return 17 }
    let text_view = ffi.os_str_from_text("plain")
    if text_view.is_empty() || text_view.len() != 5usize { return 18 }
    match text_view.to_str() {
        present(text) => { if text != "plain" { return 19 } },
        none => { return 20 }
    }
    if text_view.to_string_lossy().as_ref().len() != 5usize ||
       !ffi.os_string_from_text("plain").as_os_str().same(text_view) {
        return 21
    }
    let mixed = ffi.os_string_from_bytes([65u8, 98u8, 0xffu8, 90u8])
    if mixed.is_ascii() { return 22 }
    if !mixed.eq_ignore_ascii_case(ffi.os_string_from_bytes([97u8, 66u8, 0xffu8, 122u8])) {
        return 23
    }
    let lower = mixed.to_ascii_lowercase()
    let lower_bytes: [u8; 4] = [97u8, 98u8, 0xffu8, 122u8]
    if !ffi.bytes_equal(lower.as_encoded_bytes(), lower_bytes) { return 24 }
    var upper = mixed
    upper.as_mut_os_str().make_ascii_uppercase()
    let upper_bytes: [u8; 4] = [65u8, 66u8, 0xffu8, 90u8]
    if !ffi.bytes_equal(upper.as_encoded_bytes(), upper_bytes) { return 25 }
    var encoded_bytes = alloc.vec.new<u8>()
    encoded_bytes.extend_from_slice("plain".as_bytes())
    let encoded = ffi.OsString.from_encoded_bytes_unchecked(encoded_bytes)
    let decoded = capture encoded.into_string()
    match take decoded {
        success(text) => { if text.as_text() != "plain" { return 28 } },
        failure(error) => { return 29 }
    }
    var reserved = ffi.os_string_with_capacity(24usize)
    if reserved.capacity() < 24usize { return 26 }
    reserved.reserve(8usize)
    reserved.reserve_exact(8usize)
    reserved.push(ffi.os_str_from_text("data"))
    reserved.shrink_to_fit()
    reserved.clear()
    if !reserved.is_empty() { return 27 }
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
