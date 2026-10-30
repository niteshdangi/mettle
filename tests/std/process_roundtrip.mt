// Child-process round trip: the program re-runs itself and talks to `cat`
// and `sh` over pipes; failures, signals, environment and cwd are observed.
import std.io.{Error, ErrorKind, Read, Write};
import std.process.{Stdio, Child, ChildStdin};
import std.ffi;
import std.path.path_from_text;

fn has(v: i32?): bool { match v { present(x) => true, none => false } }

fn feed(s: take ChildStdin, data: read [u8]): Unit throws Error {
    var w = s
    try w.write_all(data)
}

fn sh(script: read Text): std.process.Command {
    var c = std.process.command_text("/bin/sh")
    c.arg_text("-c")
    c.arg_text(script)
    c
}

fn child_mode(): i32 {
    // The child echoes its environment and exits with a chosen status.
    match std.env.var_os(ffi.os_str_from_text("MT_GREETING")) {
        present(v) => { std.io.print("greeting="); match v.as_os_str().to_str() { present(t) => std.io.print(t), none => std.io.print("?") }; std.io.print("\n") },
        none => { std.io.print("no greeting\n") }
    }
    std.io.eprint("child-err\n")
    std.process.exit(7)
}

fn cat_roundtrip(): i32 throws Error {
    var c = std.process.command_text("/bin/cat")
    c.stdin(Stdio.Piped)
    c.stdout(Stdio.Piped)
    var child = try c.spawn()
    let input = child.take_stdin()
    match take input { present(s) => { try feed(s, "ping\npong\n".as_bytes()) }, none => { return 1 } }
    var out = alloc.vec.new<u8>()
    let output = child.take_stdout()
    match take output { present(o) => { var r = o; let n = try r.read_to_end(out); if n != 10usize { return 2 } }, none => { return 3 } }
    let st = try child.wait()
    if st.code() != present(0) || !st.succeeded() { return 4 }
    0
}

fn run(): i32 throws Error {
    let a = try cat_roundtrip()
    if a != 0 { return 10 + a }

    // Child failure is an exit status, not an error.
    let st = try sh("exit 3").status()
    if st.code() != present(3) || st.succeeded() || has(st.signal()) { return 20 }

    // Killing a child reports the signal.
    var sleeper = try sh("sleep 30").spawn()
    let early = try sleeper.try_wait()
    match early { present(x) => { return 21 }, none => {} }
    try sleeper.kill()
    let killed = try sleeper.wait()
    if killed.signal() != present(9) || has(killed.code()) { return 22 }

    // Output captures both streams; environment and cwd apply to the child.
    try std.fs.create_dir(path_from_text("work"))
    var c = sh("echo $MT_X; pwd; echo oops 1>&2; exit 2")
    c.env(ffi.os_str_from_text("MT_X"), ffi.os_str_from_text("value"))
    c.current_dir(path_from_text("work"))
    let o = try c.output()
    if o.status.code() != present(2) { return 23 }
    if o.stdout.len() < 6usize || o.stdout[0usize] != 118u8 { return 24 }
    if o.stderr.len() != 5usize { return 25 }
    // Cleared environment hides inherited variables.
    var e = sh("echo \"[$HOME]\"")
    e.env_clear()
    let eo = try e.output()
    if eo.stdout.len() != 3usize { return 26 }

    // Spawning a missing program fails with ENOENT before any child runs.
    let missing = capture std.process.command_text("/nonexistent/prog").spawn()
    match take missing {
        success(ch) => { return 27 },
        failure(err) => { if err.raw_os_error() != present(2) || !err.kind().is(ErrorKind.NotFound) { return 28 } }
    }

    // Re-run this program as the child.
    let args = std.env.args()
    var me = std.process.command(args[0usize].as_os_str())
    me.arg_text("child")
    me.env(ffi.os_str_from_text("MT_GREETING"), ffi.os_str_from_text("hello"))
    let mo = try me.output()
    if mo.status.code() != present(7) { return 30 }
    if mo.stdout.len() != 15usize || mo.stderr.len() != 10usize { return 31 }
    0
}

fn main(): i32 {
    let args = std.env.args()
    if args.len() > 1usize { return child_mode() }
    let r = capture run()
    match take r { success(code) => code, failure(e) => { match e.raw_os_error() { present(c) => 100 + c, none => 99 } } }
}
