// IP and socket address values: constructors, bit and octet views, classification and mapping.
import std.io.{Error}
import std.net.{Ipv4Addr, Ipv6Addr, IpAddr, SocketAddr, SocketAddrV4, SocketAddrV6}

fn run(): i32 throws Error {
    let a = Ipv4Addr.new(192u8, 0u8, 2u8, 17u8)
    let octets = a.octets()
    if octets[0usize] != 192u8 || octets[3usize] != 17u8 { return 1 }
    if Ipv4Addr.from_octets(octets).to_bits() != a.to_bits() { return 2 }
    if Ipv4Addr.from_bits(3221226001u32).same(a) == false { return 3 }
    if !Ipv4Addr.new(127u8, 1u8, 2u8, 3u8).is_loopback() { return 4 }
    if !Ipv4Addr.new(0u8, 0u8, 0u8, 0u8).is_unspecified() { return 5 }
    if !Ipv4Addr.new(255u8, 255u8, 255u8, 255u8).is_broadcast() { return 6 }
    if !Ipv4Addr.new(224u8, 0u8, 0u8, 1u8).is_multicast() { return 7 }
    if !Ipv4Addr.new(169u8, 254u8, 1u8, 1u8).is_link_local() { return 8 }
    if !Ipv4Addr.new(10u8, 0u8, 0u8, 1u8).is_private() || !Ipv4Addr.new(172u8, 16u8, 0u8, 1u8).is_private() { return 9 }
    if !Ipv4Addr.new(192u8, 0u8, 2u8, 1u8).is_documentation() || a.is_private() { return 10 }
    let mapped = a.to_ipv6_mapped()
    let compatible = a.to_ipv6_compatible()
    match mapped.to_ipv4_mapped() {
        present(v4) => { if !v4.same(a) { return 11 } },
        none => { return 11 }
    }
    match compatible.to_ipv4_compatible() {
        present(v4) => { if !v4.same(a) { return 11 } },
        none => { return 11 }
    }

    let b = Ipv6Addr.new(0x2001u16, 0xdb8u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16)
    let segments = b.segments()
    if segments[0usize] != 0x2001u16 || segments[7usize] != 1u16 { return 12 }
    if Ipv6Addr.from_segments(segments).to_bits() != b.to_bits() { return 13 }
    if Ipv6Addr.from_octets(b.octets()).to_bits() != b.to_bits() { return 14 }
    if !Ipv6Addr.localhost().is_loopback() || !Ipv6Addr.unspecified().is_unspecified() { return 15 }
    if !Ipv6Addr.new(0xff02u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16).is_multicast() { return 16 }
    if !Ipv6Addr.new(0xfe80u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16).is_unicast_link_local() { return 17 }
    if !Ipv6Addr.new(0xfd00u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16).is_unique_local() { return 18 }
    if Ipv6Addr.from_bits(b.to_bits()).same(b) == false { return 19 }
    let v4_again = mapped.to_ipv4()
    match v4_again {
        present(v4) => { if !v4.same(a) { return 20 } },
        none => { return 20 }
    }
    match mapped.to_canonical() {
        IpAddr.V4(v4) => { if !v4.same(a) { return 21 } },
        IpAddr.V6(_) => { return 21 }
    }

    let v4ip = IpAddr.V4(a)
    if !v4ip.is_ipv4() || v4ip.is_ipv6() || !v4ip.same(IpAddr.V4(a)) { return 22 }
    let v6ip = IpAddr.V6(b)
    if v6ip.is_ipv4() || !v6ip.is_ipv6() || v6ip.is_loopback() { return 23 }
    if !IpAddr.V6(Ipv6Addr.localhost()).is_loopback() || !IpAddr.V4(Ipv4Addr.new(127u8, 0u8, 0u8, 9u8)).is_loopback() { return 24 }
    if !IpAddr.V6(Ipv6Addr.unspecified()).is_unspecified() || !IpAddr.V4(Ipv4Addr.new(224u8, 0u8, 0u8, 9u8)).is_multicast() { return 25 }
    if !IpAddr.V6(mapped).to_canonical().same(IpAddr.V4(a)) { return 26 }

    let socket = SocketAddr.new(v4ip, 8080u16)
    if socket.port() != 8080u16 || !socket.is_ipv4() || socket.is_ipv6() { return 27 }
    var moved = socket
    moved.set_port(9090u16)
    moved.set_ip(v6ip)
    if moved.port() != 9090u16 || !moved.is_ipv6() || !moved.ip().same(v6ip) { return 28 }
    if socket.same(moved) { return 29 }

    var v4 = SocketAddrV4.new(a, 53u16)
    v4.set_port(5353u16)
    if v4.port() != 5353u16 || !v4.ip().same(a) { return 30 }
    if v4.to_socket_addr().port() != 5353u16 { return 31 }
    var v6 = SocketAddrV6.new(b, 443u16, 7u32, 3u32)
    v6.set_scope_id(4u32)
    if v6.scope_id() != 4u32 || v6.flowinfo() != 7u32 || v6.port() != 443u16 { return 32 }
    v6.set_flowinfo(0u32)
    if v6.to_socket_addr().flowinfo != 0u32 { return 33 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
