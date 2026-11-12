import core.cmp.PartialEq
import core.outcome
import core.slice
import std.io.{Error, ErrorKind}
import std.net.{IpAddr, Ipv4Addr, Ipv6Addr, TcpListener, TcpStream, UdpSocket}
import std.time.{Duration, from_nanos, from_secs}

extern "C" {
    unsafe fn if_nametoindex(name: ptr<read u8>): u32;
}

fn invalid<T>(take result: Outcome<T, Error>, os: bool): bool {
    match take result {
        success(_) => false,
        failure(error) => error.kind().is(ErrorKind.InvalidInput) && error.is_os() == os
    }
}

fn os_error<T>(take result: Outcome<T, Error>): bool {
    match take result {
        success(_) => false,
        failure(error) => error.is_os() && error.raw_os_error().is_present()
    }
}

fn configured(value: Duration?): bool {
    match value {
        present(duration) => !duration.is_zero(),
        none => false
    }
}

fn tcp_options(ip: IpAddr): i32 throws Error {
    let listener = try TcpListener.bind(std.net.socket_addr_ip(ip, 0u16))
    let listener_clone = try listener.try_clone()
    try listener.set_ttl(1u32)
    if try listener_clone.ttl() != 1u32 { return 1 }
    try listener_clone.set_ttl(255u32)
    if try listener.ttl() != 255u32 { return 2 }
    if !invalid(capture listener.set_ttl(256u32), true) ||
       !invalid(capture listener_clone.set_ttl(4294967295u32), true) {
        return 3
    }
    if try listener.ttl() != 255u32 { return 4 }

    let client = try TcpStream.connect(try listener.local_addr())
    let accepted = try listener.accept()
    let clone = try client.try_clone()
    try client.set_ttl(1u32)
    if try clone.ttl() != 1u32 { return 5 }
    try clone.set_ttl(255u32)
    if try client.ttl() != 255u32 { return 6 }
    if !invalid(capture client.set_ttl(256u32), true) ||
       !invalid(capture clone.set_ttl(4294967295u32), true) {
        return 7
    }
    if try client.ttl() != 255u32 { return 8 }
    if (try client.read_timeout()).is_present() ||
       (try clone.write_timeout()).is_present() { return 9 }
    try client.set_read_timeout(present(from_nanos(1u64)))
    try clone.set_write_timeout(present(from_secs(2u64)))
    let read_limit = try client.read_timeout()
    let write_limit = try client.write_timeout()
    if !configured(read_limit) || !configured(write_limit) ||
       (try clone.read_timeout()) != read_limit ||
       (try clone.write_timeout()) != write_limit ||
       write_limit != present(from_secs(2u64)) { return 10 }
    if !invalid(capture clone.set_read_timeout(present(from_secs(0u64))), false) ||
       !invalid(capture client.set_write_timeout(present(from_secs(0u64))), false) {
        return 11
    }
    if (try client.read_timeout()) != read_limit ||
       (try clone.write_timeout()) != write_limit { return 12 }
    try clone.set_read_timeout(none)
    try client.set_write_timeout(none)
    if (try client.read_timeout()).is_present() ||
       (try clone.write_timeout()).is_present() { return 13 }
    0
}

fn udp_options(ip: IpAddr): i32 throws Error {
    let socket = try UdpSocket.bind(std.net.socket_addr_ip(ip, 0u16))
    let clone = try socket.try_clone()
    try socket.set_ttl(1u32)
    if try clone.ttl() != 1u32 { return 1 }
    try clone.set_ttl(255u32)
    if try socket.ttl() != 255u32 { return 2 }
    if !invalid(capture socket.set_ttl(256u32), true) ||
       !invalid(capture clone.set_ttl(4294967295u32), true) { return 3 }
    if try socket.ttl() != 255u32 { return 4 }
    if (try socket.read_timeout()).is_present() ||
       (try clone.write_timeout()).is_present() { return 5 }
    try socket.set_read_timeout(present(from_nanos(1u64)))
    try clone.set_write_timeout(present(from_secs(2u64)))
    let read_limit = try socket.read_timeout()
    let write_limit = try socket.write_timeout()
    if !configured(read_limit) || !configured(write_limit) ||
       (try clone.read_timeout()) != read_limit ||
       (try clone.write_timeout()) != write_limit ||
       write_limit != present(from_secs(2u64)) { return 6 }
    if !invalid(capture socket.set_read_timeout(present(from_secs(0u64))), false) ||
       !invalid(capture clone.set_write_timeout(present(from_secs(0u64))), false) {
        return 7
    }
    if (try clone.read_timeout()) != read_limit ||
       (try socket.write_timeout()) != write_limit { return 8 }
    try clone.set_read_timeout(none)
    try socket.set_write_timeout(none)
    if (try socket.read_timeout()).is_present() ||
       (try clone.write_timeout()).is_present() { return 9 }

    if ip.is_ipv4() {
        try socket.set_broadcast(true)
        if !(try clone.broadcast()) { return 10 }
        try clone.set_broadcast(false)
        if try socket.broadcast() { return 11 }
        try socket.set_multicast_loop_v4(false)
        if try clone.multicast_loop_v4() { return 12 }
        try clone.set_multicast_loop_v4(true)
        if !(try socket.multicast_loop_v4()) { return 13 }
        try socket.set_multicast_ttl_v4(0u32)
        if try clone.multicast_ttl_v4() != 0u32 { return 14 }
        try clone.set_multicast_ttl_v4(255u32)
        if try socket.multicast_ttl_v4() != 255u32 { return 15 }
        if !invalid(capture socket.set_multicast_ttl_v4(256u32), true) ||
           !invalid(capture clone.set_multicast_ttl_v4(4294967295u32), true) {
            return 16
        }
        if try socket.multicast_ttl_v4() != 255u32 { return 17 }
        if !os_error(capture socket.set_multicast_loop_v6(true)) ||
           !os_error(capture socket.multicast_loop_v6()) { return 18 }
    } else {
        try socket.set_multicast_loop_v6(false)
        if try clone.multicast_loop_v6() { return 19 }
        try clone.set_multicast_loop_v6(true)
        if !(try socket.multicast_loop_v6()) { return 20 }
    }
    0
}

