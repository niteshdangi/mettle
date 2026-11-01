// TCP incoming iteration and peek use only the local loopback interface.
import core.iter.Iterator
import std.io.{ Error, ErrorKind, Reader, Writer }
import std.net.TcpStream
import std.time.from_millis

fn run(): i32 throws Error {
    var listener = try std.net.tcp_listen(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    let address = try listener.local_addr()
    var client = try TcpStream.connect_timeout(address, from_millis(1000u64))

    let payload: [u8; 5] = [105u8, 49u8, 51u8, 0u8, 255u8]
    let payload_bytes: read [u8] = read payload
    try client.write_all(payload)

    var incoming = listener.incoming()
    let item = match take incoming.next() {
        present(value) => value,
        none => { return 1 }
    }
    var server = match take item {
        success(stream) => stream,
        failure(error) => { return 2 }
    }
    if !(try server.peer_addr()).ip.is_loopback() { return 3 }

    var peeked = [0u8; 5]
    try server.set_read_timeout(present(from_millis(1000u64)))
    let peek_count = try server.peek(peeked)
    if peek_count == 0usize || peek_count > 5usize { return 4 }
    var index = 0usize
    while index < peek_count {
        if peeked[index] != payload[index] { return 5 }
        index += 1usize
    }

    var received = [0u8; 5]
    try server.read_exact(received)
    if received[0usize] != payload[0usize] ||
        received[1usize] != payload[1usize] ||
        received[2usize] != payload[2usize] ||
        received[3usize] != payload[3usize] ||
        received[4usize] != payload[4usize] {
        return 6
    }

    try listener.set_nonblocking(true)
    match take incoming.next() {
        present(item) => match take item {
            success(_) => { return 11 },
            failure(error) => {
                if !error.kind().is(ErrorKind.WouldBlock) { return 12 }
            }
        },
        none => { return 13 }
    }

    var udp_receiver = try std.net.udp_bind(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    var udp_sender = try std.net.udp_bind(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    let receiver_address = try udp_receiver.local_addr()
    try udp_sender.connect(receiver_address)
    if !(try udp_sender.peer_addr()).same(receiver_address) { return 7 }
    if try udp_sender.send(payload) != payload_bytes.len() { return 8 }
    var datagram = [0u8; 5]
    let received_datagram = try udp_receiver.recv_from(datagram)
    if received_datagram.0 != payload_bytes.len() ||
        !received_datagram.1.ip.is_loopback() {
        return 9
    }
    if datagram[0usize] != payload[0usize] ||
        datagram[1usize] != payload[1usize] ||
        datagram[2usize] != payload[2usize] ||
        datagram[3usize] != payload[3usize] ||
        datagram[4usize] != payload[4usize] {
        return 10
    }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
