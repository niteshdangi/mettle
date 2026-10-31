// Child processes and process-wide control. A child that cannot be started
// (missing program, bad directory) fails `spawn` with the OS error reported by
// the child before it ran; a child that runs and fails is a nonzero
// `ExitStatus`, or one ended by a signal, not an `Error`.
import package.alloc.vec
import package.alloc.vec.List
import package.core.outcome
import super.env
import super.ffi
import super.ffi.{OsStr, OsString}
import super.io
import super.io.{Error, ErrorKind, Reader, Writer}
import super.path.{PathBuf, PathInput}
import package.core.text.Text
import super.sys

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
pub copy enum Stdio { Inherit, Piped, Null }

fn stdio_code(s: Stdio): i32 { match s { Stdio.Inherit => 0, Stdio.Piped => 1, Stdio.Null => 2 } }

// How a child ended, from the raw wait status.
pub copy type ExitStatus { raw: i32 }

extend ExitStatus {
    // The exit code when the child exited normally.
    pub fn code(): i32? { if (self.raw & 127) == 0 { present((self.raw >> 8) & 255) } else { none } }
    // The terminating signal when a signal ended the child.
    pub fn signal(): i32? { if (self.raw & 127) != 0 && (self.raw & 127) != 127 { present(self.raw & 127) } else { none } }
    pub fn succeeded(): bool { self.raw == 0 }
    pub fn success(): bool { self.succeeded() }
}

extend Stdio {
    pub static fn inherit(): Stdio { Stdio.Inherit }
    pub static fn piped(): Stdio { Stdio.Piped }
    pub static fn `null`(): Stdio { Stdio.Null }
}

