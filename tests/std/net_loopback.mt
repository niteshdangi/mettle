// Single-process loopback TCP and UDP with partial transfers and timeouts.
import std.io.{Error, ErrorKind, Read, Write};
import std.net.{SocketAddr, TcpStream, TcpListener};
import std.time.from_millis;

fn any_port(): SocketAddr { std.net.socket_addr(std.net.localhost(), 0u16) }

fn tcp_part(): i32 throws Error {
    var listener = try std.net.tcp_listen(any_port())
    let addr = try listener.local_addr()
    if !addr.ip.is_loopback() || addr.port == 0u16 { return 1 }
    // Nothing is pending: accept honours its timeout with TimedOut.
    try listener.set_accept_timeout(present(from_millis(50u64)))
    let t0 = std.time.now()
    let idle = capture listener.accept()
    match take idle {
        success(p) => { return 2 },
        failure(e) => { if !e.kind().is(ErrorKind.TimedOut) || !e.is_os() { return 3 } }
    }
    if t0.elapsed().lt(from_millis(40u64)) { return 4 }
    try listener.set_accept_timeout(none)

    var client = try std.net.tcp_connect(addr)
    let pair = try listener.accept()
    var server = pair.0
    if !pair.1.ip.is_loopback() { return 5 }
    let peer = try client.peer_addr()
    if peer.port != addr.port { return 6 }

    // A read with no data times out, then succeeds once data arrives.
    try client.set_read_timeout(present(from_millis(50u64)))
    var buf = [0u8; 64]
    let none_yet = capture client.read_some(buf)
    match take none_yet {
        success(n) => { return 7 },
        failure(e) => { if !e.kind().is(ErrorKind.TimedOut) { return 8 } }
    }
    try server.write_all("hello".as_bytes())
    let got = try client.read_some(buf)
    if got == 0usize || got > 5usize || buf[0usize] != 104u8 { return 9 }
    var rest = [0u8; 8]
    if got < 5usize { try client.read_exact(rest.split_at_mut(5usize - got).0) }

    // A large transfer arrives through many partial reads.
    var big = alloc.vec.new<u8>()
    var i = 0usize
    while i < 200000usize { big.push((i % 253usize) as u8); i += 1usize }
    try client.set_read_timeout(present(from_millis(5000u64)))
    let writer_done = try pump(server, client, big.as_slice())
    if writer_done != 0 { return 10 + writer_done }

    // After shutdown of the write side the peer reads end-of-file.
    try client.shutdown(1)
    try server.set_read_timeout(present(from_millis(2000u64)))
    let eof = try server.read_some(buf)
    if eof != 0usize { return 20 }
    0
}

// Sends `data` from one end and reads it all on the other, interleaved so the
// socket buffers never fill.
fn pump(from: mut TcpStream, to: mut TcpStream, data: read [u8]): i32 throws Error {
    var sent = 0usize
    var received = 0usize
    var chunk = [0u8; 4096]
    while received < data.len() {
        if sent < data.len() {
            var end = sent + 2048usize
            if end > data.len() { end = data.len() }
            let n = try from.write_some(data.split_at(end).0.split_at(sent).1)
            sent += n
        }
        let m = try to.read_some(chunk)
        if m == 0usize { return 1 }
        var j = 0usize
        while j < m {
            if chunk[j] != ((received + j) % 253usize) as u8 { return 2 }
            j += 1usize
        }
        received += m
    }
    0
}

fn refused(): i32 throws Error {
    // Bind then close a listener so the port is known to be unused.
    var port = 0u16
    {
        let l = try std.net.tcp_listen(any_port())
        port = (try l.local_addr()).port
    }
    let r = capture std.net.tcp_connect(std.net.socket_addr(std.net.localhost(), port))
    match take r {
        success(s) => { return 1 },
        failure(e) => { if e.raw_os_error() != present(61) && e.raw_os_error() != present(111) { return 2 }; if !e.kind().is(ErrorKind.ConnectionRefused) { return 3 } }
    }
    0
}

fn udp_part(): i32 throws Error {
    let a = try std.net.udp_bind(any_port())
    let b = try std.net.udp_bind(any_port())
    let addr_a = try a.local_addr()
    let addr_b = try b.local_addr()
    var buf = [0u8; 32]
    // No datagram yet: the receive times out.
    try a.set_read_timeout(present(from_millis(50u64)))
    let idle = capture a.recv_from(buf)
    match take idle { success(x) => { return 1 }, failure(e) => { if !e.kind().is(ErrorKind.TimedOut) { return 2 } } }
    let sent = try b.send_to("datagram".as_bytes(), addr_a)
    if sent != 8usize { return 3 }
    let got = try a.recv_from(buf)
    if got.0 != 8usize || buf[0usize] != 100u8 || got.1.port != addr_b.port { return 4 }
    // A connected socket sends and receives without addresses.
    try a.connect(addr_b)
    try b.connect(addr_a)
    let s2 = try a.send("x".as_bytes())
    try b.set_read_timeout(present(from_millis(2000u64)))
    let r2 = try b.recv(buf)
    if s2 != 1usize || r2 != 1usize || buf[0usize] != 120u8 { return 5 }
    0
}

fn main(): i32 {
    let a = capture tcp_part()
    var code = 0
    match take a { success(c) => { code = c }, failure(e) => { code = 100 } }
    if code != 0 { return code }
    let b = capture refused()
    match take b { success(c) => { code = 30 + c }, failure(e) => { code = 130 } }
    if code != 30 { return code }
    let c = capture udp_part()
    match take c { success(v) => { code = 40 + v }, failure(e) => { code = 140 } }
    if code != 40 { return code }
    0
}
