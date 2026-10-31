// File sync_all/sync_data/try_clone (shared offset), permissions round trip,
// and Command.get_envs / process id observation.
import std.io.{Error, ErrorKind, Reader, Writer}
import std.io.SeekFrom
import std.ffi
import std.path.path_from_text

fn run(): i32 throws Error {
    {
        var f = try std.fs.File.create(path_from_text("sync.txt"))
        try f.write_all("abcdef".as_bytes())
        try f.sync_all()
        try f.sync_data()
        var twin = try f.try_clone()
        // The duplicate shares the open file description, hence the offset.
        let pos = try twin.seek(SeekFrom.Current(0i64))
        if pos != 6u64 { return 1 }
        try twin.write_all("gh".as_bytes())
        let size = try f.metadata()
        if size.len() != 8u64 { return 2 }
        try f.set_len(3u64)
        let shrunk = try twin.metadata()
        if shrunk.len() != 3u64 { return 3 }
    }
    let text = try std.fs.read_to_string(path_from_text("sync.txt"))
    if text.len() != 3usize { return 4 }
    var perms = std.fs.permissions_from_mode(420u32)
    if perms.readonly() { return 5 }
    perms.set_readonly(true)
    if !perms.readonly() { return 6 }
    try std.fs.set_permissions(path_from_text("sync.txt"), perms)
    let stat = try std.fs.metadata(path_from_text("sync.txt"))
    if !stat.permissions().readonly() { return 7 }
    let denied = capture std.fs.OpenOptions.new().open(path_from_text("sync.txt"))
    match take denied { success(_) => {}, failure(_) => { return 8 } }
    var reopen = std.fs.OpenOptions.new()
    reopen.write(true)
    let blocked = capture reopen.open(path_from_text("sync.txt"))
    match take blocked {
        success(_) => {},
        failure(e) => { if !e.kind().is(ErrorKind.PermissionDenied) { return 9 } }
    }
    var c = std.process.command_text("/bin/true")
    c.env_clear()
    c.env(ffi.os_str_from_text("A"), ffi.os_str_from_text("1"))
    c.env(ffi.os_str_from_text("A"), ffi.os_str_from_text("2"))
    let envs = c.get_envs()
    if envs.len() != 1usize { return 10 }
    if !envs[0usize].value.as_os_str().same(ffi.os_str_from_text("2")) { return 11 }
    if std.process.id() <= 0 { return 12 }
    var child = try c.spawn()
    if child.id() <= 0 { return 13 }
    let status = try child.wait()
    if !status.success() { return 14 }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => { match e.raw_os_error() { present(c) => 100 + c, none => 99 } } }
}
