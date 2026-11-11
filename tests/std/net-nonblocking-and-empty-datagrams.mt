import std.io.{Error, ErrorKind}

fn run(): i32 throws Error {
    let a = try std.net.udp_bind(std.net.socket_addr(std.net.localhost(), 0u16))
    let b = try std.net.udp_bind(std.net.socket_addr(std.net.localhost(), 0u16))
    try a.connect(try b.local_addr())
    try b.connect(try a.local_addr())
    try a.set_nonblocking(true)
    var byte = [0u8]
    match take capture a.recv_from(byte) {
        failure(error) => { if !error.kind().is(ErrorKind.WouldBlock) { return 1 } },
        success(_) => { return 2 }
    }
    try a.set_nonblocking(false)
    try a.set_read_timeout(present(std.time.from_millis(1000u64)))
    try b.set_read_timeout(present(std.time.from_millis(1000u64)))
    let empty = [0u8; 0]
    if try b.send(empty) != 0usize { return 3 }
    if try a.recv(byte) != 0usize { return 4 }
    let _ = try b.send_to(empty, try a.local_addr())
    let _ = try b.send("x".as_bytes())
    var no_room = [0u8; 0]
    if try a.recv(no_room) != 0usize { return 5 }
    if try a.recv(byte) != 1usize || byte[0usize] != 120u8 { return 6 }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
