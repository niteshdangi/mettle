// Raw operating-system boundary of `std`: the libc calls and the
// `runtime/sys.cpp` shims (see `runtime/sys.h`), plus checked helpers shared by
// the hosted modules. Nothing here is a stable public surface.
import package.alloc.vec
import package.alloc.vec.List

extern "C" {
    pub unsafe fn mettle_rt_errno(): i32;
    pub unsafe fn mettle_rt_errno_kind(code: i32): i32;
    pub unsafe fn mettle_rt_set_errno(code: i32): Unit;
    pub unsafe fn mettle_rt_open(path: ptr<read u8>, flags: i32, mode: u32): i32;
    pub unsafe fn mettle_rt_stat(path: ptr<read u8>, fd: i32, follow: i32, out: ptr<mut i64>): i32;
    pub unsafe fn mettle_rt_readdir(dir: ptr<mut u8>): ptr<read u8>;
    pub unsafe fn mettle_rt_argc(): i32;
    pub unsafe fn mettle_rt_argv(index: i32): ptr<read u8>;
    pub unsafe fn mettle_rt_environ_at(index: i32): ptr<read u8>;
    pub unsafe fn mettle_rt_spawn(program: ptr<read u8>, argv: ptr<read ptr<read u8>>, envp: ptr<read ptr<read u8>>, cwd: ptr<read u8>, modes: ptr<read i32>, fds: ptr<mut i32>): i32;
    pub unsafe fn mettle_rt_poll(fd: i32, write: i32, timeout_millis: i32): i32;
    pub unsafe fn mettle_rt_poll_pair(first: i32, second: i32): i32;
    pub unsafe fn mettle_rt_sock_new(kind: i32, family: i32): i32;
    pub unsafe fn mettle_rt_sock_bind(fd: i32, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32): i32;
    pub unsafe fn mettle_rt_sock_connect(fd: i32, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32): i32;
    pub unsafe fn mettle_rt_sock_connect_timeout(fd: i32, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32, timeout_micros: u64): i32;
    pub unsafe fn mettle_rt_sock_accept(fd: i32, timeout_millis: i32, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_sock_name(fd: i32, peer: i32, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_sock_send(fd: i32, data: ptr<read u8>, size: usize): isize;
    pub unsafe fn mettle_rt_sock_sendto(fd: i32, data: ptr<read u8>, size: usize, family: i32, address: ptr<read u8>, address_size: usize, port: u16, flowinfo: u32, scope_id: u32): isize;
    pub unsafe fn mettle_rt_sock_recvfrom(fd: i32, data: ptr<mut u8>, size: usize, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): isize;
    pub unsafe fn mettle_rt_sock_timeout(fd: i32, send: i32, micros: u64): i32;
    pub unsafe fn mettle_rt_resolve(host: ptr<read u8>, host_size: usize, port: u16, count: ptr<mut usize>): ptr<mut u8>;
    pub unsafe fn mettle_rt_resolve_get(handle: ptr<mut u8>, index: usize, family: ptr<mut i32>, address: ptr<mut u8>, address_capacity: usize, port: ptr<mut u16>, flowinfo: ptr<mut u32>, scope_id: ptr<mut u32>): i32;
    pub unsafe fn mettle_rt_resolve_free(handle: ptr<mut u8>): Unit;
    pub unsafe fn mettle_rt_clock(clock: i32, out: ptr<mut i64>): i32;
    pub unsafe fn mettle_rt_sleep(seconds: u64, nanos: u32): Unit;

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
pub fn data_mut(bytes: mut [u8]): ptr<mut u8> {
    let fat = core.ptr.from_mut(bytes)
    let raw = unsafe { core.mem.transmute<RawMut>(fat) }
    raw.data
}
