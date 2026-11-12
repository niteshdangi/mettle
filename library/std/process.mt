// Child processes and process-wide control. A child that cannot be started
// (missing program, bad directory) fails `spawn` with the OS error reported by
// the child before it ran; a child that runs and fails is a nonzero
// `ExitStatus`, or one ended by a signal, not an `Error`.
import package.alloc.vec
import package.alloc.vec.List
import package.core.outcome
import package.core.option
import package.core.convert.From
import super.env
import super.ffi
import super.ffi.{OsStr, OsString}
import super.io
import super.io.{Error, ErrorKind, Reader, Writer}
import super.path.{Path, PathBuf, PathInput}
import package.core.iter.{ExactSizeIterator, Iterator, OwnedIterable}
import package.core.text.Text
import super.sys
import package.core.clone.Clone
import package.core.borrow.AsRef
import package.core.cmp.{Eq, PartialEq}
import package.core.fmt.{Debug, Formatter}

extern "C" {
    unsafe fn getpid(): i32;
}

// Ends the process immediately with `code` after the C library's exit
// handlers; destructors of live Mettle values do not run.
pub fn exit(code: i32): Never { unsafe { sys.exit(code) } }

// Ends the process abnormally (SIGABRT).
pub fn abort(): Never { unsafe { sys.abort() } }

pub fn id(): i32 { unsafe { getpid() } }

// What a child's standard stream is connected to.
pub enum Stdio {
    Inherit, Piped, Null, Descriptor(sys.OwnedFd), StandardOutput, StandardError
}

fn stdio_config(read config: Stdio): (i32, i32) {
    match config {
        Stdio.Inherit => (0i32, -1i32),
        Stdio.Piped => (1i32, -1i32),
        Stdio.Null => (2i32, -1i32),
        Stdio.Descriptor(descriptor) => (3i32, descriptor.as_raw_fd()),
        Stdio.StandardOutput => (3i32, 1i32),
        Stdio.StandardError => (3i32, 2i32)
    }
}

// How a child ended, from the raw wait status.
pub copy type ExitStatus { raw: i32 }

extend ExitStatus {
    // The exit code when the child exited normally.
    pub fn code(): i32? { if (self.raw & 127) == 0 { present((self.raw >> 8) & 255) } else { none } }
    // The terminating signal when a signal ended the child.
    pub fn signal(): i32? { if (self.raw & 127) != 0 && (self.raw & 127) != 127 { present(self.raw & 127) } else { none } }
    pub fn succeeded(): bool { self.raw == 0 }
}

extend ExitStatus implements PartialEq {
    fn eq(read other: ExitStatus): bool { self.raw == other.raw }
}
extend ExitStatus implements Eq {}
extend ExitStatus implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("ExitStatus { raw: ")
        try i32.(package.core.fmt.Display).fmt(self.raw, mut f)
        try f.write_str(" }")
    }
}
extend ExitStatus implements package.core.default.Default {
    static fn default(): ExitStatus { ExitStatus(0) }
}

// Linux signal names, as the reference ExitStatus display prints them.
fn signal_name(signal: i32): read Text from static {
    match signal {
        1 => " (SIGHUP)", 2 => " (SIGINT)", 3 => " (SIGQUIT)", 4 => " (SIGILL)",
        5 => " (SIGTRAP)", 6 => " (SIGABRT)", 7 => " (SIGBUS)", 8 => " (SIGFPE)",
        9 => " (SIGKILL)", 10 => " (SIGUSR1)", 11 => " (SIGSEGV)", 12 => " (SIGUSR2)",
        13 => " (SIGPIPE)", 14 => " (SIGALRM)", 15 => " (SIGTERM)", 16 => " (SIGSTKFLT)",
        17 => " (SIGCHLD)", 18 => " (SIGCONT)", 19 => " (SIGSTOP)", 20 => " (SIGTSTP)",
        21 => " (SIGTTIN)", 22 => " (SIGTTOU)", 23 => " (SIGURG)", 24 => " (SIGXCPU)",
        25 => " (SIGXFSZ)", 26 => " (SIGVTALRM)", 27 => " (SIGPROF)", 28 => " (SIGWINCH)",
        29 => " (SIGIO)", 30 => " (SIGPWR)", 31 => " (SIGSYS)",
        _ => ""
    }
}

