// Address value traits: equality, ordering, hashing, bit operations, FromStr,
// From and Display for IPv4, IPv6, IpAddr and SocketAddr.
import core.cmp.{PartialEq, Ordering}
import core.convert.From
import core.fmt.{Display, buffer_writer, formatter, spec, written_text}
import core.hash.hash_one
import core.text.{FromStr, Text}
import std.io.{Error, ErrorKind}
import std.net.{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr}

fn render<T: Display>(value: read T, buffer: mut [u8]): usize throws core.fmt.Error {
    var writer = buffer_writer(mut buffer)
    var output = formatter(mut writer, spec())
    try value.fmt(mut output)
    writer.len()
}

fn equals<T: Display>(value: read T, expected: read Text, buffer: mut [u8]): bool {
    let length = match take capture render(read value, mut buffer) {
        success(length) => length,
        failure(error) => { return false }
    }
    match written_text(read buffer, length) {
        present(text) => text == expected,
        none => false
    }
}

fn run(): i32 throws Error {
    var buffer = [0u8; 128]
    let low = Ipv4Addr.new(10u8, 0u8, 0u8, 1u8)
    let high = Ipv4Addr.new(10u8, 0u8, 0u8, 2u8)
    if !equals(read low, "10.0.0.1", mut buffer) { return 1 }

    // Equality and ordering follow the address bytes.
    if !(low == Ipv4Addr.new(10u8, 0u8, 0u8, 1u8)) || low == high { return 2 }
    if !low.cmp(high).is_lt() || !high.cmp(low).is_gt() { return 3 }
    match low.partial_cmp(high) {
        present(order) => { if !order.is_lt() { return 4 } },
        none => { return 4 }
    }
    if low.cmp(low) != Ordering.Equal { return 5 }

    // Bit operations on IPv4 apply to the 32-bit representation.
    let mask = Ipv4Addr.new(255u8, 255u8, 255u8, 0u8)
    let host = Ipv4Addr.new(192u8, 0u8, 2u8, 17u8)
    if !((host & mask) == Ipv4Addr.new(192u8, 0u8, 2u8, 0u8)) { return 6 }
    if !((host | mask) == Ipv4Addr.new(255u8, 255u8, 255u8, 17u8)) { return 7 }
    if !((!std.net.unspecified()) == Ipv4Addr.new(255u8, 255u8, 255u8, 255u8)) { return 8 }
    var accumulated = host
    accumulated &= mask
    if accumulated.to_bits() != 3221225984u32 { return 9 }
    accumulated |= Ipv4Addr.new(0u8, 0u8, 0u8, 1u8)
    if accumulated.to_bits() != 3221225985u32 { return 10 }

    // Hashing agrees with equality.
    if hash_one(read low) != hash_one(read Ipv4Addr.new(10u8, 0u8, 0u8, 1u8)) { return 11 }

    // FromStr and From build the same addresses as the inherent constructors.
    let parsed = try Ipv4Addr.(FromStr).from_str("10.0.0.1")
    if parsed != low { return 12 }
    let from_octets = Ipv4Addr.(From<[u8; 4]>).from([10u8, 0u8, 0u8, 1u8])
    if from_octets != low { return 13 }
    if Ipv4Addr.(From<u32>).from(167772161u32) != low { return 14 }

    // IPv6: display, ordering and bit operations on the 128-bit value.
    let loopback = Ipv6Addr.localhost()
    if !equals(read loopback, "::1", mut buffer) { return 15 }
    let v6 = try Ipv6Addr.(FromStr).from_str("2001:db8::1")
    if !(v6 > loopback) { return 16 }
    match v6.partial_cmp(loopback) {
        present(order) => { if !order.is_gt() { return 17 } },
        none => { return 17 }
    }
    if !((!std.net.ipv6_unspecified()) ==Ipv6Addr.from_bits(340282366920938463463374607431768211455u128)) {
        return 18
    }
    let prefix = Ipv6Addr.from_bits(0xffff0000000000000000000000000000u128)
    if !((v6 & prefix) == Ipv6Addr.from_bits(0x20010000000000000000000000000000u128)) { return 19 }
    if !((loopback | prefix) == Ipv6Addr.from_bits(0xffff0000000000000000000000000001u128)) { return 20 }
    if hash_one(read v6) != hash_one(read Ipv6Addr.(From<[u16; 8]>).from([8193u16, 3512u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16])) {
        return 21
    }

    // IpAddr: IPv4 sorts before IPv6, and each family orders by its bytes.
    let v4_address = IpAddr.(From<Ipv4Addr>).from(Ipv4Addr.new(10u8, 0u8, 0u8, 1u8))
    let v6_address = IpAddr.(From<Ipv6Addr>).from(v6)
    if !v4_address.cmp(v6_address).is_lt() || !v6_address.cmp(v4_address).is_gt() { return 22 }
    if !(IpAddr.(From<Ipv4Addr>).from(Ipv4Addr.new(10u8, 0u8, 0u8, 2u8)).cmp(v4_address).is_gt()) { return 23 }
    if v4_address != (try IpAddr.parse("10.0.0.1")) { return 24 }
    let from_text = try IpAddr.(FromStr).from_str("2001:db8::1")
    if from_text != v6_address { return 25 }
    if !equals(read from_text, "2001:db8::1", mut buffer) { return 26 }

    // SocketAddr: display with brackets and scope, and ordering by address then port.
    let scoped = try SocketAddr.(FromStr).from_str("[fe80::1%12]:443")
    if !equals(read scoped, "[fe80::1%12]:443", mut buffer) { return 27 }
    let a = std.net.socket_addr(Ipv4Addr.new(10u8, 0u8, 0u8, 1u8), 80u16)
    let b = std.net.socket_addr(Ipv4Addr.new(10u8, 0u8, 0u8, 1u8), 443u16)
    let c = std.net.socket_addr(Ipv4Addr.new(10u8, 0u8, 0u8, 2u8), 1u16)
    if !a.cmp(b).is_lt() || !b.cmp(c).is_lt() || !c.cmp(a).is_gt() { return 28 }
    if a == b || a != std.net.socket_addr(Ipv4Addr.new(10u8, 0u8, 0u8, 1u8), 80u16) { return 29 }
    if hash_one(read a) != hash_one(read std.net.socket_addr(Ipv4Addr.new(10u8, 0u8, 0u8, 1u8), 80u16)) { return 30 }
    let text_socket = try SocketAddr.(FromStr).from_str("10.0.0.2:443")
    if text_socket != std.net.socket_addr(Ipv4Addr.new(10u8, 0u8, 0u8, 2u8), 443u16) { return 31 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
