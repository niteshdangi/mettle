import core.convert.From
import core.option
import std.ffi
import std.fs.File
import std.io
import std.io.{Error, ErrorKind, PipeReader, PipeWriter, Reader, Writer}
import std.path.path_from_text
import std.panic.{catch_panic, CatchResult}
import std.process.{ChildStderr, ChildStdin, ChildStdout, Command, Stdio}
import std.sys.OwnedFd

fn shell(read script: Text): Command {
    var command = Command.new("/bin/sh")
    command.arg_text("-c")
    command.arg_text(script)
    command
}

fn pipeline(kind: u8): i32 throws Error {
    var producer = shell(if kind == 1u8 { "printf pipe >&2" } else { "printf pipe" })
    producer.stdout(if kind == 1u8 { Stdio.Null } else { Stdio.Piped })
    producer.stderr(if kind == 1u8 { Stdio.Piped } else { Stdio.Null })
    var child = try producer.spawn()
    let input = if kind == 1u8 {
        let pipe = match take child.take_stderr() {
            present(pipe) => pipe,
            none => { return 1 }
        }
        Stdio.(From<ChildStderr>).from(pipe)
    } else {
        let pipe = match take child.take_stdout() {
            present(pipe) => pipe,
            none => { return 2 }
        }
        if kind == 0u8 {
            Stdio.(From<ChildStdout>).from(pipe)
        } else {
            let descriptor = OwnedFd.(From<ChildStdout>).from(pipe)
            if kind == 2u8 {
                Stdio.(From<OwnedFd>).from(descriptor)
            } else {
                let reader = PipeReader.(From<OwnedFd>).from(descriptor)
                Stdio.(From<PipeReader>).from(reader)
            }
        }
    }
    var consumer = Command.new("/bin/cat")
    consumer.stdin(input)
    let output = try consumer.output()
    if !output.status.succeeded() ||
        !ffi.os_str(output.stdout.as_slice()).same(ffi.os_str_from_text("pipe")) { return 3 }
    if !(try child.wait()).succeeded() { return 4 }
    0
}

fn forward_to_input(pipe_writer: bool): i32 throws Error {
    var sink = Command.new("/bin/cat")
    sink.stdin(Stdio.Piped).stdout(Stdio.Piped)
    var child = try sink.spawn()
    let input = match take child.stdin.`take`() {
        present(input) => input,
        none => { return 5 }
    }
    let output = if pipe_writer {
        let descriptor = OwnedFd.(From<ChildStdin>).from(input)
        let writer = PipeWriter.(From<OwnedFd>).from(descriptor)
        Stdio.(From<PipeWriter>).from(writer)
    } else {
        Stdio.(From<ChildStdin>).from(input)
    }
    {
        var source = shell("printf send")
        source.stdout(output)
        if !(try source.status()).succeeded() || !(try source.status()).succeeded() { return 6 }
    }
    let collected = try child.wait_with_output()
    if !collected.status.succeeded() ||
        !ffi.os_str(collected.stdout.as_slice()).same(ffi.os_str_from_text("sendsend")) { return 7 }
    0
}

fn file_configuration(): i32 throws Error {
    let path = path_from_text("i13-process-stdio-transfer")
    let file = try File.create_new(path)
    let fd = file.as_raw_fd()
    {
        var source = shell("printf file")
        source.stdout(Stdio.(From<File>).from(file))
        if !(try source.status()).succeeded() || !(try source.status()).succeeded() { return 8 }
        source.current_dir(path_from_text("i13-process-directory-that-does-not-exist"))
        match take capture source.spawn() {
            success(_) => { return 9 },
            failure(error) => { if !error.kind().is(ErrorKind.NotFound) { return 10 } }
        }
        source.current_dir(path_from_text("."))
        if !(try source.status()).succeeded() { return 11 }
        source.stdout(Stdio.Null)
        let written = unsafe { std.sys.write(fd, core.slice.data("!".as_bytes()), 1usize) }
        if written != -1 || io.last_os_error().raw_os_error() != present(9i32) { return 12 }
    }
    let bytes = try std.fs.read(path)
    try std.fs.remove_file(path)
    if !ffi.os_str(bytes.as_slice()).same(ffi.os_str_from_text("filefilefile")) { return 13 }
    let unwind_file = try File.create_new(path)
    let unwind_fd = unwind_file.as_raw_fd()
    let configuration = Stdio.(From<File>).from(unwind_file)
    match take catch_panic(take fn(): Unit {
        let _owned = configuration
        core.panic.panic("stdio cleanup")
    }) {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 22 }
    }
    let written = unsafe { std.sys.write(unwind_fd, core.slice.data("!".as_bytes()), 1usize) }
    let closed = written == -1 && io.last_os_error().raw_os_error() == present(9i32)
    try std.fs.remove_file(path)
    if !closed { return 23 }
    0
}