// "exit status: N" for a normal exit, "signal: N (NAME)" (and " (core dumped)")
// for a signal, matching the reference Unix display.
extend ExitStatus implements package.core.fmt.Display {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        match self.code() {
            present(code) => {
                try f.write_str("exit status: ")
                return try i32.(package.core.fmt.Display).fmt(code, mut f)
            },
            none => {}
        }
        match self.signal() {
            present(signal) => {
                try f.write_str("signal: ")
                try i32.(package.core.fmt.Display).fmt(signal, mut f)
                try f.write_str(signal_name(signal))
                if (self.raw & 128) != 0 { try f.write_str(" (core dumped)") }
            },
            none => {
                try f.write_str("unrecognised wait status: ")
                try i32.(package.core.fmt.Display).fmt(self.raw, mut f)
            }
        }
    }
}

// Write end of a child's standard input; dropping it closes the stream, which
// is how a child reading to the end of input learns the input is complete.
pub type ChildStdin {
    descriptor: sys.OwnedFd
}

extend ChildStdin implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error { try io.write_fd(self.descriptor.as_raw_fd(), buf) }
    mut fn flush(): Unit throws Error {}
}

pub type ChildStdout {
    descriptor: sys.OwnedFd
}

extend ChildStdout implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try io.read_fd(self.descriptor.as_raw_fd(), buf) }
}

pub type ChildStderr {
    descriptor: sys.OwnedFd
}

extend ChildStderr implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try io.read_fd(self.descriptor.as_raw_fd(), buf) }
}

extend sys.OwnedFd implements From<ChildStdin> {
    static fn from(take value: ChildStdin): sys.OwnedFd { value.descriptor }
}
extend sys.OwnedFd implements From<ChildStdout> {
    static fn from(take value: ChildStdout): sys.OwnedFd { value.descriptor }
}
extend sys.OwnedFd implements From<ChildStderr> {
    static fn from(take value: ChildStderr): sys.OwnedFd { value.descriptor }
}

// A running or finished child. Dropping it neither waits for nor kills the
// process; its pipe ends close.
pub type Child {
    pid: i32
    pub stdin: ChildStdin?
    pub stdout: ChildStdout?
    pub stderr: ChildStderr?
    status: ExitStatus?
}

// Captured result of `Command.output`.
pub type Output { pub status: ExitStatus; pub stdout: List<u8>; pub stderr: List<u8> }

fn wait_status(pid: i32, options: i32): ExitStatus? throws Error {
    var status = 0
    while true {
        let r = unsafe { sys.waitpid(pid, core.ptr.from_mut(status), options) }
        if r == pid { return present(ExitStatus(status)) }
        if r == 0 { return none }
        let e = io.last_os_error()
        if !e.kind().is(ErrorKind.Interrupted) { throw e }
    }
    none
}

extend Child {
    pub fn id(): i32 { self.pid }

    // Hands over the pipe to the child's input; none unless it was `Piped`
    // and not already taken.
    pub mut fn take_stdin(): ChildStdin? { self.stdin.`take`() }
    pub mut fn take_stdout(): ChildStdout? { self.stdout.`take`() }
    pub mut fn take_stderr(): ChildStderr? { self.stderr.`take`() }

    // Waits for the child to end, closing its input pipe first so it cannot
    // block forever waiting for input this process still holds open.
    pub mut fn wait(): ExitStatus throws Error {
        core.mem.drop(self.stdin.`take`())
        match self.status { present(s) => { return s }, none => {} }
        match try wait_status(self.pid, 0) {
            present(s) => { self.status = present(s); s },
            none => { throw io.from_kind(ErrorKind.Other) }
        }
    }

    // The status if the child has already ended, without blocking.
    pub mut fn try_wait(): ExitStatus? throws Error {
        match self.status { present(s) => { return present(s) }, none => {} }
        let r = try wait_status(self.pid, 1)
        match r {
            present(s) => { self.status = present(s); present(s) },
            none => none
        }
    }

    // Sends SIGKILL; a child that already ended is not an error.
    pub mut fn kill(): Unit throws Error {
        if self.status.is_present() { return }
        if unsafe { sys.kill(self.pid, 9) } != 0 {
            let e = io.last_os_error()
            if e.raw_os_error() != present(3) { throw e }
        }
    }

    pub take fn wait_with_output(): Output throws Error {
        var child = self
        try collect_output(child)
    }
}

type EnvChange { name: OsString; value: OsString; remove: bool }

