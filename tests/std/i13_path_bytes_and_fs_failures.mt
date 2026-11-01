// OS path bytes round-trip without Unicode conversion; filesystem failures
// retain their portable error kind and directory EOF is independent of errno.
import std.ffi
import std.fs.{OpenOptions, SeekFrom}
import std.io.{Error, ErrorKind}
import std.path.{path, path_from_text}

fn run(): i32 throws Error {
    let raw: [u8; 5] = [46u8, 105u8, 49u8, 51u8, 255u8]
    let path_view = path(raw)
    match path_view.to_str() {
        present(text) => { return 1 },
        none => {}
    }
    let owned_path = path_view.to_path_buf()
    let owned_os = owned_path.into_os_string()
    if !ffi.bytes_equal(owned_os.as_encoded_bytes(), raw) { return 2 }
    if !owned_os.as_os_str().same(ffi.os_str(raw)) { return 3 }

    let nul_path: [u8; 3] = [97u8, 0u8, 98u8]
    let nul_result = capture std.fs.metadata(path(nul_path))
    match take nul_result {
        success(metadata) => { return 4 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 5 }
        }
    }

    var no_access = OpenOptions.new()
    let no_access_result = capture no_access.open(path_from_text("i13-no-access"))
    match take no_access_result {
        success(file) => { return 6 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 7 }
        }
    }

    var file = try std.fs.create(path_from_text("i13-offset-boundary"))
    let too_large_seek = capture file.seek(SeekFrom.Start(9223372036854775808u64))
    match take too_large_seek {
        success(position) => { return 8 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 9 }
        }
    }
    let too_large_len = capture file.set_len(9223372036854775808u64)
    match take too_large_len {
        success(unit) => { return 10 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 11 }
        }
    }
    core.mem.drop(take file)
    try std.fs.remove_file(path_from_text("i13-offset-boundary"))

    let missing = capture std.fs.metadata(path_from_text("i13-missing-before-readdir"))
    if missing.is_success() { return 12 }
    try std.fs.create_dir(path_from_text("i13-empty-directory"))
    {
        var entries = try std.fs.read_dir(path_from_text("i13-empty-directory"))
        match try entries.next_entry() {
            present(entry) => { return 13 },
            none => {}
        }
        match try entries.next_entry() {
            present(entry) => { return 14 },
            none => {}
        }
    }
    try std.fs.remove_dir(path_from_text("i13-empty-directory"))
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
