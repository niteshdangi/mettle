import std.io.{Error, ErrorKind, Reader, Writer}
import std.net.{IpAddr, TcpStream}
import std.time.from_millis

fn unavailable(error: Error): bool {
    error.kind().is(ErrorKind.AddrNotAvailable) ||
        error.raw_os_error() == present(47) ||
        error.raw_os_error() == present(97)
}

fn run(): i32 throws Error {
    let bind_result = capture std.net.tcp_listen(
        std.net.socket_addr_v6(std.net.ipv6_localhost(), 0u16, 0u32, 0u32)
    )
    var listener = match take bind_result {
        success(value) => value,
        failure(error) => {
            if !unavailable(error) { return 1 }
            std.io.print("ipv6-loopback-unavailable\n")
            return 0
        }
    }
    let address = try listener.local_addr()
    var client = try TcpStream.connect_timeout(address, from_millis(1000u64))
    let accepted = try listener.accept()
    var server = accepted.0
    try client.set_read_timeout(present(from_millis(2000u64)))
    try server.set_read_timeout(present(from_millis(2000u64)))
    try server.set_write_timeout(present(from_millis(2000u64)))
    try client.write_all("v6-tcp".as_bytes())
    var bytes = [0u8; 16]
    try server.read_exact(bytes.split_at_mut(6usize).0)
    if bytes[0usize] != 118u8 || !accepted.1.ip.is_loopback() { return 2 }
    try server.write_all("ack".as_bytes())
    try client.read_exact(bytes.split_at_mut(3usize).0)
    if bytes[0usize] != 97u8 || bytes[1usize] != 99u8 || bytes[2usize] != 107u8 { return 3 }

    let receiver = try std.net.udp_bind(
        std.net.socket_addr_v6(std.net.ipv6_localhost(), 0u16, 0u32, 0u32)
    )
    let sender = try std.net.udp_bind(
        std.net.socket_addr_v6(std.net.ipv6_localhost(), 0u16, 0u32, 0u32)
    )
    let receive_address = try receiver.local_addr()
    let sender_address = try sender.local_addr()
    try sender.set_read_timeout(present(from_millis(1000u64)))
    try receiver.set_read_timeout(present(from_millis(1000u64)))
    if try sender.send_to("v6-udp".as_bytes(), receive_address) != 6usize { return 4 }
    let packet = try receiver.recv_from(bytes)
    if packet.0 != 6usize || bytes[0usize] != 118u8 ||
        packet.1.port != sender_address.port { return 5 }
    match packet.1.ip {
        IpAddr.V6(ip) => { if !ip.is_loopback() { return 6 } },
        IpAddr.V4(_) => { return 7 }
    }
    if try receiver.send_to("ack".as_bytes(), packet.1) != 3usize { return 8 }
    let reply = try sender.recv_from(bytes)
    if reply.0 != 3usize || bytes[0usize] != 97u8 ||
        reply.1.port != receive_address.port { return 9 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
