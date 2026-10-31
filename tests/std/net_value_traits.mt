// IP address constants, ordering, hashing, bit operators and conversions.
import core.convert.From
import core.hash.hash_one
import core.clone.Clone
import std.net.{Ipv4Addr, Ipv6Addr, IpAddr, SocketAddr}

fn main(): i32 {
    if Ipv4Addr.BITS != 32u32 || Ipv6Addr.BITS != 128u32 { return 1 }
    if !Ipv4Addr.LOCALHOST.is_loopback() || !Ipv4Addr.UNSPECIFIED.is_unspecified() { return 2 }
    if !Ipv4Addr.BROADCAST.is_broadcast() || Ipv4Addr.LOCALHOST.octets()[0usize] != 127u8 { return 3 }
    if !Ipv6Addr.LOCALHOST.is_loopback() || !Ipv6Addr.UNSPECIFIED.is_unspecified() { return 4 }

    let a = Ipv4Addr.new(10u8, 0u8, 0u8, 1u8)
    let b = Ipv4Addr.new(10u8, 0u8, 0u8, 2u8)
    if a == b || !(a < b) || a != a.clone() { return 5 }
    if hash_one(read a) != hash_one(read Ipv4Addr.new(10u8, 0u8, 0u8, 1u8)) { return 6 }
    let mask = Ipv4Addr.new(255u8, 255u8, 255u8, 0u8)
    if (a & mask) != Ipv4Addr.new(10u8, 0u8, 0u8, 0u8) { return 7 }
    if (a | !mask) != Ipv4Addr.new(10u8, 0u8, 0u8, 255u8) { return 8 }
    var m = a
    m &= mask
    m |= Ipv4Addr.new(0u8, 0u8, 0u8, 9u8)
    if m != Ipv4Addr.new(10u8, 0u8, 0u8, 9u8) { return 9 }

    let x = Ipv6Addr.LOCALHOST
    let y = Ipv6Addr.new(0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 2u16)
    if x == y || !(x < y) || x != x.clone() { return 10 }
    if hash_one(read x) != hash_one(read Ipv6Addr.LOCALHOST) { return 11 }
    if (x | y) != Ipv6Addr.new(0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 3u16) { return 12 }
    if (!Ipv6Addr.UNSPECIFIED & x) != x { return 13 }

    if Ipv4Addr.from(167772161u32) != a || u32.from(a) != 167772161u32 { return 14 }
    if Ipv4Addr.from([10u8, 0u8, 0u8, 1u8]) != a { return 15 }
    if u128.from(Ipv6Addr.from(5u128)) != 5u128 { return 16 }
    if IpAddr.from(a) == IpAddr.from(x) || !(IpAddr.from(a) < IpAddr.from(x)) { return 17 }
    let socket = SocketAddr.from((a, 80u16))
    if socket.port() != 80u16 || socket != SocketAddr.new(IpAddr.from(a), 80u16) { return 18 }
    if !(socket < SocketAddr.new(IpAddr.from(a), 81u16)) { return 19 }
    0
}