fn borrowed_fields(): i32 throws Error {
    var command = Command.new("/bin/cat")
    command.stdin(Stdio.Piped).stdout(Stdio.Piped).stderr(Stdio.Piped)
    var child = try command.spawn()
    match mut child.stdin {
        present(input) => { try input.write_all("borrow".as_bytes()) },
        none => { return 14 }
    }
    if child.stdin.is_none() || child.stdout.is_none() || child.stderr.is_none() { return 15 }
    core.mem.drop(child.stdin.`take`())
    var buffer = [0u8; 6]
    match mut child.stdout {
        present(output) => { try output.read_exact(mut buffer) },
        none => { return 16 }
    }
    if !ffi.os_str(read buffer).same(ffi.os_str_from_text("borrow")) { return 17 }
    let remaining = try child.wait_with_output()
    if !remaining.status.succeeded() || !remaining.stdout.is_empty() ||
        !remaining.stderr.is_empty() { return 18 }
    0
}

fn standard_sources(): i32 throws Error {
    var child = shell("printf o; printf e >&2")
    child.stdout(Stdio.(From<io.Stderr>).from(io.stderr()))
    child.stderr(Stdio.(From<io.Stdout>).from(io.stdout()))
    if !(try child.status()).succeeded() { return 19 }
    var output = io.stdout()
    try output.write_all("S".as_bytes())
    try output.flush()
    var error = io.stderr()
    try error.write_all("E".as_bytes())
    try error.flush()
    0
}

fn invalid_environment(read key: ffi.OsStr, read value: ffi.OsStr): bool {
    var command = shell("exit 99")
    command.envs([(key.to_os_string(), value.to_os_string())])
    match take capture command.spawn() {
        success(_) => false,
        failure(error) => error.kind().is(ErrorKind.InvalidInput)
    }
}

fn run(): i32 throws Error {
    var kind = 0u8
    while kind < 4u8 {
        let result = try pipeline(kind)
        if result != 0 { return result }
        kind += 1u8
    }
    let direct = try forward_to_input(false)
    if direct != 0 { return direct }
    let wrapped = try forward_to_input(true)
    if wrapped != 0 { return wrapped }
    let file = try file_configuration()
    if file != 0 { return file }
    let borrowed = try borrowed_fields()
    if borrowed != 0 { return borrowed }
    let args = std.env.args()
    var reentry = Command.new(args[0usize].as_os_str())
    reentry.arg_text("standard-sources")
    let standard = try reentry.output()
    if !standard.status.succeeded() ||
        !ffi.os_str(standard.stdout.as_slice()).same(ffi.os_str_from_text("eS")) ||
        !ffi.os_str(standard.stderr.as_slice()).same(ffi.os_str_from_text("oE")) { return 20 }
    let nul_key = [b'K', 0u8]
    let nul_value = [b'V', 0u8]
    if !invalid_environment(ffi.os_str_from_text(""), ffi.os_str_from_text("value")) ||
        !invalid_environment(ffi.os_str_from_text("A=B"), ffi.os_str_from_text("value")) ||
        !invalid_environment(ffi.os_str(read nul_key), ffi.os_str_from_text("value")) ||
        !invalid_environment(ffi.os_str_from_text("KEY"), ffi.os_str(read nul_value)) { return 21 }
    0
}

fn main(): i32 {
    let args = std.env.args()
    let result = if args.len() > 1usize { capture standard_sources() } else { capture run() }
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