pub type CommandArgs<region r> { values: read [OsString] from r; index: usize }
extend<region r> CommandArgs<region r> implements Iterator {
    type Item = read OsStr from r
    fn size_hint(): (usize, usize?) {
        let remaining = self.values.len() - self.index
        (remaining, present(remaining))
    }
    mut fn next(): (read OsStr from r)? {
        if self.index == self.values.len() { return none }
        let value = self.values[self.index].as_os_str()
        self.index += 1usize
        present(value)
    }
}
extend<region r> CommandArgs<region r> implements ExactSizeIterator {}
extend<region r> CommandArgs<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("CommandArgs(")
        try fmt_os_strings(self.values.split_at(self.index).1, mut f)
        try f.write_char(')')
    }
}

pub type CommandEnvs<region r> { values: read [EnvChange] from r; index: usize }
extend<region r> CommandEnvs<region r> implements Iterator {
    type Item = (read OsStr from r, (read OsStr from r)?)
    fn size_hint(): (usize, usize?) {
        let remaining = self.values.len() - self.index
        (remaining, present(remaining))
    }
    mut fn next(): (read OsStr from r, (read OsStr from r)?)? {
        if self.index == self.values.len() { return none }
        let current = read self.values[self.index]
        self.index += 1usize
        let value = if current.remove { none } else { present(current.value.as_os_str()) }
        present((current.name.as_os_str(), value))
    }
}
extend<region r> CommandEnvs<region r> implements ExactSizeIterator {}
extend<region r> CommandEnvs<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("CommandEnvs([")
        var index = self.index
        while index < self.values.len() {
            if index != self.index { try f.write_str(", ") }
            let entry = read self.values[index]
            try f.write_char('(')
            try fmt_os_string(entry.name.as_os_str(), mut f)
            try f.write_str(", ")
            if entry.remove {
                try f.write_str("none")
            } else {
                try f.write_str("present(")
                try fmt_os_string(entry.value.as_os_str(), mut f)
                try f.write_char(')')
            }
            try f.write_char(')')
            index += 1usize
        }
        try f.write_str("])")
    }
}

// A command under construction: program, arguments, environment changes,
// working directory and standard streams.
pub type Command {
    program: OsString
    args: List<OsString>
    changes: List<EnvChange>
    clear_env: bool
    cwd: PathBuf
    has_cwd: bool
    stdin: Stdio
    stdout: Stdio
    stderr: Stdio
    stdio_set: u8
}

pub fn command(read program: OsStr): Command {
    Command(program.to_os_string(), vec.new<OsString>(), vec.new<EnvChange>(), false,
            super.path.new_path_buf(), false, Stdio.Inherit, Stdio.Inherit, Stdio.Inherit, 0u8)
}

pub fn command_text(read program: Text): Command { command(ffi.os_str_from_text(program)) }

