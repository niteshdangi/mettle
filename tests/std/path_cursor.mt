import std.path.{path_from_text, path_buf_from_text}
import std.io.{Error, ErrorKind, BufRead, Seek, Reader, Writer}
import std.ffi.CStr
import alloc.vec
import alloc.vec.List
import core.iter.Iterator

fn run(): i32 throws Error {
    let path = path_from_text("/a/b")
    var parts = path.components()
    match parts.next() {
        present(part) => { if part.as_bytes()[0usize] != 47u8 { return 1 } },
        none => { return 2 }
    }
    match parts.next() {
        present(part) => { if part.as_bytes()[0usize] != 97u8 { return 3 } },
        none => { return 4 }
    }
    match parts.next() {
        present(part) => { if part.as_bytes()[0usize] != 98u8 { return 5 } },
        none => { return 6 }
    }
    if parts.next().is_present() { return 7 }
    var ancestors = path.ancestors()
    if ancestors.next().is_none() || ancestors.next().is_none() || ancestors.next().is_none() { return 8 }
    if ancestors.next().is_present() { return 9 }

    var owned = path_buf_from_text("rel")
    owned.as_mut_os_string().push_bytes([47u8, 120u8])
    if owned.as_bytes().len() != 5usize { return 10 }
    let boxed = owned.into_boxed_path()
    if boxed.as_bytes().len() != 5usize { return 11 }

    var cursor = std.io.Cursor<List<u8>>.new(vec.new<u8>())
    try cursor.write_all([104u8, 105u8])
    try cursor.rewind()
    if cursor.stream_position() != 0u64 { return 12 }
    var got = [0u8; 2]
    try cursor.read_exact(got)
    if got[0usize] != 104u8 || got[1usize] != 105u8 { return 13 }
    cursor.set_position(1u64)
    let skipped = try cursor.skip_until(105u8)
    if skipped != 1usize { return 14 }
    if cursor.into_inner().len() != 2usize { return 15 }

    var source = vec.new<u8>()
    source.extend_from_slice([97u8, 98u8, 88u8, 99u8])
    var buffered = std.io.buf_reader(std.io.Cursor<List<u8>>.new(source))
    let until = try buffered.skip_until(88u8)
    if until != 3usize { return 16 }
    if buffered.buffer().len() == 0usize { return 17 }

    var raw = [104u8, 0u8]
    match capture CStr.from_bytes_with_nul(raw) {
        success(text) => { if text.count_bytes() != 1usize { return 18 } },
        failure(_) => { return 19 }
    }
    var mixed = [104u8, 0u8, 105u8]
    match CStr.from_bytes_until_nul(mixed) {
        present(text) => { if text.count_bytes() != 1usize { return 20 } },
        none => { return 21 }
    }
    if !Error.other().kind().is(ErrorKind.Other) { return 22 }
    0
}
