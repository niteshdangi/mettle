// Synchronous IPv4 TCP and UDP sockets. Operations block unless a timeout is
// set; an expired timeout fails with kind `TimedOut` while keeping the raw OS
// number the system reported (usually "try again"). IPv6 and connect
// timeouts are not provided yet.
import package.core.outcome;
import super.io;
import super.io.{Error, ErrorKind, Reader, Writer};
import package.core.slice;
import super.sys;
import super.time.Duration;

pub copy type Ipv4Addr { bits: u32 }

pub fn ipv4(a: u8, b: u8, c: u8, d: u8): Ipv4Addr {
    Ipv4Addr(((a as u32) << 24u32) | ((b as u32) << 16u32) | ((c as u32) << 8u32) | d as u32)
}
pub fn localhost(): Ipv4Addr { ipv4(127u8, 0u8, 0u8, 1u8) }
pub fn unspecified(): Ipv4Addr { Ipv4Addr(0u32) }

extend Ipv4Addr {
    pub fn octets(): [u8; 4] {
        [(self.bits >> 24u32) as u8, (self.bits >> 16u32) as u8, (self.bits >> 8u32) as u8, self.bits as u8]
    }
    pub fn is_loopback(): bool { (self.bits >> 24u32) == 127u32 }
    pub fn same(other: Ipv4Addr): bool { self.bits == other.bits }
}

// An address and port; port 0 asks the system to choose one when binding.
pub copy type SocketAddr { pub ip: Ipv4Addr; pub port: u16 }

pub fn socket_addr(ip: Ipv4Addr, port: u16): SocketAddr { SocketAddr(ip, port) }

extend SocketAddr {
    pub fn same(other: SocketAddr): bool { self.ip.same(other.ip) && self.port == other.port }
}

fn net_error(): Error {
    let e = io.last_os_error()
    if e.kind().is(ErrorKind.WouldBlock) { return io.with_kind(sys.errno(), ErrorKind.TimedOut) }
    e
}

fn set_timeout(fd: i32, send: i32, limit: Duration?): Unit throws Error {
    var micros = 0u64
    match limit {
        present(d) => {
            if d.is_zero() { throw io.from_kind(ErrorKind.InvalidInput) }
            micros = d.as_secs() * 1000000u64 + (d.subsec_micros() as u64)
            if micros == 0u64 { micros = 1u64 }
        },
        none => {}
    }
    if unsafe { sys.mettle_rt_sock_timeout(fd, send, micros) } != 0 { throw io.last_os_error() }
}

fn local_of(fd: i32, peer: i32): SocketAddr throws Error {
    var address = 0u32
    var port = 0u16
    if unsafe { sys.mettle_rt_sock_name(fd, peer, core.ptr.from_mut(address), core.ptr.from_mut(port)) } != 0 {
        throw io.last_os_error()
    }
    SocketAddr(Ipv4Addr(address), port)
}

fn new_socket(kind: i32): i32 throws Error {
    let fd = unsafe { sys.mettle_rt_sock_new(kind) }
    if fd < 0 { throw io.last_os_error() }
    fd
}