extend Command {
    pub static fn new<S: AsRef<OsStr> + unsized>(read program: S): Command {
        command(S.(AsRef<OsStr>).as_ref(program))
    }

    pub mut fn arg(read a: OsStr): Unit { self.args.push(a.to_os_string()) }
    pub mut fn arg_text(read a: Text): Unit { self.args.push(ffi.os_string_from_text(a)) }
    pub fn args<region r, I: OwnedIterable<Item = S>, S: AsRef<OsStr>>(
        receiver mut self: Command from r, take values: I
    ): mut Command from r {
        var entries = values.into_iter()
        while true {
            match take entries.next() {
                present(value) => self.args.push(S.(AsRef<OsStr>).as_ref(value).to_os_string()),
                none => { break }
            }
        }
        mut self
    }
    pub fn get_program<region r>(receiver read self: Command from r): read OsStr from r {
        self.program.as_os_str()
    }
    pub fn get_args<region r>(receiver read self: Command from r): CommandArgs<region r> {
        CommandArgs(self.args.as_slice(), 0usize)
    }
    pub fn get_envs<region r>(receiver read self: Command from r): CommandEnvs<region r> {
        CommandEnvs(self.changes.as_slice(), 0usize)
    }
    pub fn get_current_dir<region r>(receiver read self: Command from r): (read Path from r)? {
        if self.has_cwd { present(self.cwd.as_path()) } else { none }
    }
    mut fn change_env(take change: EnvChange): Unit {
        var index = 0usize
        while index < self.changes.len() {
            if self.changes[index].name.same(change.name) {
                let obsolete = self.changes.remove(index)
                break
            }
            index += 1usize
        }
        self.changes.push(change)
    }
    // Sets `name` for the child only.
    pub mut fn env(read name: OsStr, read value: OsStr): Unit {
        self.change_env(EnvChange(name.to_os_string(), value.to_os_string(), false))
    }
    pub fn envs<region r, I: OwnedIterable<Item = (K, V)>, K: AsRef<OsStr>, V: AsRef<OsStr>>(
        receiver mut self: Command from r, take values: I
    ): mut Command from r {
        var entries = values.into_iter()
        while true {
            match take entries.next() {
                present((key, value)) => {
                    self.env(K.(AsRef<OsStr>).as_ref(key), V.(AsRef<OsStr>).as_ref(value))
                },
                none => { break }
            }
        }
        mut self
    }
    // Removes `name` from the child's environment.
    pub mut fn env_remove(read name: OsStr): Unit {
        if self.clear_env {
            var index = 0usize
            while index < self.changes.len() {
                if self.changes[index].name.as_os_str().same(name) {
                    let removed = self.changes.remove(index)
                    return
                }
                index += 1usize
            }
            return
        }
        self.change_env(EnvChange(name.to_os_string(), ffi.new_os_string(), true))
    }
    // Starts the child with an empty environment (plus later `env` calls).
    pub fn env_clear<region r>(receiver mut self: Command from r): mut Command from r {
        self.clear_env = true
        self.changes.clear()
        mut self
    }
    pub mut fn current_dir(read input: PathInput): Unit {
        self.cwd = input.as_path().to_path_buf()
        self.has_cwd = true
    }
    pub fn stdin<region r>(receiver mut self: Command from r, take config: Stdio): mut Command from r {
        self.stdin = config
        self.stdio_set |= 1u8
        mut self
    }
    pub fn stdout<region r>(receiver mut self: Command from r, take config: Stdio): mut Command from r {
        self.stdout = config
        self.stdio_set |= 2u8
        mut self
    }
    pub fn stderr<region r>(receiver mut self: Command from r, take config: Stdio): mut Command from r {
        self.stderr = config
        self.stdio_set |= 4u8
        mut self
    }

    // The child's environment as NUL-terminated `name=value` strings.
    fn environment(): List<List<u8>> throws Error {
        var entries = if self.clear_env { vec.new<env.EnvVar>() } else { env.vars() }
        var k = 0usize
        while k < self.changes.len() {
            let name = self.changes[k].name.as_bytes()
            if name.len() == 0usize { throw io.from_kind(ErrorKind.InvalidInput) }
            var byte = 0usize
            while byte < name.len() {
                if name[byte] == 0u8 || name[byte] == 61u8 {
                    throw io.from_kind(ErrorKind.InvalidInput)
                }
                byte += 1usize
            }
            var m = 0usize
            while m < entries.len() {
                if entries[m].name.same(self.changes[k].name) { let gone = entries.remove(m) } else { m += 1usize }
            }
            if !self.changes[k].remove {
                entries.push(env.EnvVar(self.changes[k].name.to_os_string(), self.changes[k].value.to_os_string()))
            }
            k += 1usize
        }
        var out = vec.new<List<u8>>()
        var n = 0usize
        while n < entries.len() {
            var line = vec.new<u8>()
            line.extend_from_slice(entries[n].name.as_bytes())
            line.push(61u8)
            line.extend_from_slice(entries[n].value.as_bytes())
            out.push(try ffi.cstring(line.as_slice()))
            n += 1usize
        }
        out
    }

    // Starts the child. Piped streams are reachable through the `Child`.
    pub fn spawn(): Child throws Error {
        try self.spawn_with_stdio(stdio_config(read self.stdin),
            stdio_config(read self.stdout), stdio_config(read self.stderr))
    }

    fn spawn_with_stdio(stdin: (i32, i32), stdout: (i32, i32), stderr: (i32, i32)): Child throws Error {
        var strings = vec.new<List<u8>>()
        strings.push(try ffi.cstring(self.program.as_bytes()))
        var i = 0usize
        while i < self.args.len() {
            strings.push(try ffi.cstring(self.args[i].as_bytes()))
            i += 1usize
        }
        var argv = vec.new<ptr<read u8>>()
        var j = 0usize
        while j < strings.len() {
            argv.push(strings[j].as_ptr())
            j += 1usize
        }
        argv.push(core.ptr.null<u8>())
        let use_env = self.clear_env || self.changes.len() > 0usize
        let env_pairs = if use_env { try self.environment() } else { vec.new<List<u8>>() }
        var envp = vec.new<ptr<read u8>>()
        if use_env {
            var e = 0usize
            while e < env_pairs.len() {
                envp.push(env_pairs[e].as_ptr())
                e += 1usize
            }
            envp.push(core.ptr.null<u8>())
        }
        var cwd_c = vec.new<u8>()
        if self.has_cwd { cwd_c = try ffi.cstring(self.cwd.as_bytes()) }
        var modes = [stdin.0, stdout.0, stderr.0]
        var sources = [stdin.1, stdout.1, stderr.1]
        var fds = [-1, -1, -1]
        let cwd_ptr = if self.has_cwd { cwd_c.as_ptr() } else { core.ptr.null<u8>() }
        let envp_ptr = if use_env { envp.as_ptr() } else { core.ptr.null<ptr<read u8>>() }
        let pid = unsafe {
            sys.mettle_rt_spawn_with_sources(strings[0usize].as_ptr(), argv.as_ptr(), envp_ptr, cwd_ptr,
                                 core.ptr.from_mut(modes).cast<i32>().cast_const(),
                                 core.ptr.from_mut(sources).cast<i32>().cast_const(),
                                 core.ptr.from_mut(fds).cast<i32>())
        }
        if pid < 0 { throw io.last_os_error() }
        // Successful spawn transfers only the nonnegative parent pipe ends.
        let input = if fds[0usize] < 0 { none } else {
            present(ChildStdin(unsafe { sys.OwnedFd.from_raw_fd(fds[0usize]) }))
        }
        let output = if fds[1usize] < 0 { none } else {
            present(ChildStdout(unsafe { sys.OwnedFd.from_raw_fd(fds[1usize]) }))
        }
        let error = if fds[2usize] < 0 { none } else {
            present(ChildStderr(unsafe { sys.OwnedFd.from_raw_fd(fds[2usize]) }))
        }
        Child(pid, input, output, error, none)
    }

    // Runs to completion with inherited streams and returns how it ended.
    pub fn status(): ExitStatus throws Error {
        var child = try self.spawn()
        try child.wait()
    }

    // Capture/null defaults apply only to streams not explicitly configured.
    pub mut fn output(): Output throws Error {
        let stdin = if (self.stdio_set & 1u8) == 0u8 { (2i32, -1i32) } else { stdio_config(read self.stdin) }
        let stdout = if (self.stdio_set & 2u8) == 0u8 { (1i32, -1i32) } else { stdio_config(read self.stdout) }
        let stderr = if (self.stdio_set & 4u8) == 0u8 { (1i32, -1i32) } else { stdio_config(read self.stderr) }
        let child = try self.spawn_with_stdio(stdin, stdout, stderr)
        try child.wait_with_output()
    }
}

