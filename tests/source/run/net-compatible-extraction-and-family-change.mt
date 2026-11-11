// profiles: debug release
import std.net

fn main(): i32 {
    if net.ipv6_unspecified().to_ipv4() != present(net.unspecified()) { return 1 }
    if net.ipv6_localhost().to_ipv4() != present(net.ipv4(0u8, 0u8, 0u8, 1u8)) { return 2 }
    var address = net.socket_addr_v6(net.ipv6_localhost(), 80u16, 7u32, 9u32)
    address.set_ip(net.IpAddr.V4(net.localhost()))
    if address != net.socket_addr(net.localhost(), 80u16) { return 3 }
    address.set_ip(net.IpAddr.V6(net.ipv6_unspecified()))
    if address.flowinfo != 0u32 || address.scope_id != 0u32 { return 4 }
    0
}