fn stream_read(fd: i32, buf: mut [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys.`read`(fd, sys.data_mut(buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = net_error()
        if !e.kind().is(ErrorKind.Interrupted) { throw e }
    }
    0usize
}

fn stream_write(fd: i32, buf: read [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    let n = unsafe { sys.mettle_rt_sock_send(fd, slice.data(buf), buf.len()) }
    if n < 0isize { throw net_error() }
    n as usize
}

pub type TcpStream {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

pub type TcpListener {
    fd: i32
    accept_millis: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

pub fn tcp_connect(addr: SocketAddr): TcpStream throws Error {
    let fd = try new_socket(0)
    let stream = TcpStream(fd)
    if unsafe { sys.mettle_rt_sock_connect(fd, addr.ip.bits, addr.port) } != 0 { throw io.last_os_error() }
    stream
}

pub fn tcp_listen(addr: SocketAddr): TcpListener throws Error {
    let fd = try new_socket(0)
    let listener = TcpListener(fd, -1)
    if unsafe { sys.mettle_rt_sock_bind(fd, addr.ip.bits, addr.port) } != 0 { throw io.last_os_error() }
    if unsafe { sys.listen(fd, 128) } != 0 { throw io.last_os_error() }
    listener
}

extend TcpListener {
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    // Limits how long `accept` waits; none waits forever.
    pub mut fn set_accept_timeout(limit: Duration?): Unit throws Error {
        self.accept_millis = -1
        match limit {
            present(d) => {
                if d.is_zero() { throw io.from_kind(ErrorKind.InvalidInput) }
                var ms = d.as_millis()
                if ms > 2000000000u128 { ms = 2000000000u128 }
                if ms == 0u128 { ms = 1u128 }
                self.accept_millis = ms as i32
            },
            none => {}
        }
    }
    pub fn accept(): (TcpStream, SocketAddr) throws Error {
        var address = 0u32
        var port = 0u16
        let fd = unsafe { sys.mettle_rt_sock_accept(self.fd, self.accept_millis, core.ptr.from_mut(address), core.ptr.from_mut(port)) }
        if fd < 0 { throw net_error() }
        (TcpStream(fd), SocketAddr(Ipv4Addr(address), port))
    }
}

extend TcpStream {
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub fn peer_addr(): SocketAddr throws Error { try local_of(self.fd, 1) }
    pub fn set_read_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 0, limit) }
    pub fn set_write_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 1, limit) }
    // Waits until a read would not block, or `limit` passes; true when ready.
    pub fn wait_readable(limit: Duration): bool throws Error {
        let ms = limit.as_millis() as i32
        let r = unsafe { sys.mettle_rt_poll(self.fd, 0, ms) }
        if r < 0 { throw io.last_os_error() }
        r == 1
    }
    // Closes the read side (0), the write side (1) or both (2).
    pub fn shutdown(how: i32): Unit throws Error {
        if unsafe { sys.shutdown(self.fd, how) } != 0 { throw io.last_os_error() }
    }
}

extend TcpStream implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error { try stream_read(self.fd, buf) }
}

extend TcpStream implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error { try stream_write(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

pub type UdpSocket {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

pub fn udp_bind(addr: SocketAddr): UdpSocket throws Error {
    let fd = try new_socket(1)
    let socket = UdpSocket(fd)
    if unsafe { sys.mettle_rt_sock_bind(fd, addr.ip.bits, addr.port) } != 0 { throw io.last_os_error() }
    socket
}

extend UdpSocket {
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub fn set_read_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 0, limit) }
    pub fn set_write_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 1, limit) }

    // Fixes the peer for `send` and `recv` and filters other senders.
    pub fn connect(addr: SocketAddr): Unit throws Error {
        if unsafe { sys.mettle_rt_sock_connect(self.fd, addr.ip.bits, addr.port) } != 0 { throw io.last_os_error() }
    }

    pub fn send_to(buf: read [u8], addr: SocketAddr): usize throws Error {
        let n = unsafe { sys.mettle_rt_sock_sendto(self.fd, slice.data(buf), buf.len(), addr.ip.bits, addr.port) }
        if n < 0isize { throw net_error() }
        n as usize
    }

    // One datagram and its sender; a datagram longer than `buf` is truncated.
    pub fn recv_from(buf: mut [u8]): (usize, SocketAddr) throws Error {
        var address = 0u32
        var port = 0u16
        let n = unsafe { sys.mettle_rt_sock_recvfrom(self.fd, sys.data_mut(buf), buf.len(), core.ptr.from_mut(address), core.ptr.from_mut(port)) }
        if n < 0isize { throw net_error() }
        (n as usize, SocketAddr(Ipv4Addr(address), port))
    }

    pub fn send(buf: read [u8]): usize throws Error { try stream_write(self.fd, buf) }
    pub fn recv(buf: mut [u8]): usize throws Error { try stream_read(self.fd, buf) }
}