fn collect_output(mut child: Child): Output throws Error {
    core.mem.drop(child.take_stdin())
    var stdout = child.take_stdout()
    var stderr = child.take_stderr()
    var stdout_fd = match stdout.as_ref() {
        present(pipe) => pipe.descriptor.as_raw_fd(),
        none => -1i32
    }
    var stderr_fd = match stderr.as_ref() {
        present(pipe) => pipe.descriptor.as_raw_fd(),
        none => -1i32
    }
    var out = vec.new<u8>()
    var err = vec.new<u8>()
    var chunk = [0u8; 4096]
    while stdout_fd >= 0 || stderr_fd >= 0 {
        let ready = unsafe { sys.mettle_rt_poll_pair(stdout_fd, stderr_fd) }
        if ready < 0 { throw io.last_os_error() }
        if (ready & 1) != 0 {
            let n = try io.read_fd(stdout_fd, chunk)
            if n == 0usize { core.mem.drop(stdout.`take`()); stdout_fd = -1i32 }
            else { out.extend_from_slice(chunk.split_at(n).0) }
        }
        if (ready & 2) != 0 {
            let n = try io.read_fd(stderr_fd, chunk)
            if n == 0usize { core.mem.drop(stderr.`take`()); stderr_fd = -1i32 }
            else { err.extend_from_slice(chunk.split_at(n).0) }
        }
    }
    Output(try child.wait(), out, err)
}

extend Output implements PartialEq {
    fn eq(read other: Output): bool {
        self.status == other.status &&
            self.stdout.as_slice() == other.stdout.as_slice() &&
            self.stderr.as_slice() == other.stderr.as_slice()
    }
}
extend Output implements Eq {}
extend Output implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("Output { status: ")
        try self.status.fmt(mut f)
        try f.write_str(", stdout: ")
        try fmt_bytes(self.stdout.as_slice(), mut f)
        try f.write_str(", stderr: ")
        try fmt_bytes(self.stderr.as_slice(), mut f)
        try f.write_str(" }")
    }
}

