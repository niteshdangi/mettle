// Raw operating-system boundary of `std`: the libc calls and the
// `runtime/sys.cpp` shims (see `runtime/sys.h`), plus checked helpers shared by
// the hosted modules. Nothing here is a stable public surface.
import package.alloc.vec
import package.alloc.vec.List

extern "C" {
    pub unsafe fn mettle_rt_errno(): i32;
    pub unsafe fn mettle_rt_errno_kind(code: i32): i32;
    pub unsafe fn mettle_rt_errno_is_range(code: i32): i32;
    pub unsafe fn mettle_rt_dup(fd: i32): i32;
    pub unsafe fn mettle_rt_remove_dir_all(path: ptr<read u8>): i32;
    pub unsafe fn mettle_rt_set_errno(code: i32): Unit;
    pub unsafe fn mettle_rt_open(path: ptr<read u8>, flags: i32, mode: u32): i32;
    pub unsafe fn mettle_rt_stat(path: ptr<read u8>, fd: i32, follow: i32, out: ptr<mut i64>): i32;
    pub unsafe fn mettle_rt_stat_full(path: ptr<read u8>, fd: i32, follow: i32, out: ptr<mut i64>): i32;
    pub unsafe fn mettle_rt_file_set_times(fd: i32, mask: u32, accessed_seconds: i64, accessed_nanoseconds: u32, modified_seconds: i64, modified_nanoseconds: u32): i32;
    pub unsafe fn mettle_rt_reentrant_mutex_new(): ptr<mut u8>;
    pub unsafe fn mettle_rt_mutex_free(mutex: ptr<mut u8>): Unit;
    pub unsafe fn mettle_rt_mutex_lock(mutex: ptr<mut u8>): i32;
    pub unsafe fn mettle_rt_mutex_unlock(mutex: ptr<mut u8>): i32;
    pub unsafe fn mettle_rt_readdir(dir: ptr<mut u8>): ptr<read u8>;
    pub unsafe fn mettle_rt_argc(): i32;
    pub unsafe fn mettle_rt_argv(index: i32): ptr<read u8>;
    pub unsafe fn mettle_rt_environ(): ptr<read ptr<read u8>>;
    pub unsafe fn mettle_rt_spawn(program: ptr<read u8>, argv: ptr<read ptr<read u8>>, envp: ptr<read ptr<read u8>>, cwd: ptr<read u8>, modes: ptr<read i32>, fds: ptr<mut i32>): i32;
    pub unsafe fn mettle_rt_spawn_with_sources(program: ptr<read u8>, argv: ptr<read ptr<read u8>>, envp: ptr<read ptr<read u8>>, cwd: ptr<read u8>, modes: ptr<read i32>, sources: ptr<read i32>, fds: ptr<mut i32>): i32;
    pub unsafe fn mettle_rt_poll(fd: i32, write: i32, timeout_millis: i32): i32;
    pub unsafe fn mettle_rt_poll_pair(first: i32, second: i32): i32;
    pub unsafe fn mettle_rt_sock_new(kind: i32, family: i32): i32;
    pub unsafe fn mettle_rt_sock_bind(fd: i32, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32): i32;
    pub unsafe fn mettle_rt_sock_connect(fd: i32, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32): i32;
    pub unsafe fn mettle_rt_sock_connect_timeout(fd: i32, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32, timeout_micros: u64): i32;
    pub unsafe fn mettle_rt_sock_accept(fd: i32, timeout_millis: i32, nonblocking: i32, timed_out: ptr<mut i32>, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_sock_name(fd: i32, peer: i32, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_sock_send(fd: i32, data: ptr<read u8>, size: usize): isize;
    pub unsafe fn mettle_rt_sock_sendto(fd: i32, data: ptr<read u8>, size: usize, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32): isize;
    pub unsafe fn mettle_rt_sock_recvfrom(fd: i32, data: ptr<mut u8>, size: usize, peek: i32, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): isize;
    pub unsafe fn mettle_rt_sock_timeout(fd: i32, send: i32, micros: u64): i32;
    pub unsafe fn mettle_rt_sock_get_timeout(fd: i32, send: i32, seconds: ptr<mut u64>, nanos: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_sock_set_option(fd: i32, option: i32, value: u32): i32;
    pub unsafe fn mettle_rt_sock_get_option(fd: i32, option: i32, value: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_sock_membership_v4(fd: i32, group: ptr<read u8>, interface_addr: ptr<read u8>, join: i32): i32;
    pub unsafe fn mettle_rt_sock_membership_v6(fd: i32, group: ptr<read u8>, interface_index: u32, join: i32): i32;
    pub unsafe fn mettle_rt_sock_set_nodelay(fd: i32, enabled: i32): i32;
    pub unsafe fn mettle_rt_sock_get_nodelay(fd: i32, enabled: ptr<mut i32>): i32;
    pub unsafe fn mettle_rt_sock_error(fd: i32, error: ptr<mut i32>): i32;
    pub unsafe fn mettle_rt_resolve(host: ptr<read u8>, host_size: usize, port: u16, count: ptr<mut usize>): ptr<mut u8>;
    pub unsafe fn mettle_rt_resolve_get(handle: ptr<mut u8>, index: usize, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_resolve_free(handle: ptr<mut u8>): Unit;
    pub unsafe fn mettle_rt_clock(clock: i32, out: ptr<mut i64>): i32;
    pub unsafe fn mettle_rt_sleep(seconds: u64, nanos: u32): Unit;
    pub unsafe fn mettle_rt_reactor_new(): ptr<mut u8>;
    pub unsafe fn mettle_rt_reactor_close(reactor: ptr<mut u8>): Unit;
    pub unsafe fn mettle_rt_reactor_watch(reactor: ptr<mut u8>, fd: i32, write: i32, data: ptr<mut u8>, wake: extern "C" fn(ptr<mut u8>): Unit, release: extern "C" fn(ptr<mut u8>): Unit): u64;
    pub unsafe fn mettle_rt_reactor_timer(reactor: ptr<mut u8>, seconds: u64, nanos: u32, data: ptr<mut u8>, wake: extern "C" fn(ptr<mut u8>): Unit, release: extern "C" fn(ptr<mut u8>): Unit): u64;
    pub unsafe fn mettle_rt_reactor_cancel(reactor: ptr<mut u8>, token: u64): Unit;
    pub unsafe fn mettle_rt_reactor_wake(reactor: ptr<mut u8>): Unit;
    pub unsafe fn mettle_rt_reactor_wait(reactor: ptr<mut u8>): i32;
    pub unsafe fn mettle_rt_set_nonblocking(fd: i32): i32;
    pub unsafe fn mettle_rt_set_blocking(fd: i32): i32;
    pub unsafe fn mettle_rt_sock_is_nonblocking(fd: i32): i32;
    pub unsafe fn mettle_rt_sock_connect_start(fd: i32, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32): i32;
    pub unsafe fn mettle_rt_sock_connect_status(fd: i32): i32;

    pub unsafe fn `read`(fd: i32, buffer: ptr<mut u8>, count: usize): isize;
    pub unsafe fn write(fd: i32, buffer: ptr<read u8>, count: usize): isize;
    pub unsafe fn close(fd: i32): i32;
    pub unsafe fn lseek(fd: i32, offset: i64, whence: i32): i64;
    pub unsafe fn unlink(path: ptr<read u8>): i32;
    pub unsafe fn rmdir(path: ptr<read u8>): i32;
    pub unsafe fn mkdir(path: ptr<read u8>, mode: u32): i32;
    pub unsafe fn rename(old: ptr<read u8>, new: ptr<read u8>): i32;
    pub unsafe fn opendir(path: ptr<read u8>): ptr<mut u8>;
    pub unsafe fn closedir(dir: ptr<mut u8>): i32;
    pub unsafe fn getcwd(buffer: ptr<mut u8>, size: usize): ptr<mut u8>;
    pub unsafe fn chdir(path: ptr<read u8>): i32;
    pub unsafe fn getenv(name: ptr<read u8>): ptr<read u8>;
    pub unsafe fn setenv(name: ptr<read u8>, value: ptr<read u8>, overwrite: i32): i32;
    pub unsafe fn unsetenv(name: ptr<read u8>): i32;
    pub unsafe fn waitpid(pid: i32, status: ptr<mut i32>, options: i32): i32;
    pub unsafe fn kill(pid: i32, signal: i32): i32;
    pub unsafe fn listen(fd: i32, backlog: i32): i32;
    pub unsafe fn shutdown(fd: i32, how: i32): i32;
    pub unsafe fn exit(code: i32): Never;
    pub unsafe fn abort(): Never;
    pub unsafe fn strlen(text: ptr<read u8>): usize;
    pub unsafe fn strerror(code: i32): ptr<read u8>;
}

// An owned POSIX descriptor. Dropping closes it unless `into_raw_fd` transfers
// ownership; `as_raw_fd` only lends the integer descriptor.
pub type OwnedFd {
    fd: i32
    drop {
        if self.fd >= 0 { let closed = unsafe { close(self.fd) } }
    }
}

extend OwnedFd {
    // Safety: `fd` must be open and exclusively owned by the caller.
    pub unsafe static fn from_raw_fd(fd: i32): OwnedFd { OwnedFd(fd) }

    // The returned integer is borrowed; do not close it or use it after self.
    pub fn as_raw_fd(): i32 { self.fd }

    pub take fn into_raw_fd(): i32 {
        var this = self
        let fd = this.fd
        this.fd = -1
        fd
    }
}

// `open` flags understood by `mettle_rt_open`.
pub fn open_read(): i32 { 1 }
pub fn open_write(): i32 { 2 }
pub fn open_append(): i32 { 4 }
pub fn open_truncate(): i32 { 8 }
pub fn open_create(): i32 { 16 }
pub fn open_create_new(): i32 { 32 }

pub fn errno(): i32 { unsafe { mettle_rt_errno() } }

// Bytes of the NUL-terminated string at `p`, without the terminator.
// Safety: `p` points at a NUL-terminated string that outlives the copy.
pub unsafe fn bytes_from_c(p: ptr<read u8>): List<u8> {
    let n = unsafe { strlen(p) }
    var out = vec.with_capacity<u8>(n)
    var i = 0usize
    while i < n {
        out.push(unsafe { *p.add(i) })
        i += 1usize
    }
    out
}

copy type RawMut { data: ptr<mut u8>; len: usize }

// Base address of a mutable byte slice.
pub fn data_mut(mut bytes: [u8]): ptr<mut u8> {
    let fat = core.ptr.from_mut(bytes)
    let raw = unsafe { core.mem.transmute<RawMut>(fat) }
    raw.data
}
