import core.convert.From
import core.fmt.{Debug, buffer_writer, formatter, spec}
import core.iter.Iterator
import core.outcome
import std.io.{Error, ErrorKind, Reader, Writer}
import std.net.{TcpListener, TcpStream, UdpSocket}
import std.sys
import std.time.from_millis

fn debug<T: Debug>(read value: T): Unit {
    var bytes = [0u8; 128]
    var writer = buffer_writer(mut bytes)
    var output = formatter(mut writer, spec())
    match take capture value.fmt(mut output) {
        success(_) => {},
        failure(_) => { panic("socket debug formatting failed") }
    }
    if writer.len() == 0usize { panic("socket debug formatting was empty") }
    var empty = [0u8; 0]
    var full = buffer_writer(mut empty)
    var failing = formatter(mut full, spec())
    match take capture value.fmt(mut failing) {
        success(_) => { panic("socket debug ignored sink failure") },
        failure(_) => {}
    }
}

fn raw_socket(kind: i32): sys.OwnedFd? {
    let fd = unsafe { sys.mettle_rt_sock_new(kind, 4) }
    if fd < 0 { return none }
    present(unsafe { sys.OwnedFd.from_raw_fd(fd) })
}

fn run(): i32 throws Error {
    var listener = try TcpListener.bind(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    debug(read listener)
    let address = try listener.local_addr()
    let listener_copy = try listener.try_clone()
    if !(try listener_copy.local_addr()).same(address) { return 3 }
    if (try listener.take_error()).is_present() { return 12 }
    var client = try TcpStream.connect(address)
    debug(read client)
    let client_address = try client.local_addr()
    if !client_address.ip.is_loopback() { return 13 }
    try client.set_nodelay(true)
    if !(try client.nodelay()) { return 4 }
    try client.set_nodelay(false)
    try client.set_read_timeout(present(from_millis(1000u64)))
    try client.set_write_timeout(present(from_millis(1000u64)))
    try client.set_read_timeout(none)
    try client.set_write_timeout(none)
    try client.set_nonblocking(true)
    try client.set_nonblocking(false)
    let client_copy = try client.try_clone()
    if !(try client_copy.peer_addr()).same(address) { return 5 }
    try client_copy.set_nodelay(true)
    if !(try client.nodelay()) { return 21 }
    try client_copy.set_nodelay(false)
    if try client.nodelay() { return 22 }
    try client_copy.set_nonblocking(true)
    var idle = [0u8; 1]
    match take capture client.peek(mut idle) {
        success(_) => { return 23 },
        failure(error) => {
            if !error.kind().is(ErrorKind.WouldBlock) || !error.is_os() { return 24 }
        }
    }
    try client_copy.set_nonblocking(false)
    match take capture client.set_read_timeout(present(from_millis(0u64))) {
        success(_) => { return 25 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 26 }
        }
    }
    match take capture client.set_write_timeout(present(from_millis(0u64))) {
        success(_) => { return 27 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 28 }
        }
    }
    if (try client.take_error()).is_present() { return 6 }
    var accepted = try listener.accept()
    var server = accepted.0
    try client.write_all("net".as_bytes())
    var bytes = [0u8; 3]
    try server.read_exact(bytes)
    if bytes[0usize] != 110u8 || bytes[1usize] != 101u8 ||
       bytes[2usize] != 116u8 {
        return 1
    }
    try client.shutdown(1)
    try server.set_read_timeout(present(from_millis(1000u64)))
    if try server.read_some(mut idle) != 0usize { return 29 }
    var server_writer = read server
    try server_writer.write_all("view".as_bytes())
    var stream_peek = [0u8; 4]
    let peeked = try client.peek(mut stream_peek)
    if peeked == 0usize || peeked > 4usize {
        return 14
    }
    var peek_index = 0usize
    while peek_index < peeked {
        if stream_peek[peek_index] != "view".as_bytes()[peek_index] { return 14 }
        peek_index += 1usize
    }
    var client_reader = read client
    var borrowed_bytes = [0u8; 4]
    try client_reader.read_exact(mut borrowed_bytes)
    if borrowed_bytes[0usize] != 118u8 || borrowed_bytes[1usize] != 105u8 ||
       borrowed_bytes[2usize] != 101u8 || borrowed_bytes[3usize] != 119u8 {
        return 11
    }

    try listener.set_nonblocking(true)
    let timed_client = try TcpStream.connect_timeout(address, from_millis(1000u64))
    var incoming = listener.incoming()
    let accepted_by_iterator = match take incoming.next() {
        present(success(stream)) => stream,
        present(failure(_)) => { return 15 },
        none => { return 15 }
    }
    debug(read timed_client)
    debug(read accepted_by_iterator)

    let datagram = try UdpSocket.bind(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    debug(read datagram)
    let datagram_address = try datagram.local_addr()
    if !datagram_address.ip.is_loopback() { return 7 }
    try datagram.set_read_timeout(present(from_millis(1000u64)))
    let sender = try UdpSocket.bind(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    if try sender.send_to("peek".as_bytes(), datagram_address) != 4usize { return 8 }
    var peeked = [0u8; 4]
    if try datagram.peek(mut peeked) != 4usize ||
       peeked[0usize] != 112u8 || peeked[1usize] != 101u8 ||
       peeked[2usize] != 101u8 || peeked[3usize] != 107u8 {
        return 9
    }
    var received = [0u8; 4]
    if try datagram.recv(mut received) != 4usize ||
       received[0usize] != 112u8 || received[1usize] != 101u8 ||
       received[2usize] != 101u8 || received[3usize] != 107u8 {
        return 10
    }
    try datagram.set_nonblocking(true)
    try datagram.set_nonblocking(false)
    try sender.connect(datagram_address)
    if try sender.send("udp".as_bytes()) != 3usize { return 16 }
    var received_from = [0u8; 3]
    let (received_count, source) = try datagram.recv_from(mut received_from)
    let sender_address = try sender.local_addr()
    if received_count != 3usize || !source.same(sender_address) ||
       received_from[0usize] != 117u8 || received_from[1usize] != 100u8 ||
       received_from[2usize] != 112u8 {
        return 17
    }
    let raw_listener = match take raw_socket(0) {
        present(fd) => fd,
        none => { return 18 }
    }
    let owned_listener = unsafe { try TcpListener.from_owned_fd(raw_listener) }
    if (try owned_listener.local_addr()).port != 0u16 { return 18 }
    let raw_stream = match take raw_socket(0) {
        present(fd) => fd,
        none => { return 19 }
    }
    let owned_stream = TcpStream.from(raw_stream)
    if (try owned_stream.local_addr()).port != 0u16 { return 19 }
    let raw_datagram = match take raw_socket(1) {
        present(fd) => fd,
        none => { return 20 }
    }
    let owned_datagram = UdpSocket.from(raw_datagram)
    if (try owned_datagram.local_addr()).port != 0u16 { return 20 }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => 100
    }
}
