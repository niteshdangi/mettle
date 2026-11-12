// Command builder and child results: arguments, environment edits, working directory,
// captured output, exit statuses and piped stdin.
import std.io.{Error, Reader, Writer}
import std.process.{Stdio}
import std.ffi
import std.path.path_from_text
import core.iter.Iterator
import alloc.string.String

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

    var configured = std.process.command_text("/bin/sh")
    {
        var args = configured.get_args()
        var entries = configured.get_envs()
        if args.next().is_present() || entries.next().is_present() ||
           configured.get_current_dir().is_present() { return 15 }
    }
    configured.arg_text("-c")
    configured.arg_text("printf '%s|%s|%s|%s|%s' \"$1\" \"$2\" \"${MT_OLD-unset}\" \"${MT_NEW-unset}\" \"${MT_REMOVED-unset}\"")
    configured.arg_text("sh")
    {
        var arguments = alloc.vec.new<String>()
        arguments.push(String("two words"))
        arguments.push(String(""))
        configured.args<alloc.vec.List<String>, String>(arguments)
        let directory = String("/")
        configured.current_dir(path_from_text(directory.as_text()))
    }
    {
        var args = configured.get_args()
        if args.next().is_none() || args.next().is_none() || args.next().is_none() { return 16 }
        match args.next() {
            present(value) => { if !value.same(ffi.os_str_from_text("two words")) { return 17 } },
            none => { return 17 }
        }
        match args.next() {
            present(value) => { if !value.is_empty() { return 18 } },
            none => { return 18 }
        }
        if args.next().is_present() { return 19 }
    }
    match configured.get_current_dir() {
        present(path) => { if !path.same(path_from_text("/")) { return 20 } },
        none => { return 20 }
    }
    configured.current_dir(path_from_text("."))
    match configured.get_current_dir() {
        present(path) => { if !path.same(path_from_text(".")) { return 21 } },
        none => { return 21 }
    }
    configured.env(ffi.os_str_from_text("MT_OLD"), ffi.os_str_from_text("discarded"))
    configured.env_clear()
    {
        var entries = configured.get_envs()
        if entries.next().is_present() { return 22 }
    }
    var environment = alloc.vec.new<(String, String)>()
    environment.push((String("MT_NEW"), String("old")))
    environment.push((String("MT_NEW"), String("final")))
    environment.push((String("MT_REMOVED"), String("discarded")))
    configured.envs<alloc.vec.List<(String, String)>, String, String>(environment)
    configured.env_remove(ffi.os_str_from_text("MT_REMOVED"))
    {
        var entries = configured.get_envs()
        var found_new = false
        while true {
            match entries.next() {
                present((name, value)) => {
                    if name.same(ffi.os_str_from_text("MT_NEW")) {
                        match value {
                            present(text) => { if !text.same(ffi.os_str_from_text("final")) { return 24 } },
                            none => { return 24 }
                        }
                        found_new = true
                    } else { return 23 }
                },
                none => { break }
            }
        }
        if !found_new { return 25 }
    }
    let built = try configured.output()
    if !built.status.succeeded() ||
       !ffi.os_str(built.stdout.as_slice()).same(ffi.os_str_from_text("two words||unset|final|unset")) {
        return 26
    }
    configured.env(ffi.os_str_from_text("MT_REMOVED"), ffi.os_str_from_text("restored"))
    {
        var entries = configured.get_envs()
        var restored = false
        while true {
            match entries.next() {
                present((name, value)) => {
                    if name.same(ffi.os_str_from_text("MT_REMOVED")) {
                        match value {
                            present(text) => { if !text.same(ffi.os_str_from_text("restored")) { return 27 } },
                            none => { return 27 }
                        }
                        restored = true
                    }
                },
                none => { break }
            }
        }
        if !restored { return 27 }
    }
    let replaced = try configured.output()
    if !replaced.status.succeeded() ||
       !ffi.os_str(replaced.stdout.as_slice()).same(ffi.os_str_from_text("two words||unset|final|restored")) {
        return 32
    }
    configured.env_clear()
    {
        var entries = configured.get_envs()
        if entries.next().is_present() { return 28 }
    }
    let cleared_again = try configured.output()
    if !cleared_again.status.succeeded() ||
       !ffi.os_str(cleared_again.stdout.as_slice()).same(ffi.os_str_from_text("two words||unset|unset|unset")) {
        return 29
    }
    var invalid_removal = sh("exit 0")
    invalid_removal.env_clear()
    invalid_removal.env_remove(ffi.os_str_from_text("BAD=NAME"))
    {
        var entries = invalid_removal.get_envs()
        if entries.next().is_present() { return 30 }
    }
    if !(try invalid_removal.status()).succeeded() { return 31 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
