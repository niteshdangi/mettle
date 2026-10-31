// Metadata.accessed on every platform; Metadata.created where recorded
// (Darwin) and Unsupported elsewhere.
import std.io.{Error, ErrorKind, Reader, Writer}
import std.path.path_from_text

fn run(): i32 throws Error {
    {
        var f = try std.fs.File.create(path_from_text("times.txt"))
        try f.write_all("abc".as_bytes())
    }
    let stat = try std.fs.metadata(path_from_text("times.txt"))
    if stat.accessed().unix_secs() <= 0i64 { return 1 }
    if stat.modified().unix_secs() <= 0i64 { return 2 }
    let made = capture stat.created()
    match take made {
        success(t) => { if t.unix_secs() <= 0i64 { return 3 } },
        failure(e) => { if !e.kind().is(ErrorKind.Unsupported) { return 4 } }
    }
    let handle = try std.fs.open(path_from_text("times.txt"))
    let open_stat = try handle.metadata()
    if open_stat.accessed().unix_secs() <= 0i64 { return 5 }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => { match e.raw_os_error() { present(c) => 100 + c, none => 99 } } }
}
