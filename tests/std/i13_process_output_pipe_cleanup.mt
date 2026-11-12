import std.ffi.os_str_from_text
import std.io.Error
import std.process.{Command, Stdio}

fn run(): i32 throws Error {
    var command = Command.new(os_str_from_text("/bin/sh"))
    command.arg_text("-c")
    command.arg_text("cat >/dev/null; i=0; while [ \"$i\" -lt 4096 ]; do printf '0123456789abcdef0123456789abcdef'; printf 'fedcba9876543210fedcba9876543210' >&2; i=$((i+1)); done; exit 7")
    command.stdin(Stdio.Piped)
    command.stdout(Stdio.Piped)
    command.stderr(Stdio.Piped)
    let child = try command.spawn()
    let output = try child.wait_with_output()
    if output.status.code() != present(7i32) || output.status.succeeded() { return 1 }
    if output.stdout.len() != 131072usize || output.stderr.len() != 131072usize { return 2 }
    var index = 0usize
    while index < output.stdout.len() {
        if output.stdout[index] != "0123456789abcdef".as_bytes()[index % 16usize] ||
            output.stderr[index] != "fedcba9876543210".as_bytes()[index % 16usize] { return 3 }
        index += 1usize
    }
    let mut_command = Command.new(os_str_from_text("/bin/true"))
    var completed = try mut_command.spawn()
    let status = try completed.wait()
    if !status.succeeded() || !(try completed.wait()).succeeded() { return 4 }
    match try completed.try_wait() {
        present(cached) => { if cached.code() != status.code() { return 5 } },
        none => { return 6 }
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