// Write end of a child's standard input; dropping it closes the stream, which
// is how a child reading to the end of input learns the input is complete.
pub type ChildStdin {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

extend ChildStdin implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error { try io.write_fd(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

// Read end of a child's standard output or error.
pub type ChildOutput {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

extend ChildOutput implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error { try io.read_fd(self.fd, buf) }
}

// A running or finished child. Dropping it neither waits for nor kills the
// process; its pipe ends close.
pub type Child {
    pid: i32
    stdin_fd: i32
    stdout_fd: i32
    stderr_fd: i32
    done: bool
    drop {
        if self.stdin_fd >= 0 { let closed = unsafe { sys.close(self.stdin_fd) } }
        if self.stdout_fd >= 0 { let closed = unsafe { sys.close(self.stdout_fd) } }
        if self.stderr_fd >= 0 { let closed = unsafe { sys.close(self.stderr_fd) } }
    }
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
    pub mut fn take_stdin(): ChildStdin? {
        let fd = self.stdin_fd
        if fd < 0 { return none }
        self.stdin_fd = -1
        present(ChildStdin(fd))
    }
    pub mut fn take_stdout(): ChildOutput? {
        let fd = self.stdout_fd
        if fd < 0 { return none }
        self.stdout_fd = -1
        present(ChildOutput(fd))
    }
    pub mut fn take_stderr(): ChildOutput? {
        let fd = self.stderr_fd
        if fd < 0 { return none }
        self.stderr_fd = -1
        present(ChildOutput(fd))
    }

    // Waits for the child to end, closing its input pipe first so it cannot
    // block forever waiting for input this process still holds open.
    pub mut fn wait(): ExitStatus throws Error {
        if self.stdin_fd >= 0 {
            let closed = unsafe { sys.close(self.stdin_fd) }
            self.stdin_fd = -1
        }
        self.done = true
        match try wait_status(self.pid, 0) {
            present(s) => s,
            none => ExitStatus(0)
        }
    }

    // The status if the child has already ended, without blocking.
    pub mut fn try_wait(): ExitStatus? throws Error {
        let r = try wait_status(self.pid, 1)
        match r {
            present(s) => { self.done = true; present(s) },
            none => none
        }
    }

    // Sends SIGKILL; a child that already ended is not an error.
    pub mut fn kill(): Unit throws Error {
        if self.done { return }
        if unsafe { sys.kill(self.pid, 9) } != 0 {
            let e = io.last_os_error()
            if e.raw_os_error() != present(3) { throw e }
        }
    }

    // Closes the input pipe, reads both piped outputs to the end, then waits.
    pub mut fn wait_with_output(): Output throws Error {
        if self.stdin_fd >= 0 {
            let closed = unsafe { sys.close(self.stdin_fd) }
            self.stdin_fd = -1
        }
        var out = vec.new<u8>()
        var err = vec.new<u8>()
        var chunk = [0u8; 4096]
        while self.stdout_fd >= 0 || self.stderr_fd >= 0 {
            let ready = unsafe { sys.mettle_rt_poll_pair(self.stdout_fd, self.stderr_fd) }
            if ready < 0 { throw io.last_os_error() }
            if (ready & 1) != 0 {
                let n = try io.read_fd(self.stdout_fd, chunk)
                if n == 0usize {
                    let closed = unsafe { sys.close(self.stdout_fd) }
                    self.stdout_fd = -1
                } else {
                    out.extend_from_slice(chunk.split_at(n).0)
                }
            }
            if (ready & 2) != 0 {
                let n = try io.read_fd(self.stderr_fd, chunk)
                if n == 0usize {
                    let closed = unsafe { sys.close(self.stderr_fd) }
                    self.stderr_fd = -1
                } else {
                    err.extend_from_slice(chunk.split_at(n).0)
                }
            }
        }
        let status = try self.wait()
        Output(status, out, err)
    }
}

type EnvChange { name: OsString; value: OsString; remove: bool }

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
}

pub fn command(program: read OsStr): Command {
    Command(program.to_os_string(), vec.new<OsString>(), vec.new<EnvChange>(), false,
            super.path.new_path_buf(), false, Stdio.Inherit, Stdio.Inherit, Stdio.Inherit)
}

pub fn command_text(program: read Text): Command { command(ffi.os_str_from_text(program)) }

extend Command {
    pub static fn new(program: read OsStr): Command { command(program) }
    pub mut fn arg(a: read OsStr): Unit { self.args.push(a.to_os_string()) }
    pub mut fn args(values: read [OsString]): Unit {
        var index = 0usize
        while index < values.len() {
            self.args.push(values[index].as_os_str().to_os_string())
            index += 1usize
        }
    }
    pub fn get_program(): read OsStr from self { self.program.as_os_str() }
    pub fn get_args(): read [OsString] from self { self.args.as_slice() }
    pub fn get_current_dir(): (read PathBuf from self)? {
        if self.has_cwd { present(read self.cwd) } else { none }
    }
    pub fn get_envs(): List<env.EnvVar> {
        var entries = vec.new<env.EnvVar>()
        if !self.clear_env {
            let current = env.vars()
            var index = 0usize
            while index < current.len() {
                entries.push(env.EnvVar(current[index].name.as_os_str().to_os_string(), current[index].value.as_os_str().to_os_string()))
                index += 1usize
            }
        }
        var change = 0usize
        while change < self.changes.len() {
            var slot = 0usize
            while slot < entries.len() {
                if entries[slot].name.same(self.changes[change].name) {
                    let gone = entries.remove(slot)
                } else {
                    slot += 1usize
                }
            }
            if !self.changes[change].remove {
                entries.push(env.EnvVar(
                    self.changes[change].name.as_os_str().to_os_string(),
                    self.changes[change].value.as_os_str().to_os_string()
                ))
            }
            change += 1usize
        }
        entries
    }
    pub mut fn arg_text(a: read Text): Unit { self.args.push(ffi.os_string_from_text(a)) }
    // Sets `name` for the child only.
    pub mut fn env(name: read OsStr, value: read OsStr): Unit {
        self.changes.push(EnvChange(name.to_os_string(), value.to_os_string(), false))
    }
    // Removes `name` from the child's environment.
    pub mut fn env_remove(name: read OsStr): Unit {
        self.changes.push(EnvChange(name.to_os_string(), ffi.new_os_string(), true))
    }
    // Starts the child with an empty environment (plus later `env` calls).
    pub mut fn env_clear(): Unit { self.clear_env = true; self.changes.clear() }
    pub mut fn envs(pairs: read [env.EnvVar]): Unit {
        var index = 0usize
        while index < pairs.len() {
            self.env(pairs[index].name.as_os_str(), pairs[index].value.as_os_str())
            index += 1usize
        }
    }
    pub mut fn current_dir(input: read PathInput): Unit {
        self.cwd = input.as_path().to_path_buf()
        self.has_cwd = true
    }
    pub mut fn stdin(s: Stdio): Unit { self.stdin = s }
    pub mut fn stdout(s: Stdio): Unit { self.stdout = s }
    pub mut fn stderr(s: Stdio): Unit { self.stderr = s }

    // The child's environment as NUL-terminated `name=value` strings.
    fn environment(): List<List<u8>> throws Error {
        var entries = vec.new<EnvChange>()
        if !self.clear_env {
            let current = env.vars()
            var i = 0usize
            while i < current.len() {
                entries.push(EnvChange(current[i].name.as_os_str().to_os_string(), current[i].value.as_os_str().to_os_string(), false))
                i += 1usize
            }
        }
        var k = 0usize
        while k < self.changes.len() {
            var m = 0usize
            while m < entries.len() {
                if entries[m].name.same(self.changes[k].name) { let gone = entries.remove(m) } else { m += 1usize }
            }
            if !self.changes[k].remove {
                entries.push(EnvChange(self.changes[k].name.as_os_str().to_os_string(), self.changes[k].value.as_os_str().to_os_string(), false))
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
        let env_pairs = try self.environment()
        var envp = vec.new<ptr<read u8>>()
        var e = 0usize
        while e < env_pairs.len() {
            envp.push(env_pairs[e].as_ptr())
            e += 1usize
        }
        envp.push(core.ptr.null<u8>())
        var cwd_c = vec.new<u8>()
        if self.has_cwd { cwd_c = try ffi.cstring(self.cwd.as_bytes()) }
        var modes = [stdio_code(self.stdin), stdio_code(self.stdout), stdio_code(self.stderr)]
        var fds = [-1, -1, -1]
        let use_env = self.clear_env || self.changes.len() > 0usize
        let cwd_ptr = if self.has_cwd { cwd_c.as_ptr() } else { core.ptr.null<u8>() }
        let envp_ptr = if use_env { envp.as_ptr() } else { core.ptr.null<ptr<read u8>>() }
        let pid = unsafe {
            sys.mettle_rt_spawn(strings[0usize].as_ptr(), argv.as_ptr(), envp_ptr, cwd_ptr,
                                 core.ptr.from_mut(modes).cast<i32>().cast_const(),
                                 core.ptr.from_mut(fds).cast<i32>())
        }
        if pid < 0 { throw io.last_os_error() }
        Child(pid, fds[0usize], fds[1usize], fds[2usize], false)
    }

    // Runs to completion with inherited streams and returns how it ended.
    pub fn status(): ExitStatus throws Error {
        var child = try self.spawn()
        try child.wait()
    }

    // Runs to completion capturing standard output and error (both are piped
    // regardless of earlier settings; input is closed).
    pub mut fn output(): Output throws Error {
        self.stdin = Stdio.Null
        self.stdout = Stdio.Piped
        self.stderr = Stdio.Piped
        var child = try self.spawn()
        var out = vec.new<u8>()
        var err = vec.new<u8>()
        var chunk = [0u8; 4096]
        while child.stdout_fd >= 0 || child.stderr_fd >= 0 {
            let ready = unsafe { sys.mettle_rt_poll_pair(child.stdout_fd, child.stderr_fd) }
            if ready < 0 { throw io.last_os_error() }
            if (ready & 1) != 0 {
                let n = try io.read_fd(child.stdout_fd, chunk)
                if n == 0usize { let closed = unsafe { sys.close(child.stdout_fd) }; child.stdout_fd = -1 }
                else { out.extend_from_slice(chunk.split_at(n).0) }
            }
            if (ready & 2) != 0 {
                let n = try io.read_fd(child.stderr_fd, chunk)
                if n == 0usize { let closed = unsafe { sys.close(child.stderr_fd) }; child.stderr_fd = -1 }
                else { err.extend_from_slice(chunk.split_at(n).0) }
            }
        }
        let status = try child.wait()
        Output(status, out, err)
    }
}
