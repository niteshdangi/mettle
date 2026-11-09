// Command builder and child results: arguments, environment edits, working directory,
// captured output, exit statuses and piped stdin.
import std.io.{Error, Reader, Writer}
import std.process.{Stdio}
import std.ffi
import std.path.path_from_text

fn sh(read script: Text): std.process.Command {
    var c = std.process.command_text("/bin/sh")
    c.arg(ffi.os_str_from_text("-c"))
    c.arg(ffi.os_str_from_text(script))
    c
}

fn run(): i32 throws Error {
    var echo = std.process.command_text("/bin/sh")
    echo.arg(ffi.os_str_from_text("-c"))
    echo.arg(ffi.os_str_from_text("printf '%s|%s' \"$MT_A\" \"$MT_B\"; printf err >&2"))
    echo.env(ffi.os_str_from_text("MT_A"), ffi.os_str_from_text("alpha"))
    echo.env(ffi.os_str_from_text("MT_B"), ffi.os_str_from_text("beta"))
    echo.env_remove(ffi.os_str_from_text("MT_B"))
    echo.env(ffi.os_str_from_text("MT_B"), ffi.os_str_from_text("gamma"))
    let output = try echo.output()
    if !output.status.succeeded() || output.status.code() != present(0) { return 1 }
    if output.stdout.len() != 11usize || output.stderr.len() != 3usize { return 2 }
    if output.stdout[0usize] != 97u8 || output.stdout[10usize] != 97u8 { return 3 }
    if output.stderr[0usize] != 101u8 { return 4 }

    var quiet = sh("exit 3")
    let status = try quiet.status()
    if status.succeeded() { return 5 }
    match status.code() {
        present(code) => { if code != 3 { return 6 } },
        none => { return 6 }
    }
    match status.signal() {
        present(_) => { return 7 },
        none => {}
    }

    var here = std.process.command_text("/bin/pwd")
    here.current_dir(path_from_text("/"))
    let root = try here.output()
    if root.stdout.len() != 2usize || root.stdout[0usize] != 47u8 { return 8 }

    var cat = std.process.command_text("/bin/cat")
    cat.stdin(Stdio.Piped)
    cat.stdout(Stdio.Piped)
    cat.stderr(Stdio.Null)
    var child = try cat.spawn()
    if child.id() <= 0 { return 9 }
    let pipe = child.take_stdin()
    match take pipe {
        present(s) => { var w = s; try w.write_all("ok".as_bytes()) },
        none => { return 10 }
    }
    let collected = child.take_stdout()
    var out = alloc.vec.new<u8>()
    match take collected {
        present(o) => { var r = o; let n = try r.read_to_end(out); if n != 2usize { return 11 } },
        none => { return 11 }
    }
    let finished = try child.wait()
    if finished.code() != present(0) { return 12 }

    let silent = try sh("exit 0").status()
    if !silent.succeeded() || silent.code() != present(0) { return 13 }
    if std.process.id() <= 0 { return 14 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