fn fmt_bytes(read bytes: [u8], mut f: Formatter): Unit throws package.core.fmt.Error {
    try f.write_char('[')
    var i = 0usize
    while i < bytes.len() {
        if i != 0usize { try f.write_str(", ") }
        try u8.(package.core.fmt.Debug).fmt(bytes[i], mut f)
        i += 1usize
    }
    try f.write_char(']')
}

extend Stdio {
    pub static fn inherit(): Stdio { Stdio.Inherit }
}
extend Stdio implements From<sys.OwnedFd> {
    static fn from(take value: sys.OwnedFd): Stdio { Stdio.Descriptor(value) }
}
extend Stdio implements From<io.Stdout> {
    static fn from(take value: io.Stdout): Stdio { Stdio.StandardOutput }
}
extend Stdio implements From<io.Stderr> {
    static fn from(take value: io.Stderr): Stdio { Stdio.StandardError }
}
extend Stdio implements From<super.fs.File> {
    static fn from(take value: super.fs.File): Stdio {
        Stdio.Descriptor(sys.OwnedFd.(From<super.fs.File>).from(value))
    }
}
extend Stdio implements From<io.PipeReader> {
    static fn from(take value: io.PipeReader): Stdio {
        Stdio.Descriptor(sys.OwnedFd.(From<io.PipeReader>).from(value))
    }
}
extend Stdio implements From<io.PipeWriter> {
    static fn from(take value: io.PipeWriter): Stdio {
        Stdio.Descriptor(sys.OwnedFd.(From<io.PipeWriter>).from(value))
    }
}
extend Stdio implements From<ChildStdin> {
    static fn from(take value: ChildStdin): Stdio {
        Stdio.Descriptor(sys.OwnedFd.(From<ChildStdin>).from(value))
    }
}
extend Stdio implements From<ChildStdout> {
    static fn from(take value: ChildStdout): Stdio {
        Stdio.Descriptor(sys.OwnedFd.(From<ChildStdout>).from(value))
    }
}
extend Stdio implements From<ChildStderr> {
    static fn from(take value: ChildStderr): Stdio {
        Stdio.Descriptor(sys.OwnedFd.(From<ChildStderr>).from(value))
    }
}
extend Stdio implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        match self {
            Stdio.Inherit => try f.write_str("Inherit"),
            Stdio.Piped => try f.write_str("Piped"),
            Stdio.Null => try f.write_str("Null"),
            Stdio.Descriptor(descriptor) => {
                try f.write_str("Descriptor(")
                try i32.(Debug).fmt(descriptor.as_raw_fd(), mut f)
                try f.write_char(')')
            },
            Stdio.StandardOutput => try f.write_str("StandardOutput"),
            Stdio.StandardError => try f.write_str("StandardError")
        }
    }
}

extend Child implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("Child { id: ")
        try i32.(package.core.fmt.Display).fmt(self.pid, mut f)
        try f.write_str(" }")
    }
}

extend Command implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("Command { program: ")
        try fmt_os_string(self.program.as_os_str(), mut f)
        try f.write_str(", args: ")
        try fmt_os_strings(self.args.as_slice(), mut f)
        try f.write_str(" }")
    }
}

fn fmt_os_string(read value: OsStr, mut f: Formatter): Unit throws package.core.fmt.Error {
    match value.to_str() {
        present(text) => try Text.(Debug).fmt(text, mut f),
        none => {
            try f.write_str("OsStr(")
            try fmt_bytes(value.as_bytes(), mut f)
            try f.write_char(')')
        }
    }
}

fn fmt_os_strings(read values: [OsString], mut f: Formatter): Unit throws package.core.fmt.Error {
    try f.write_char('[')
    var i = 0usize
    while i < values.len() {
        if i != 0usize { try f.write_str(", ") }
        try fmt_os_string(values[i].as_os_str(), mut f)
        i += 1usize
    }
    try f.write_char(']')
}

// Value types duplicate by copy; owners clone their buffers.
extend ExitStatus implements Clone {
    fn clone(): ExitStatus { self }
}
extend Output implements Clone {
    fn clone(): Output { Output(self.status, self.stdout.clone(), self.stderr.clone()) }
}
