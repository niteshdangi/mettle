// Address parsers preserve the address family and IPv6 scope; I/O stays on
// the local loopback interface.
import std.io.{Error, ErrorKind, Reader, Writer}
import std.net.{Ipv4Addr, IpAddr, SocketAddrV4, SocketAddrV6, TcpStream}
import std.time.from_millis

fn run(): i32 throws Error {
    let ipv4 = try Ipv4Addr.parse("192.0.2.17")
    if ipv4.octets()[3usize] != 17u8 { return 1 }
    let ip4 = try IpAddr.parse("127.0.0.1")
    if !ip4.is_ipv4() || !ip4.is_loopback() { return 2 }
    let ip6 = try IpAddr.parse("::1")
    if !ip6.is_ipv6() || !ip6.is_loopback() { return 3 }

    let socket4 = try SocketAddrV4.parse("127.0.0.1:0")
    if !socket4.ip().is_loopback() || socket4.port() != 0u16 { return 4 }
    let socket6 = try SocketAddrV6.parse("[fe80::1%12]:443")
    if !socket6.ip().is_unicast_link_local() ||
       socket6.scope_id() != 12u32 || socket6.port() != 443u16 {
        return 5
    }

    let wrong_v4 = capture SocketAddrV4.parse("[::1]:80")
    match take wrong_v4 {
        success(address) => { return 6 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 7 }
        }
    }
    let wrong_v6 = capture SocketAddrV6.parse("127.0.0.1:80")
    match take wrong_v6 {
        success(address) => { return 8 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 9 }
        }
    }
    let bad_port = capture SocketAddrV4.parse("127.0.0.1:65536")
    if bad_port.is_success() { return 10 }
    let bad_ip = capture Ipv4Addr.parse("127.00.0.1")
    if bad_ip.is_success() { return 11 }

    var listener = try std.net.tcp_listen(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    let address = try listener.local_addr()
    if !address.ip.is_loopback() || address.port == 0u16 { return 12 }
    var client = try TcpStream.connect_timeout(address, from_millis(1000u64))
    var accepted = try listener.accept()
    var server = accepted.0
    if !accepted.1.ip.is_loopback() { return 13 }
    try server.write_all("i13".as_bytes())
    var response = [0u8; 3]
    try client.read_exact(response)
    if response[0usize] != 105u8 || response[1usize] != 49u8 ||
       response[2usize] != 51u8 {
        return 14
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
