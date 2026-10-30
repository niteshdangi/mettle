import core.fmt.{Debug, Display, Error, buffer_writer, formatter, spec, written_text}
import core.text.Text
import std.net.{Ipv6Addr, SocketAddr, ipv6}
import std.io.ErrorKind

fn render<T: Display>(value: read T, buffer: mut [u8]): usize throws Error {
    var writer = buffer_writer(mut buffer)
    var output = formatter(mut writer, spec())
    try value.fmt(mut output)
    writer.len()
}

fn render_debug<T: Debug>(value: read T, buffer: mut [u8]): usize throws Error {
    var writer = buffer_writer(mut buffer)
    var output = formatter(mut writer, spec())
    try value.fmt(mut output)
    writer.len()
}

fn equals<T: Display>(value: read T, expected: read Text, buffer: mut [u8]): bool throws Error {
    let length = try render(read value, mut buffer)
    match written_text(read buffer, length) {
        present(text) => text == expected,
        none => false
    }
}

fn run(): i32 throws Error {
    var buffer = [0u8; 128]
    let zero = try Ipv6Addr.parse("::")
    if !equals(read zero, "::", mut buffer) { return 1 }
    let made = ipv6(0x2001u16, 0x0db8u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16)
    if !equals(read made, "2001:db8::1", mut buffer) { return 2 }
    let loopback = ipv6(0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16)
    if !Ipv6Addr.localhost().same(loopback) { return 3 }
    if !Ipv6Addr.unspecified().is_unspecified() { return 4 }
    let one = try std.net.parse_ipv6("0:0:0:0:0:0:0:1")
    if !equals(read one, "::1", mut buffer) { return 5 }
    let longest = try std.net.parse_ipv6("2001:0:0:1:0:0:0:1")
    if !equals(read longest, "2001:0:0:1::1", mut buffer) { return 6 }
    let tie = try std.net.parse_ipv6("2001:0:0:1:0:0:1:1")
    if !equals(read tie, "2001::1:0:0:1:1", mut buffer) { return 7 }
    let length = try render_debug(read tie, mut buffer)
    match written_text(read buffer, length) {
        present(text) => { if text != "2001::1:0:0:1:1" { return 8 } },
        none => { return 9 }
    }

    let v6 = try SocketAddr.parse("[::1]:8080")
    if !equals(read v6, "[::1]:8080", mut buffer) { return 10 }
    let scoped = try std.net.parse_socket_addr("[fe80::1%12]:443")
    if !equals(read scoped, "[fe80::1%12]:443", mut buffer) { return 11 }
    if scoped.scope_id != 12u32 || scoped.flowinfo != 0u32 { return 12 }
    let v4 = try std.net.parse_socket_addr("127.0.0.1:80")
    if !equals(read v4, "127.0.0.1:80", mut buffer) { return 13 }
    let mapped = try std.net.parse_ipv6("::ffff:192.0.2.1")
    if !equals(read mapped, "::ffff:192.0.2.1", mut buffer) { return 14 }
    match capture std.net.parse_ipv6(":::") {
        success(value) => { return 15 },
        failure(error) => { if !error.kind().is(ErrorKind.InvalidInput) { return 16 } }
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