fn membership_v4(): i32 throws Error {
    let socket = try UdpSocket.bind(std.net.socket_addr(Ipv4Addr.UNSPECIFIED, 0u16))
    let group = Ipv4Addr.new(239u8, 255u8, 0u8, 114u8)
    if !os_error(capture socket.join_multicast_v4(Ipv4Addr.LOCALHOST, Ipv4Addr.LOCALHOST)) ||
       !os_error(capture socket.leave_multicast_v4(group, Ipv4Addr.LOCALHOST)) {
        return 1
    }
    try socket.join_multicast_v4(group, Ipv4Addr.LOCALHOST)
    {
        let clone = try socket.try_clone()
        if !os_error(capture clone.join_multicast_v4(group, Ipv4Addr.LOCALHOST)) {
            return 2
        }
        try clone.leave_multicast_v4(group, Ipv4Addr.LOCALHOST)
        if !os_error(capture socket.leave_multicast_v4(group, Ipv4Addr.LOCALHOST)) {
            return 3
        }
        try clone.join_multicast_v4(group, Ipv4Addr.LOCALHOST)
    }
    try socket.leave_multicast_v4(group, Ipv4Addr.LOCALHOST)
    0
}

fn loopback_index(): u32 {
    let linux_name = [108u8, 111u8, 0u8]
    let index = unsafe { if_nametoindex(slice.data(linux_name)) }
    if index != 0u32 { return index }
    let darwin_name = [108u8, 111u8, 48u8, 0u8]
    unsafe { if_nametoindex(slice.data(darwin_name)) }
}

fn membership_v6(): i32 throws Error {
    let socket = try UdpSocket.bind(
        std.net.socket_addr_v6(Ipv6Addr.UNSPECIFIED, 0u16, 0u32, 0u32)
    )
    let index = loopback_index()
    if index == 0u32 { return 1 }
    let group = Ipv6Addr.new(0xff02u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0x114u16)
    if !os_error(capture socket.join_multicast_v6(Ipv6Addr.LOCALHOST, index)) ||
       !os_error(capture socket.leave_multicast_v6(group, index)) { return 2 }
    try socket.join_multicast_v6(group, index)
    {
        let clone = try socket.try_clone()
        if !os_error(capture clone.join_multicast_v6(group, index)) { return 3 }
        try clone.leave_multicast_v6(group, index)
        if !os_error(capture socket.leave_multicast_v6(group, index)) { return 4 }
        try clone.join_multicast_v6(group, index)
    }
    try socket.leave_multicast_v6(group, index)
    let v4 = try UdpSocket.bind(std.net.socket_addr(Ipv4Addr.LOCALHOST, 0u16))
    if !os_error(capture v4.join_multicast_v6(group, index)) ||
       !os_error(capture v4.leave_multicast_v6(group, index)) { return 5 }
    0
}

fn run(): i32 throws Error {
    let v4 = IpAddr.V4(Ipv4Addr.LOCALHOST)
    let v6 = IpAddr.V6(Ipv6Addr.LOCALHOST)
    let tcp4 = try tcp_options(v4)
    if tcp4 != 0 { return tcp4 }
    let tcp6 = try tcp_options(v6)
    if tcp6 != 0 { return 20 + tcp6 }
    let udp4 = try udp_options(v4)
    if udp4 != 0 { return 40 + udp4 }
    let udp6 = try udp_options(v6)
    if udp6 != 0 { return 70 + udp6 }
    let membership4 = try membership_v4()
    if membership4 != 0 { return 100 + membership4 }
    let membership6 = try membership_v6()
    if membership6 != 0 { return 110 + membership6 }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => {
            std.io.eprint(f"network option acceptance failed: {error}\n")
            200
        }
    }
}
