// expect-exit: 0
// Std value types clone (copies equal the original; owned buffers are
// independent) and io errors / exit statuses display like the reference.
import core.clone.Clone
import core.cmp.PartialEq
import alloc.string.ToString
import core.borrow.ToOwned
import std.fs
import std.ffi
import std.io
import std.io.{Error, ErrorKind}
import std.net
import std.path
import std.process
import std.time.{duration, now, unix_epoch}

fn shown<T: ToString>(read value: T): alloc.string.String { value.to_string() }
fn owned_ok<T: ToOwned>() {}
fn string_ok<T: ToString>() {}

// The ToOwned blanket now applies to these Clone types, and ToString to the
// newly Display types.
fn relations() {
    owned_ok<std.time.Duration>()
    owned_ok<std.time.Instant>()
    owned_ok<std.time.SystemTime>()
    owned_ok<std.net.Ipv4Addr>()
    owned_ok<std.net.Ipv6Addr>()
    owned_ok<std.net.IpAddr>()
    owned_ok<std.net.SocketAddr>()
    owned_ok<std.fs.FileType>()
    owned_ok<std.fs.Metadata>()
    owned_ok<std.fs.OpenOptions>()
    owned_ok<std.fs.Permissions>()
    owned_ok<ErrorKind>()
    owned_ok<std.path.PathBuf>()
    owned_ok<std.ffi.OsString>()
    owned_ok<std.process.ExitStatus>()
    owned_ok<std.process.Output>()
    string_ok<Error>()
    string_ok<ErrorKind>()
    string_ok<std.process.ExitStatus>()
}

fn main(): i32 {
    relations()
    let d = duration(3u64, 5u32)
    if d.clone() != d || d.to_owned() != d { return 1 }
    let t = now()
    if t.clone() != t || unix_epoch().clone() != unix_epoch() { return 2 }
    let ip = net.ipv4(127u8, 0u8, 0u8, 1u8)
    if ip.clone() != ip { return 3 }
    let kind = ErrorKind.NotFound
    if kind.clone() != kind { return 4 }
    var original = path.new_path_buf()
    original.push(path.path_from_text("a"))
    let copied = original.clone()
    original.push(path.path_from_text("b"))
    match copied.to_str() { present(text) => if text != "a" { return 5 }, none => { return 5 } }
    if shown(read ErrorKind.NotFound).as_text() != "entity not found" { return 6 }
    if shown(read ErrorKind.InvalidInput).as_text() != "invalid input parameter" { return 7 }
    if shown(read io.from_kind(ErrorKind.WriteZero)).as_text() != "write zero" { return 8 }
    let os = io.from_raw_os_error(2)
    let text = shown(read os)
    if !text.as_text().ends_with(" (os error 2)") || text.len() <= 13usize { return 9 }
    var command = process.command_text("/bin/sh")
    command.arg_text("-c")
    command.arg_text("exit 3")
    match capture command.status() {
        success(status) => if shown(read status).as_text() != "exit status: 3" { return 10 },
        failure(_) => { return 11 }
    }
    0
}
