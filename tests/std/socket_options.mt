import std.io.Error
import std.net
import std.time.Duration

fn run(): i32 throws Error {
    var listener = try net.tcp_listen(net.socket_addr(net.localhost(), 0u16))
    try listener.set_ttl(9u32)
    if try listener.ttl() != 9u32 { return 1 }

    var socket = try net.udp_bind(net.socket_addr(net.localhost(), 0u16))
    let address = try socket.local_addr()
    try socket.set_ttl(7u32)
    if try socket.ttl() != 7u32 { return 2 }
    try socket.set_broadcast(true)
    if !try socket.broadcast() { return 3 }
    try socket.set_broadcast(false)
    if try socket.broadcast() { return 4 }
    try socket.set_multicast_loop_v4(false)
    if try socket.multicast_loop_v4() { return 5 }
    try socket.set_multicast_ttl_v4(3u32)
    if try socket.multicast_ttl_v4() != 3u32 { return 6 }
    try socket.set_read_timeout(present(Duration.new(1u64, 0u32)))
    match try socket.read_timeout() {
        present(limit) => { if limit.as_secs() != 1u64 { return 7 } },
        none => { return 7 }
    }
    try socket.set_read_timeout(none)
    match try socket.read_timeout() {
        present(_) => { return 8 },
        none => {}
    }
    try socket.send_to("hi".as_bytes(), address)
    var buf = [0u8; 8]
    let peeked = try socket.peek_from(buf)
    if peeked.0 != 2usize || buf[0usize] != 104u8 || buf[1usize] != 105u8 { return 9 }
    let received = try socket.recv_from(buf)
    if received.0 != 2usize { return 10 }
    try socket.join_multicast_v4(net.ipv4(224u8, 0u8, 0u8, 1u8), net.unspecified())
    try socket.leave_multicast_v4(net.ipv4(224u8, 0u8, 0u8, 1u8), net.unspecified())
    let bound = try net.TcpListener.bind(net.socket_addr(net.localhost(), 0u16))
    let _listener_addr = try bound.local_addr()
    let packet = try net.UdpSocket.bind(net.socket_addr(net.localhost(), 0u16))
    let _packet_addr = try packet.local_addr()
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => {
            match error.raw_os_error() { present(code) => 100 + code, none => 99 }
        }
    }
}
