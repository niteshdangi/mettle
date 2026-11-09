// profiles: debug release
import core.convert.From
import core.cmp.{Ordering, PartialEq, PartialOrd}
import core.fmt.Debug
import core.ops.{BitAndAssign, BitOrAssign}
import std.net.{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6}

fn debug<T: Debug>(read value: T): Unit {}

fn main(): i32 {
    if Ipv4Addr.BITS != 32u32 || Ipv6Addr.BITS != 128u32 { return 1 }
    let v4 = Ipv4Addr.(From<[u8; 4]>).from([192u8, 0u8, 2u8, 1u8])
    let v4_from_bits = Ipv4Addr.(From<u32>).from(v4.to_bits())
    let v6 = Ipv6Addr.(From<[u8; 16]>).from([
        0x20u8, 0x01u8, 0x0du8, 0xb8u8, 0u8, 0u8, 0u8, 0u8,
        0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8
    ])
    let v6_from_bits = Ipv6Addr.(From<u128>).from(v6.to_bits())
    let v6_from_segments = Ipv6Addr.(From<[u16; 8]>).from(v6.segments())
    let v4_input = v4
    let ip4 = IpAddr.(From<Ipv4Addr>).from(v4_input)
    let ip6 = IpAddr.(From<[u8; 16]>).from(v6.octets())
    let ip4_from_octets = IpAddr.(From<[u8; 4]>).from(v4.octets())
    let ip6_from_segments = IpAddr.(From<[u16; 8]>).from(v6.segments())
    debug(read v4)
    debug(read v6)
    debug(read ip4)
    if v4_from_bits != v4 || v6_from_bits != v6 || v6_from_segments != v6 {
        return 2
    }
    if ip4 != IpAddr.V4(v4) || ip6 != IpAddr.V6(v6) ||
       ip4_from_octets != ip4 || ip6_from_segments != ip6 || !(ip4 < ip6) ||
       IpAddr.(PartialOrd<Ipv4Addr>).partial_cmp(ip4, v4) != present(Ordering.Equal) ||
       IpAddr.(PartialOrd<Ipv6Addr>).partial_cmp(ip4, v6) != present(Ordering.Less) ||
       ip6.partial_cmp(v4) != present(Ordering.Greater) ||
       ip6.partial_cmp(v6) != present(Ordering.Equal) {
        return 3
    }
    let addr4 = SocketAddr.V4(SocketAddrV4.new(v4, 80u16))
    let addr6 = SocketAddr.V6(SocketAddrV6.new(v6, 443u16, 9u32, 12u32))
    debug(read addr4)
    if addr4.ip != ip4 || addr4.port != 80u16 { return 4 }
    if addr6.ip != ip6 || addr6.port != 443u16 ||
       addr6.flowinfo != 9u32 || addr6.scope_id != 12u32 {
        return 5
    }
    if SocketAddr.(From<(IpAddr, u16)>).from((ip4, 8080u16)).port != 8080u16 {
        return 6
    }
    if SocketAddr.(From<(Ipv4Addr, u16)>).from((v4, 8080u16)).ip != ip4 {
        return 7
    }
    let from6 = SocketAddr.(From<(Ipv6Addr, u16)>).from((v6, 443u16))
    if from6.ip != ip6 || from6.port != 443u16 { return 7 }
    if SocketAddr.(From<SocketAddrV4>).from(SocketAddrV4.new(v4, 80u16)) != addr4 ||
       SocketAddr.(From<SocketAddrV6>).from(SocketAddrV6.new(v6, 443u16, 9u32, 12u32)) != addr6 {
        return 8
    }
    var bit_and = v6
    let and_mask = Ipv6Addr.from_segments([65535u16, 65535u16, 65535u16, 65535u16,
                                            65535u16, 65535u16, 65535u16, 65534u16])
    bit_and &= read and_mask
    if bit_and != Ipv6Addr.from_segments([8193u16, 3512u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16]) {
        return 9
    }
    var bit_and_owned = v6
    bit_and_owned &= and_mask
    if bit_and_owned != bit_and { return 11 }
    var bit_or = Ipv6Addr.from_segments([0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16])
    let or_mask = Ipv6Addr.from_segments([0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 2u16])
    bit_or |= read or_mask
    if bit_or != Ipv6Addr.from_segments([0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 3u16]) {
        return 10
    }
    var bit_or_owned = Ipv6Addr.from_segments([0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16])
    bit_or_owned |= or_mask
    if bit_or_owned != bit_or { return 12 }
    0
}
