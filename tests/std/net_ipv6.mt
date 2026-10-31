import std.io.{Error, ErrorKind, Reader, Writer}
import std.net.{IpAddr, TcpStream}
import std.time.from_millis

fn unavailable(error: Error): bool {
    error.kind().is(ErrorKind.AddrNotAvailable) ||
        error.raw_os_error() == present(47) ||
        error.raw_os_error() == present(97)
}

fn run(): i32 throws Error {
    let private = std.net.Ipv4Addr.from_octets([10u8, 1u8, 2u8, 3u8])
    if !private.is_private() || private.to_bits() != 167838211u32 { return 10 }
    match private.to_ipv6_mapped().to_ipv4_mapped() {
        present(address) => { if !address.same(private) { return 10 } },
        none => { return 10 }
    }
    let ip_value = IpAddr.V4(private)
    if !ip_value.is_ipv4() || ip_value.is_ipv6() || ip_value.is_unspecified() { return 14 }
    let compatibility = private.to_ipv6_compatible()
    match compatibility.to_ipv4_compatible() {
        present(address) => { if !address.same(private) { return 15 } },
        none => { return 15 }
    }
    let link_local = std.net.Ipv4Addr.new(169u8, 254u8, 1u8, 2u8)
    if !link_local.is_link_local() || link_local.is_private() { return 11 }
    let multicast = std.net.Ipv6Addr.from_segments(
        [65535u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16]
    )
    if !multicast.is_multicast() { return 12 }
    let address6 = std.net.SocketAddrV6.new(multicast, 8000u16, 3u32, 4u32)
    if address6.port() != 8000u16 || address6.flowinfo() != 3u32 ||
       address6.scope_id() != 4u32 { return 16 }
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
    var listener_clone = try listener.try_clone()
    try listener_clone.set_nonblocking(true)
    try listener_clone.set_nonblocking(false)
    let address = try listener.local_addr()
    var client = try TcpStream.connect_timeout(address, from_millis(1000u64))
    var client_clone = try client.try_clone()
    try client_clone.set_nonblocking(true)
    try client_clone.set_nonblocking(false)
    try client.set_nodelay(true)
    if !try client.nodelay() { return 17 }
    try client.set_nodelay(false)
    if try client.nodelay() { return 18 }
    match try client.take_error() { present(error) => { return 19 }, none => {} }
    match try listener.take_error() { present(error) => { return 20 }, none => {} }
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

    let inbox = try std.net.udp_bind(
        std.net.socket_addr_v6(std.net.ipv6_localhost(), 0u16, 0u32, 0u32)
    )
    let sender = try std.net.udp_bind(
        std.net.socket_addr_v6(std.net.ipv6_localhost(), 0u16, 0u32, 0u32)
    )
    var sender_clone = try sender.try_clone()
    try sender_clone.set_nonblocking(true)
    try sender_clone.set_nonblocking(false)
    match try inbox.take_error() { present(error) => { return 21 }, none => {} }
    let receive_address = try inbox.local_addr()
    let sender_address = try sender.local_addr()
    try sender.set_read_timeout(present(from_millis(1000u64)))
    try inbox.set_read_timeout(present(from_millis(1000u64)))
    if try sender.send_to("v6-udp".as_bytes(), receive_address) != 6usize { return 4 }
    let packet = try inbox.recv_from(bytes)
    if packet.0 != 6usize || bytes[0usize] != 118u8 ||
        packet.1.port != sender_address.port { return 5 }
    match packet.1.ip {
        IpAddr.V6(ip) => { if !ip.is_loopback() { return 6 } },
        IpAddr.V4(_) => { return 7 }
    }
    if try inbox.send_to("ack".as_bytes(), packet.1) != 3usize { return 8 }
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
