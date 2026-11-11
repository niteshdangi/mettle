import alloc.string.String
import core.iter.{ Copied, Iterator }
import core.outcome
import core.slice.SliceIter
import std.io.{ Error, ErrorKind, Reader, Writer }
import std.net.{ IpAddr, SocketAddr, TcpListener, TcpStream, ToSocketAddrs, UdpSocket }
import std.time.from_millis

type Candidates { addresses: [SocketAddr; 2] }

extend Candidates implements ToSocketAddrs {
    type Iter<region r> = Copied<region r, SocketAddr, SliceIter<region r, SocketAddr>>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Copied<region r, SocketAddr, SliceIter<region r, SocketAddr>> throws Error {
        self.addresses.iter().copied()
    }
}

fn invalid_input<T>(take result: Outcome<T, Error>): bool {
    match take result {
        success(_) => false,
        failure(error) => error.kind().is(ErrorKind.InvalidInput)
    }
}

fn run(): i32 throws Error {
    let loopback = std.net.localhost()
    let local4 = std.net.socket_addr(loopback, 0u16)
    let local6 = std.net.socket_addr_v6(std.net.ipv6_localhost(), 0u16, 0u32, 0u32)
    let v4 = std.net.SocketAddrV4.new(loopback, 0u16)
    let v6 = std.net.SocketAddrV6.new(std.net.ipv6_localhost(), 0u16, 0u32, 0u32)
    let bound4 = try UdpSocket.bind(read v4)
    let bound6 = try UdpSocket.bind(v6)
    if !(try bound4.local_addr()).ip.is_ipv4() ||
        !(try bound6.local_addr()).ip.is_ipv6() { return 1 }
    let tuple4 = try UdpSocket.bind((loopback, 0u16))
    let tuple6 = try UdpSocket.bind((std.net.ipv6_localhost(), 0u16))
    let tuple_ip = try UdpSocket.bind((IpAddr.V4(loopback), 0u16))
    if !(try tuple4.local_addr()).ip.is_loopback() ||
        !(try tuple6.local_addr()).ip.is_loopback() ||
        !(try tuple_ip.local_addr()).ip.is_loopback() { return 2 }
    let text4 = try UdpSocket.bind("127.0.0.1:0")
    let text6 = try UdpSocket.bind("[::1]:0")
    let owned_text = String("127.0.0.1:0")
    let owned = try UdpSocket.bind(owned_text)
    let host = try UdpSocket.bind(("localhost", 0u16))
    let owned_host = try UdpSocket.bind((String("localhost"), 0u16))
    if !(try text4.local_addr()).ip.is_loopback() ||
        !(try text6.local_addr()).ip.is_loopback() ||
        !(try owned.local_addr()).ip.is_loopback() ||
        !(try host.local_addr()).ip.is_loopback() ||
        !(try owned_host.local_addr()).ip.is_loopback() { return 3 }
    let host_port = try UdpSocket.bind("localhost:0")
    if !(try host_port.local_addr()).ip.is_loopback() { return 4 }
    let empty: [SocketAddr; 0] = []
    let empty_slice: read [SocketAddr] = read empty
    if !invalid_input(capture UdpSocket.bind(empty_slice)) ||
        !invalid_input(capture TcpListener.bind(empty)) ||
        !invalid_input(capture TcpStream.connect(empty)) { return 5 }
    if !invalid_input(capture UdpSocket.bind("localhost")) ||
        !invalid_input(capture UdpSocket.bind("localhost:65536")) ||
        !invalid_input(capture UdpSocket.bind("[::1:0")) ||
        !invalid_input(capture UdpSocket.bind(("local\0host", 0u16))) { return 6 }

    let no_scope = std.net.socket_addr_v6(
        std.net.ipv6(65152u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16),
        0u16, 0u32, 0u32
    )
    let rebound = try UdpSocket.bind([no_scope, local4])
    if !(try rebound.local_addr()).ip.is_loopback() { return 23 }

    let first_listener = try TcpListener.bind((loopback, 0u16))
    let occupied = try first_listener.local_addr()
    let choices = Candidates([occupied, local4])
    let listener = try TcpListener.bind(choices)
    let address = try listener.local_addr()
    if address.port == 0u16 || address.port == occupied.port { return 7 }
    let mut_addresses = [occupied, address]
    let address_slice: read [SocketAddr] = read mut_addresses
    var addresses = try address_slice.to_socket_addrs()
    if !match addresses.next() {
        present(value) => value.same(occupied),
        none => false
    } { return 8 }
    if !match addresses.next() {
        present(value) => value.same(address),
        none => false
    } || addresses.next().is_present() { return 9 }
    var client = try TcpStream.connect([local4, address])
    let accepted = try listener.accept()
    var server = accepted.0
    try server.set_read_timeout(present(from_millis(1000u64)))
    try client.write_all("candidate".as_bytes())
    var received = [0u8; 9]
    try server.read_exact(received)
    if received[0usize] != 99u8 || received[8usize] != 101u8 { return 10 }

    let inbox = try UdpSocket.bind(local4)
    let destination = try inbox.local_addr()
    let sender = try UdpSocket.bind(local4)
    let source = try sender.local_addr()
    try inbox.set_read_timeout(present(from_millis(1000u64)))
    if !invalid_input(capture sender.connect(empty)) ||
        !invalid_input(capture sender.send_to("x".as_bytes(), empty)) { return 11 }
    try sender.connect([local6, destination])
    if !(try sender.peer_addr()).same(destination) { return 12 }
    if try sender.send_to("x".as_bytes(), (loopback, destination.port)) != 1usize {
        return 13
    }
    let packet = try inbox.peek_from(received)
    if packet.0 != 1usize || !packet.1.same(source) { return 14 }
    if (try inbox.recv_from(received)).0 != 1usize || received[0usize] != 120u8 {
        return 15
    }
    match take capture sender.send_to("wrong".as_bytes(), [local6, destination]) {
        success(_) => { return 16 },
        failure(error) => { if !error.is_os() { return 17 } }
    }
    try inbox.set_nonblocking(true)
    match take capture inbox.recv(received) {
        success(_) => { return 18 },
        failure(error) => {
            if !error.kind().is(ErrorKind.WouldBlock) { return 19 }
        }
    }
    let final_error = match take capture sender.connect(local6) {
        success(_) => { return 20 },
        failure(error) => error
    }
    match take capture sender.connect([local6, local6]) {
        success(_) => { return 21 },
        failure(error) => {
            if error.raw_os_error() != final_error.raw_os_error() { return 22 }
        }
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => {
            std.io.eprint(f"Address input acceptance failed: {error}\n")
            100
        }
    }
}
