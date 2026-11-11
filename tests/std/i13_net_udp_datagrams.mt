import core.outcome
import std.io.{ Error, ErrorKind }
import std.net.{ IpAddr, SocketAddr, UdpSocket }
import std.time.from_millis

fn would_block(take result: Outcome<usize, Error>): bool {
    match take result {
        success(_) => false,
        failure(error) => error.kind().is(ErrorKind.WouldBlock) && error.is_os()
    }
}

fn would_block_from(take result: Outcome<(usize, SocketAddr), Error>): bool {
    match take result {
        success(_) => false,
        failure(error) => error.kind().is(ErrorKind.WouldBlock) && error.is_os()
    }
}

fn run(ip: IpAddr): i32 throws Error {
    let target = try UdpSocket.bind(std.net.socket_addr_ip(ip, 0u16))
    let sender = try UdpSocket.bind(std.net.socket_addr_ip(ip, 0u16))
    let destination = try target.local_addr()
    let source = try sender.local_addr()
    try target.connect(source)
    try sender.connect(destination)
    try target.set_read_timeout(present(from_millis(1000u64)))
    var buffer = [0u8; 8]
    var empty = [0u8; 0]

    try target.set_nonblocking(true)
    if !would_block(capture target.recv(buffer)) { return 1 }
    if !would_block(capture target.peek(buffer)) { return 2 }
    if !would_block_from(capture target.recv_from(buffer)) { return 3 }
    if !would_block_from(capture target.peek_from(buffer)) { return 4 }
    if !would_block(capture target.recv(empty)) { return 5 }
    if !would_block_from(capture target.peek_from(empty)) { return 6 }
    try target.set_nonblocking(false)

    if try sender.send(empty) != 0usize { return 7 }
    if try target.peek(buffer) != 0usize { return 8 }
    let empty_peek = try target.peek_from(buffer)
    if empty_peek.0 != 0usize || !empty_peek.1.same(source) { return 9 }
    let empty_packet = try target.recv_from(buffer)
    if empty_packet.0 != 0usize || !empty_packet.1.same(source) { return 10 }
    try target.set_nonblocking(true)
    if !would_block(capture target.recv(buffer)) { return 11 }
    try target.set_nonblocking(false)

    if try sender.send_to(empty, destination) != 0usize { return 12 }
    if try target.recv(buffer) != 0usize { return 13 }
    try target.set_nonblocking(true)
    if !would_block_from(capture target.recv_from(buffer)) { return 14 }
    try target.set_nonblocking(false)

    let payload = [0u8, 255u8, 7u8, 8u8, 9u8]
    if try sender.send(payload) != 5usize { return 15 }
    let zero_peek = try target.peek_from(empty)
    if zero_peek.0 != 0usize || !zero_peek.1.same(source) { return 16 }
    var prefix = [0u8; 2]
    let first_peek = try target.peek_from(prefix)
    if first_peek.0 != 2usize || !first_peek.1.same(source) ||
        prefix[0usize] != 0u8 || prefix[1usize] != 255u8 { return 17 }
    if try target.peek(buffer) != 5usize { return 18 }
    var index = 0usize
    while index < 5usize {
        if buffer[index] != payload[index] { return 19 }
        index += 1usize
    }
    if try target.recv(prefix) != 2usize { return 20 }
    try target.set_nonblocking(true)
    if !would_block_from(capture target.recv_from(buffer)) { return 21 }
    try target.set_nonblocking(false)

    if try sender.send_to(payload, destination) != 5usize { return 22 }
    let truncated = try target.recv_from(prefix)
    if truncated.0 != 2usize || !truncated.1.same(source) ||
        prefix[0usize] != 0u8 || prefix[1usize] != 255u8 { return 23 }
    try target.set_nonblocking(true)
    if !would_block(capture target.peek(buffer)) { return 24 }
    try target.set_nonblocking(false)

    if try sender.send(payload) != 5usize { return 25 }
    if try target.recv(empty) != 0usize { return 26 }
    try target.set_nonblocking(true)
    if !would_block_from(capture target.peek_from(buffer)) { return 27 }
    try target.set_nonblocking(false)
    if try sender.send(payload) != 5usize { return 28 }
    if (try target.recv_from(empty)).0 != 0usize { return 29 }
    try target.set_nonblocking(true)
    if !would_block(capture target.recv(buffer)) { return 30 }
    {
        let clone = try target.try_clone()
        try clone.set_nonblocking(false)
        try clone.set_read_timeout(present(from_millis(50u64)))
        match take capture target.peek_from(buffer) {
            success(_) => { return 31 },
            failure(error) => {
                if !error.kind().is(ErrorKind.TimedOut) || !error.is_os() {
                    return 32
                }
            }
        }
    }
    match take capture target.recv_from(buffer) {
        success(_) => { return 33 },
        failure(error) => {
            if !error.kind().is(ErrorKind.TimedOut) || !error.is_os() { return 34 }
        }
    }
    try target.set_nonblocking(true)
    if !would_block(capture target.peek(buffer)) { return 35 }
    try target.set_read_timeout(none)
    if !would_block(capture target.recv(buffer)) { return 36 }
    0
}

fn main(): i32 {
    match take capture run(IpAddr.V4(std.net.localhost())) {
        success(code) => { if code != 0 { return code } },
        failure(error) => {
            std.io.eprint(f"IPv4 UDP acceptance failed: {error}\n")
            return 100
        }
    }
    match take capture run(IpAddr.V6(std.net.ipv6_localhost())) {
        success(code) => if code == 0 { 0 } else { 100 + code },
        failure(error) => {
            std.io.eprint(f"IPv6 UDP acceptance failed: {error}\n")
            200
        }
    }
}
