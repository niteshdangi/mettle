import core.slice
import std.io
import std.io.{Error, ErrorKind, Reader, Writer}
import std.net.{TcpListener, TcpStream}
import std.sys
import std.time.{Duration, from_millis}

extern "C" {
    unsafe fn accept(fd: i32, address: ptr<mut u8>, size: ptr<mut u32>): i32;
}

fn adopted(nonblocking: bool): (TcpListener, i32) throws Error {
    let fd = unsafe { sys.mettle_rt_sock_new(0, 4) }
    if fd < 0 { throw io.last_os_error() }
    let owned = unsafe { sys.OwnedFd.from_raw_fd(fd) }
    let address = [127u8, 0u8, 0u8, 1u8]
    if unsafe { sys.mettle_rt_sock_bind(fd, 4, slice.data(address), 4usize, 0u16, 0u32, 0u32) } != 0 ||
       unsafe { sys.listen(fd, 8) } != 0 {
        throw io.last_os_error()
    }
    if nonblocking && unsafe { sys.mettle_rt_set_nonblocking(fd) } != 0 {
        throw io.last_os_error()
    }
    let listener = unsafe { try TcpListener.from_owned_fd(owned) }
    (listener, fd)
}

fn would_block(read listener: TcpListener): bool {
    match take capture listener.accept() {
        success(pair) => false,
        failure(error) => error.kind().is(ErrorKind.WouldBlock) && error.is_os()
    }
}

fn expires(read listener: TcpListener, budget: Duration): bool {
    let start = std.time.now()
    match take capture listener.accept() {
        success(pair) => false,
        failure(error) => error.kind().is(ErrorKind.TimedOut) && error.is_os() &&
                          !start.elapsed().lt(budget)
    }
}

fn run(): i32 throws Error {
    let adoption = try adopted(false)
    var listener = adoption.0
    let raw = adoption.1
    if unsafe { sys.mettle_rt_sock_is_nonblocking(raw) } != 1 { return 1 }
    try listener.set_accept_timeout(present(from_millis(20u64)))
    if !expires(read listener, from_millis(20u64)) { return 13 }
    var cloned = try listener.try_clone()
    try cloned.set_accept_timeout(present(from_millis(5u64)))
    try cloned.set_nonblocking(true)
    if !would_block(read listener) || !would_block(read cloned) { return 2 }
    try listener.set_nonblocking(false)
    if unsafe { sys.mettle_rt_sock_is_nonblocking(raw) } != 1 { return 3 }
    if unsafe { accept(raw, core.ptr.null_mut<u8>(), core.ptr.null_mut<u32>()) } != -1 {
        return 4
    }
    if !io.last_os_error().kind().is(ErrorKind.WouldBlock) { return 5 }
    if !expires(read listener, from_millis(20u64)) ||
       !expires(read cloned, from_millis(5u64)) { return 6 }

    var client = try TcpStream.connect(try listener.local_addr())
    try cloned.set_nonblocking(true)
    let pair = try listener.accept()
    var stream = pair.0
    try stream.set_read_timeout(present(from_millis(5u64)))
    var byte = [0u8; 1]
    match take capture stream.read_some(mut byte) {
        success(count) => { return 7 },
        failure(error) => {
            if !error.kind().is(ErrorKind.TimedOut) || !error.is_os() { return 8 }
        }
    }
    try client.write_all("x".as_bytes())
    try stream.read_exact(mut byte)
    if byte[0usize] != 120u8 { return 9 }

    let survivor = {
        let pair = try adopted(true)
        let listener = pair.0
        if !would_block(read listener) { return 10 }
        try listener.try_clone()
    }
    if !would_block(read survivor) { return 11 }
    let created = try TcpListener.bind(std.net.socket_addr(std.net.localhost(), 0u16))
    try created.set_nonblocking(true)
    if !would_block(read created) { return 12 }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => 100
    }
}
