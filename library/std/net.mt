// Synchronous POSIX TCP and UDP sockets, core address values, and DNS lookup.
import core.outcome
import core.convert.From
import core.cmp.{Eq, PartialEq}
import core.fmt.{Debug, Display, Error as FmtError, Formatter, Write}
import core.iter.{Copied, Iterator, Once, OwnedIterable}
import core.slice
import core.text.{FromStr, Text}
import core.clone.Clone
import alloc.vec
import alloc.vec.List
import alloc.string.String
import alloc.arc
import alloc.arc.Shared
import super.io
import super.io.{Error, ErrorKind, Reader, Writer}
import super.path.PathInput
import super.sys
import super.task
import super.time.Duration

extern "C" {
    unsafe fn recv(fd: i32, buffer: ptr<mut u8>, count: usize, flags: i32): isize;
}

pub import core.net.{
    ipv4, ipv6, ipv6_localhost, ipv6_unspecified, localhost, socket_addr,
    socket_addr_ip, socket_addr_v4, socket_addr_v6, socket_addr_v6_parts,
    unspecified, IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4,
    SocketAddrV6
}

pub copy enum Shutdown { Read, Write, Both }

pub copy type AddrParseError {}

extend AddrParseError implements Clone {
    fn clone(): AddrParseError { AddrParseError() }
}

extend AddrParseError implements PartialEq {
    fn eq(read other: AddrParseError): bool { true }
}
extend AddrParseError implements core.cmp.Eq {}

extend AddrParseError implements Debug {
    fn fmt(mut f: Formatter): Unit throws FmtError {
        var debug = try f.debug_struct("AddrParseError")
        try debug.finish()
    }
}

extend AddrParseError implements Display {
    fn fmt(mut f: Formatter): Unit throws FmtError {
        try f.write_str("invalid IP address syntax")
    }
}

extend AddrParseError implements core.error.Error {}

extend Shutdown implements Clone {
    fn clone(): Shutdown { self }
}

extend Shutdown implements PartialEq {
    fn eq(read other: Shutdown): bool {
        match self {
            Shutdown.Read => match other {
                Shutdown.Read => true,
                _ => false
            },
            Shutdown.Write => match other {
                Shutdown.Write => true,
                _ => false
            },
            Shutdown.Both => match other {
                Shutdown.Both => true,
                _ => false
            }
        }
    }
}

extend Shutdown implements Eq {}

pub interface ToSocketAddrs {
    type Iter<region r>: Iterator<Item = SocketAddr>;
    fn to_socket_addrs<region r>(receiver read self: Self from r): Self.Iter<region r> throws Error;
}

extend SocketAddr implements ToSocketAddrs {
    type Iter<region r> = Once<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Once<SocketAddr> throws Error {
        let address: SocketAddr = self
        core.iter.once(take address)
    }
}

extend SocketAddrV4 implements ToSocketAddrs {
    type Iter<region r> = Once<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Once<SocketAddr> throws Error {
        core.iter.once(self.to_socket_addr())
    }
}

extend SocketAddrV6 implements ToSocketAddrs {
    type Iter<region r> = Once<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Once<SocketAddr> throws Error {
        core.iter.once(self.to_socket_addr())
    }
}

extend (IpAddr, u16) implements ToSocketAddrs {
    type Iter<region r> = Once<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Once<SocketAddr> throws Error {
        core.iter.once(socket_addr_ip(self.0, self.1))
    }
}

extend (Ipv4Addr, u16) implements ToSocketAddrs {
    type Iter<region r> = Once<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Once<SocketAddr> throws Error {
        core.iter.once(socket_addr(self.0, self.1))
    }
}

extend (Ipv6Addr, u16) implements ToSocketAddrs {
    type Iter<region r> = Once<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Once<SocketAddr> throws Error {
        core.iter.once(socket_addr_v6(self.0, self.1, 0u32, 0u32))
    }
}

extend [SocketAddr] implements ToSocketAddrs {
    type Iter<region r> = Copied<region r, SocketAddr, slice.SliceIter<region r, SocketAddr>>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Copied<region r, SocketAddr, slice.SliceIter<region r, SocketAddr>> throws Error {
        self.iter().copied()
    }
}

extend<const N: usize> [SocketAddr; N] implements ToSocketAddrs {
    type Iter<region r> = Copied<region r, SocketAddr, slice.SliceIter<region r, SocketAddr>>
    fn to_socket_addrs<region r>(receiver read self: Self from r): Copied<region r, SocketAddr, slice.SliceIter<region r, SocketAddr>> throws Error {
        self.iter().copied()
    }
}

extend Text implements ToSocketAddrs {
    type Iter<region r> = vec.IntoIter<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): vec.IntoIter<SocketAddr> throws Error {
        match take capture parse_socket_addr(self) {
            success(address) => {
                var addresses = vec.new<SocketAddr>()
                addresses.push(take address)
                return addresses.into_iter()
            },
            failure(_) => {}
        }
        let separator = match self.rfind(':') {
            present(index) => index,
            none => throw invalid_to_socket_addrs()
        }
        let host = match self.get(0usize, separator) {
            present(value) => value,
            none => throw invalid_to_socket_addrs()
        }
        if host.is_empty() || host.find_byte(58u8).is_present() ||
            host.find_byte(91u8).is_present() || host.find_byte(93u8).is_present() {
            throw invalid_to_socket_addrs()
        }
        let port = match self.get(separator + 1usize, self.len()) {
            present(value) => match take capture parse_port(value) {
                success(port) => port,
                failure(_) => throw invalid_to_socket_addrs()
            },
            none => throw invalid_to_socket_addrs()
        }
        (try resolve(host, port)).into_iter()
    }
}

extend String implements ToSocketAddrs {
    type Iter<region r> = vec.IntoIter<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): vec.IntoIter<SocketAddr> throws Error {
        try self.as_text().to_socket_addrs()
    }
}

extend<region host_region> (read Text from host_region, u16) implements ToSocketAddrs {
    type Iter<region r> = vec.IntoIter<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): vec.IntoIter<SocketAddr> throws Error {
        (try resolve(self.0, self.1)).into_iter()
    }
}

extend (String, u16) implements ToSocketAddrs {
    type Iter<region r> = vec.IntoIter<SocketAddr>
    fn to_socket_addrs<region r>(receiver read self: Self from r): vec.IntoIter<SocketAddr> throws Error {
        (try resolve(self.0.as_text(), self.1)).into_iter()
    }
}

fn invalid_address(): AddrParseError { AddrParseError() }
fn invalid_to_socket_addrs(): Error { io.from_kind(ErrorKind.InvalidInput) }

fn parse_decimal(read text: Text, limit: u32): u32 throws AddrParseError {
    let bytes = text.as_bytes()
    if bytes.len() == 0usize { throw invalid_address() }
    var value = 0u32
    var i = 0usize
    while i < bytes.len() {
        if bytes[i] < 48u8 || bytes[i] > 57u8 { throw invalid_address() }
        let scaled = match value.checked_mul(10u32) {
            present(next) => next,
            none => throw invalid_address()
        }
        value = match scaled.checked_add((bytes[i] - 48u8) as u32) {
            present(next) => next,
            none => throw invalid_address()
        }
        if value > limit { throw invalid_address() }
        i += 1usize
    }
    value
}

fn parse_ipv4(read text: Text): Ipv4Addr throws AddrParseError {
    let bytes = text.as_bytes()
    var octets = [0u8; 4]
    var start = 0usize
    var i = 0usize
    var part = 0usize
    while part < 4usize {
        while i < bytes.len() && bytes[i] != 46u8 { i += 1usize }
        if i == start { throw invalid_address() }
        let digits = match text.get(start, i) {
            present(value) => value,
            none => throw invalid_address()
        }
        let digit_bytes = digits.as_bytes()
        if digit_bytes.len() > 1usize && digit_bytes[0usize] == 48u8 { throw invalid_address() }
        let value = try parse_decimal(digits, 255u32)
        octets[part] = value as u8
        part += 1usize
        if part < 4usize {
            if i >= bytes.len() { throw invalid_address() }
            i += 1usize
            start = i
        } else if i < bytes.len() {
            throw invalid_address()
        }
    }
    ipv4(octets[0usize], octets[1usize], octets[2usize], octets[3usize])
}

fn parse_ipv6_side(read text: Text, start_index: usize, allow_ipv4: bool, mut groups: [u16; 8]): usize throws AddrParseError {
    let bytes = text.as_bytes()
    var i = 0usize
    var used = 0usize
    while i < bytes.len() {
        let start = i
        while i < bytes.len() && bytes[i] != 58u8 { i += 1usize }
        if i == start { throw invalid_address() }
        let part = match text.get(start, i) {
            present(value) => value,
            none => throw invalid_address()
        }
        let dotted = match part.find_byte(46u8) {
            present(_) => true,
            none => false
        }
        if dotted {
            if !allow_ipv4 || i != bytes.len() || used > 6usize { throw invalid_address() }
            let v4 = try parse_ipv4(part)
            let octets = v4.octets()
            groups[start_index + used] = ((octets[0usize] as u16) << 8u16) | octets[1usize] as u16
            groups[start_index + used + 1usize] = ((octets[2usize] as u16) << 8u16) | octets[3usize] as u16
            used += 2usize
        } else {
            if part.len() > 4usize || used >= 8usize { throw invalid_address() }
            let digits = part.as_bytes()
            var value = 0u32
            var j = 0usize
            while j < digits.len() {
                let byte = digits[j]
                var digit = 16u32
                if byte >= 48u8 && byte <= 57u8 {
                    digit = (byte - 48u8) as u32
                } else if byte >= 97u8 && byte <= 102u8 {
                    digit = (byte - 87u8) as u32
                } else if byte >= 65u8 && byte <= 70u8 {
                    digit = (byte - 55u8) as u32
                }
                if digit >= 16u32 { throw invalid_address() }
                value = value * 16u32 + digit
                j += 1usize
            }
            groups[start_index + used] = value as u16
            used += 1usize
        }
        if i < bytes.len() {
            i += 1usize
            if i == bytes.len() { throw invalid_address() }
        }
    }
    used
}

pub fn parse_ipv6(read text: Text): Ipv6Addr throws AddrParseError {
    let bytes = text.as_bytes()
    if bytes.len() == 0usize { throw invalid_address() }
    var compressed_at = bytes.len()
    var i = 0usize
    while i + 1usize < bytes.len() {
        if bytes[i] == 58u8 && bytes[i + 1usize] == 58u8 {
            if compressed_at != bytes.len() { throw invalid_address() }
            compressed_at = i
            i += 2usize
        } else {
            i += 1usize
        }
    }

    var groups = [0u16; 8]
    if compressed_at == bytes.len() {
        let count = try parse_ipv6_side(text, 0usize, true, mut groups)
        if count != 8usize { throw invalid_address() }
    } else {
        let left = match text.get(0usize, compressed_at) {
            present(value) => value,
            none => throw invalid_address()
        }
        let right = match text.get(compressed_at + 2usize, bytes.len()) {
            present(value) => value,
            none => throw invalid_address()
        }
        let left_count = try parse_ipv6_side(left, 0usize, false, mut groups)
        var right_groups = [0u16; 8]
        let right_count = try parse_ipv6_side(right, 0usize, true, mut right_groups)
        if left_count + right_count >= 8usize { throw invalid_address() }
        var j = 0usize
        while j < right_count {
            groups[8usize - right_count + j] = right_groups[j]
            j += 1usize
        }
    }

    var address_bytes = [0u8; 16]
    i = 0usize
    while i < 8usize {
        address_bytes[i * 2usize] = (groups[i] >> 8u16) as u8
        address_bytes[i * 2usize + 1usize] = groups[i] as u8
        i += 1usize
    }
    Ipv6Addr.from_octets(address_bytes)
}

extend Ipv6Addr {
    pub static fn localhost(): Ipv6Addr { ipv6_localhost() }
    pub static fn unspecified(): Ipv6Addr { ipv6_unspecified() }
    pub static fn parse(read text: Text): Ipv6Addr throws AddrParseError { try parse_ipv6(text) }
}

extend Ipv4Addr {
    pub static fn localhost(): Ipv4Addr { ipv4(127u8, 0u8, 0u8, 1u8) }
    pub static fn unspecified(): Ipv4Addr { ipv4(0u8, 0u8, 0u8, 0u8) }
    pub static fn parse(read text: Text): Ipv4Addr throws AddrParseError {
        try parse_ipv4(text)
    }
}

pub fn parse_ip_addr(read text: Text): IpAddr throws AddrParseError {
    match text.find_byte(58u8) {
        present(_) => {
            let value = try parse_ipv6(text)
            IpAddr.V6(value)
        },
        none => {
            let value = try parse_ipv4(text)
            IpAddr.V4(value)
        }
    }
}

extend IpAddr {
    pub static fn parse(read text: Text): IpAddr throws AddrParseError {
        try parse_ip_addr(text)
    }
}

fn parse_port(read text: Text): u16 throws AddrParseError {
    let value = try parse_decimal(text, 65535u32)
    value as u16
}

pub fn parse_socket_addr(read text: Text): SocketAddr throws AddrParseError {
    let bytes = text.as_bytes()
    if bytes.len() == 0usize { throw invalid_address() }
    if bytes[0usize] == 91u8 {
        var close = 1usize
        while close < bytes.len() && bytes[close] != 93u8 { close += 1usize }
        if close >= bytes.len() || close + 1usize >= bytes.len() ||
            bytes[close + 1usize] != 58u8 { throw invalid_address() }
        let host = match text.get(1usize, close) {
            present(value) => value,
            none => throw invalid_address()
        }
        let port_text = match text.get(close + 2usize, bytes.len()) {
            present(value) => value,
            none => throw invalid_address()
        }
        var scope_id = 0u32
        let ip_text = match host.find_byte(37u8) {
            present(mark) => {
                let scope_text = match host.get(mark + 1usize, host.len()) {
                    present(value) => value,
                    none => throw invalid_address()
                }
                scope_id = try parse_decimal(scope_text, 4294967295u32)
                match host.get(0usize, mark) {
                    present(value) => value,
                    none => throw invalid_address()
                }
            },
            none => host
        }
        let ip = try parse_ipv6(ip_text)
        let port = try parse_port(port_text)
        return socket_addr_v6(ip, port, 0u32, scope_id)
    }

    let colon = match text.find_byte(58u8) {
        present(value) => value,
        none => throw invalid_address()
    }
    let host = match text.get(0usize, colon) {
        present(value) => value,
        none => throw invalid_address()
    }
    let port_text = match text.get(colon + 1usize, bytes.len()) {
        present(value) => value,
        none => throw invalid_address()
    }
    let ip = try parse_ipv4(host)
    let port = try parse_port(port_text)
    socket_addr(ip, port)
}

extend SocketAddr {
    pub static fn parse(read text: Text): SocketAddr throws AddrParseError { try parse_socket_addr(text) }
}

extend SocketAddrV4 {
    pub static fn parse(read text: Text): SocketAddrV4 throws AddrParseError {
        let address = try parse_socket_addr(text)
        match address.ip {
            IpAddr.V4(ip) => SocketAddrV4(ip, address.port),
            IpAddr.V6(_) => throw invalid_address()
        }
    }
}

extend SocketAddrV6 {
    pub static fn parse(read text: Text): SocketAddrV6 throws AddrParseError {
        let address = try parse_socket_addr(text)
        match address.ip {
            IpAddr.V4(_) => throw invalid_address(),
            IpAddr.V6(ip) => {
                SocketAddrV6(ip, address.port, address.flowinfo, address.scope_id)
            }
        }
    }
}

fn net_error(fd: i32): Error {
    let code = sys.errno()
    let e = io.from_raw_os_error(code)
    if e.kind().is(ErrorKind.WouldBlock) &&
        unsafe { sys.mettle_rt_sock_is_nonblocking(fd) } == 0 {
        return io.with_kind(code, ErrorKind.TimedOut)
    }
    e
}

fn duration_micros(duration: Duration): u64 throws Error {
    if duration.is_zero() { throw io.from_kind(ErrorKind.InvalidInput) }
    let seconds = match duration.as_secs().checked_mul(1000000u64) {
        present(value) => value,
        none => throw io.from_kind(ErrorKind.InvalidInput)
    }
    match seconds.checked_add(duration.subsec_micros() as u64) {
        present(value) => if value == 0u64 { 1u64 } else { value },
        none => throw io.from_kind(ErrorKind.InvalidInput)
    }
}

fn set_timeout(fd: i32, send: i32, limit: Duration?): Unit throws Error {
    var micros = 0u64
    match limit {
        present(duration) => { micros = try duration_micros(duration) },
        none => {}
    }
    if unsafe { sys.mettle_rt_sock_timeout(fd, send, micros) } != 0 { throw io.last_os_error() }
}

fn get_timeout(fd: i32, send: i32): Duration? throws Error {
    var seconds = 0u64
    var nanos = 0u32
    if unsafe { sys.mettle_rt_sock_get_timeout(fd, send, core.ptr.from_mut(seconds), core.ptr.from_mut(nanos)) } != 0 {
        throw io.last_os_error()
    }
    if seconds == 0u64 && nanos == 0u32 { none }
    else { present(super.time.duration(seconds, nanos)) }
}

const OPTION_TTL: i32 = 0
const OPTION_BROADCAST: i32 = 1
const OPTION_MULTICAST_LOOP_V4: i32 = 2
const OPTION_MULTICAST_LOOP_V6: i32 = 3
const OPTION_MULTICAST_TTL_V4: i32 = 4

fn set_socket_option(fd: i32, option: i32, value: u32): Unit throws Error {
    if unsafe { sys.mettle_rt_sock_set_option(fd, option, value) } != 0 {
        throw io.last_os_error()
    }
}

fn get_socket_option(fd: i32, option: i32): u32 throws Error {
    var value = 0u32
    if unsafe { sys.mettle_rt_sock_get_option(fd, option, core.ptr.from_mut(value)) } != 0 {
        throw io.last_os_error()
    }
    value
}

fn set_nonblocking(fd: i32, on: bool): Unit throws Error {
    var status = 0
    if on {
        status = unsafe { sys.mettle_rt_set_nonblocking(fd) }
    } else {
        status = unsafe { sys.mettle_rt_set_blocking(fd) }
    }
    if status != 0 { throw io.last_os_error() }
}

fn take_socket_error(fd: i32): Error? throws Error {
    var code = 0i32
    if unsafe { sys.mettle_rt_sock_error(fd, core.ptr.from_mut(code)) } != 0 {
        throw io.last_os_error()
    }
    if code == 0 { none } else { present(io.from_raw_os_error(code)) }
}

fn new_socket(kind: i32, family: i32): i32 throws Error {
    let fd = unsafe { sys.mettle_rt_sock_new(kind, family) }
    if fd < 0 { throw io.last_os_error() }
    fd
}

fn family_of(ip: IpAddr): i32 {
    match ip { IpAddr.V4(_) => 4, IpAddr.V6(_) => 6 }
}

fn bind_address(fd: i32, addr: SocketAddr): Unit throws Error {
    match addr.ip {
        IpAddr.V4(ip) => {
            let bytes = ip.octets()
            if unsafe { sys.mettle_rt_sock_bind(fd, 4, slice.data(bytes), 4usize, addr.port, 0u32, 0u32) } != 0 {
                throw io.last_os_error()
            }
        },
        IpAddr.V6(ip) => {
            let bytes = ip.octets()
            if unsafe { sys.mettle_rt_sock_bind(fd, 6, slice.data(bytes), 16usize, addr.port, addr.flowinfo, addr.scope_id) } != 0 {
                throw io.last_os_error()
            }
        }
    }
}

fn connect_address(fd: i32, addr: SocketAddr): Unit throws Error {
    match addr.ip {
        IpAddr.V4(ip) => {
            let bytes = ip.octets()
            if unsafe { sys.mettle_rt_sock_connect(fd, 4, slice.data(bytes), 4usize, addr.port, 0u32, 0u32) } != 0 {
                throw io.last_os_error()
            }
        },
        IpAddr.V6(ip) => {
            let bytes = ip.octets()
            if unsafe { sys.mettle_rt_sock_connect(fd, 6, slice.data(bytes), 16usize, addr.port, addr.flowinfo, addr.scope_id) } != 0 {
                throw io.last_os_error()
            }
        }
    }
}

fn connect_address_timeout(fd: i32, addr: SocketAddr, timeout_micros: u64): Unit throws Error {
    match addr.ip {
        IpAddr.V4(ip) => {
            let bytes = ip.octets()
            if unsafe { sys.mettle_rt_sock_connect_timeout(fd, 4, slice.data(bytes), 4usize, addr.port, 0u32, 0u32, timeout_micros) } != 0 {
                throw net_error(fd)
            }
        },
        IpAddr.V6(ip) => {
            let bytes = ip.octets()
            if unsafe { sys.mettle_rt_sock_connect_timeout(fd, 6, slice.data(bytes), 16usize, addr.port, addr.flowinfo, addr.scope_id, timeout_micros) } != 0 {
                throw net_error(fd)
            }
        }
    }
}

fn decode_socket_addr(family: i32, bytes: [u8; 16], port: u16, flowinfo: u32, scope_id: u32): SocketAddr {
    if family == 4 {
        socket_addr(ipv4(bytes[0usize], bytes[1usize], bytes[2usize], bytes[3usize]), port)
    } else {
        socket_addr_v6(Ipv6Addr.from_octets(bytes), port, flowinfo, scope_id)
    }
}

fn local_of(fd: i32, peer: i32): SocketAddr throws Error {
    var family = 0i32
    var bytes = [0u8; 16]
    var port = 0u16
    var flowinfo = 0u32
    var scope_id = 0u32
    if unsafe { sys.mettle_rt_sock_name(fd, peer, core.ptr.from_mut(family), sys.data_mut(mut bytes), 16usize, core.ptr.from_mut(port), core.ptr.from_mut(flowinfo), core.ptr.from_mut(scope_id)) } != 0 {
        throw io.last_os_error()
    }
    decode_socket_addr(family, bytes, port, flowinfo, scope_id)
}

fn stream_read(fd: i32, mut buf: [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys.`read`(fd, sys.data_mut(mut buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = net_error(fd)
        if !e.kind().is(ErrorKind.Interrupted) { throw e }
    }
    0usize
}

fn stream_write(fd: i32, read buf: [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    let n = unsafe { sys.mettle_rt_sock_send(fd, slice.data(buf), buf.len()) }
    if n < 0isize { throw net_error(fd) }
    n as usize
}

fn socket_peek(fd: i32, mut buf: [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let count = unsafe { recv(fd, sys.data_mut(mut buf), buf.len(), 2) }
        if count >= 0isize { return count as usize }
        let error = net_error(fd)
        if !error.kind().is(ErrorKind.Interrupted) { throw error }
    }
    0usize
}

pub type TcpStream {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

extend TcpStream implements From<sys.OwnedFd> {
    static fn from(take fd: sys.OwnedFd): TcpStream { TcpStream(fd.into_raw_fd()) }
}

pub type TcpListener {
    fd: i32
    accept_millis: i32
    nonblocking: Shared<core.sync.atomic.AtomicBool>
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

@cfg(target_os = "linux")
extend TcpStream implements std.os.fd.AsRawFd {
    fn as_raw_fd(): i32 { self.fd }
}
@cfg(target_os = "linux")
extend TcpListener implements std.os.fd.AsRawFd {
    fn as_raw_fd(): i32 { self.fd }
}
@cfg(target_os = "linux")
extend TcpStream implements std.os.fd.AsFd {
    fn as_fd<region r>(receiver read self: Self from r): std.os.fd.BorrowedFd<region r> {
        unsafe { std.os.fd.BorrowedFd<region r>.borrow_raw(self.fd) }
    }
}
@cfg(target_os = "linux")
extend TcpListener implements std.os.fd.AsFd {
    fn as_fd<region r>(receiver read self: Self from r): std.os.fd.BorrowedFd<region r> {
        unsafe { std.os.fd.BorrowedFd<region r>.borrow_raw(self.fd) }
    }
}

extend TcpListener {
    // Safety: control all aliases; never clear O_NONBLOCK or independently re-adopt while managed.
    pub unsafe static fn from_owned_fd(take fd: sys.OwnedFd): TcpListener throws Error {
        let raw = fd.as_raw_fd()
        let mode = unsafe { sys.mettle_rt_sock_is_nonblocking(raw) }
        if mode < 0 { throw io.last_os_error() }
        let nonblocking = arc.new(core.sync.atomic.AtomicBool.new(mode != 0))
        if unsafe { sys.mettle_rt_set_nonblocking(raw) } != 0 { throw io.last_os_error() }
        TcpListener(fd.into_raw_fd(), -1, nonblocking)
    }
}

pub type Incoming<region r> { listener: read TcpListener from r }
extend<region r> Incoming<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        var debug = try f.debug_struct("Incoming")
        try debug.field("listener", read self.listener)
        try debug.finish()
    }
}

// Nonblocking counterparts used by async methods. A pending operation keeps
// only its readiness registration; dropping its future removes that token.
pub type AsyncTcpStream {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

pub type AsyncTcpListener {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

fn debug_socket(name: read Text, fd: i32, mut f: Formatter): Unit throws core.fmt.Error {
    try f.write_str(name)
    try f.write_str(" { fd: ")
    try i32.(Display).fmt(fd, mut f)
    try f.write_str(" }")
}

extend TcpListener implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try debug_socket("TcpListener", self.fd, mut f)
    }
}

extend TcpStream implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try debug_socket("TcpStream", self.fd, mut f)
    }
}

unsafe extend AsyncTcpStream implements Transferable {}
unsafe extend AsyncTcpListener implements Transferable {}

pub fn tcp_connect<A: ToSocketAddrs + unsized>(read addr: A): TcpStream throws Error {
    var addresses = try addr.to_socket_addrs()
    var last_error = io.from_kind(ErrorKind.InvalidInput)
    while true {
        let address = match take addresses.next() {
            present(value) => value,
            none => throw last_error
        }
        match take capture tcp_connect_address(address) {
            success(stream) => { return stream },
            failure(error) => { last_error = error }
        }
    }
}

fn tcp_connect_address(addr: SocketAddr): TcpStream throws Error {
    let fd = try new_socket(0, family_of(addr.ip))
    let stream = TcpStream(fd)
    try connect_address(fd, addr)
    stream
}

pub fn tcp_connect_timeout(addr: SocketAddr, timeout: Duration): TcpStream throws Error {
    let micros = try duration_micros(timeout)
    let fd = try new_socket(0, family_of(addr.ip))
    let stream = TcpStream(fd)
    try connect_address_timeout(fd, addr, micros)
    stream
}

pub fn tcp_listen<A: ToSocketAddrs + unsized>(read addr: A): TcpListener throws Error {
    var addresses = try addr.to_socket_addrs()
    var last_error = io.from_kind(ErrorKind.InvalidInput)
    while true {
        let address = match take addresses.next() {
            present(value) => value,
            none => throw last_error
        }
        match take capture tcp_listen_address(address) {
            success(listener) => { return listener },
            failure(error) => { last_error = error }
        }
    }
}

fn tcp_listen_address(addr: SocketAddr): TcpListener throws Error {
    let fd = try new_socket(0, family_of(addr.ip))
    let owned = unsafe { sys.OwnedFd.from_raw_fd(fd) }
    let listener = unsafe { try TcpListener.from_owned_fd(take owned) }
    try bind_address(fd, addr)
    if unsafe { sys.listen(fd, 128) } != 0 { throw io.last_os_error() }
    listener
}

pub async fn async_tcp_connect(addr: SocketAddr): AsyncTcpStream throws Error {
    let fd = try new_socket(0, family_of(addr.ip))
    let stream = AsyncTcpStream(fd)
    if unsafe { sys.mettle_rt_set_nonblocking(fd) } != 0 {
        throw io.last_os_error()
    }
    let started = match addr.ip {
        IpAddr.V4(ip) => {
            let bytes = ip.octets()
            unsafe {
                sys.mettle_rt_sock_connect_start(
                    fd, 4, slice.data(bytes), 4usize, addr.port, 0u32, 0u32
                )
            }
        },
        IpAddr.V6(ip) => {
            let bytes = ip.octets()
            unsafe {
                sys.mettle_rt_sock_connect_start(
                    fd, 6, slice.data(bytes), 16usize, addr.port,
                    addr.flowinfo, addr.scope_id
                )
            }
        }
    }
    if started < 0 { throw net_error(fd) }
    if started == 1 {
        let waited = await task.writable(fd)
        if waited == -1 { throw io.from_kind(ErrorKind.Unsupported) }
        if waited != 0 { throw io.from_raw_os_error(waited) }
        if unsafe { sys.mettle_rt_sock_connect_status(fd) } != 0 {
            throw net_error(fd)
        }
    }
    stream
}

pub fn async_tcp_listen(addr: SocketAddr): AsyncTcpListener throws Error {
    let fd = try new_socket(0, family_of(addr.ip))
    let listener = AsyncTcpListener(fd)
    if unsafe { sys.mettle_rt_set_nonblocking(fd) } != 0 {
        throw io.last_os_error()
    }
    try bind_address(fd, addr)
    if unsafe { sys.listen(fd, 128) } != 0 { throw io.last_os_error() }
    listener
}

extend TcpListener {
    pub static fn bind<A: ToSocketAddrs + unsized>(read addr: A): TcpListener throws Error { try tcp_listen(addr) }

    pub fn set_ttl(ttl: u32): Unit throws Error { try set_socket_option(self.fd, OPTION_TTL, ttl) }
    pub fn ttl(): u32 throws Error { try get_socket_option(self.fd, OPTION_TTL) }

    pub fn incoming<region r>(
        receiver read self: TcpListener from r
    ): Incoming<region r> {
        Incoming(read self)
    }

    pub fn take_error(): Error? throws Error { try take_socket_error(self.fd) }
    pub fn try_clone(): TcpListener throws Error {
        let nonblocking = self.nonblocking.clone()
        let cloned = unsafe { sys.mettle_rt_dup(self.fd) }
        if cloned < 0 { throw io.last_os_error() }
        TcpListener(cloned, self.accept_millis, nonblocking)
    }
    pub fn set_nonblocking(on: bool): Unit throws Error {
        self.nonblocking.get().store(on, core.sync.atomic.Ordering.Release)
    }
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub mut fn set_accept_timeout(limit: Duration?): Unit throws Error {
        self.accept_millis = -1
        match limit {
            present(duration) => {
                if duration.is_zero() { throw io.from_kind(ErrorKind.InvalidInput) }
                var millis = duration.as_millis()
                if millis > 2000000000u128 { millis = 2000000000u128 }
                if millis == 0u128 { millis = 1u128 }
                self.accept_millis = millis as i32
            },
            none => {}
        }
    }
    pub fn accept(): (TcpStream, SocketAddr) throws Error {
        let nonblocking = self.nonblocking.get().load(core.sync.atomic.Ordering.Acquire)
        var timed_out = 0i32
        var family = 0i32
        var bytes = [0u8; 16]
        var port = 0u16
        var flowinfo = 0u32
        var scope_id = 0u32
        let fd = unsafe {
            sys.mettle_rt_sock_accept(
                self.fd, self.accept_millis, if nonblocking { 1 } else { 0 },
                core.ptr.from_mut(timed_out), core.ptr.from_mut(family),
                sys.data_mut(mut bytes), 16usize, core.ptr.from_mut(port),
                core.ptr.from_mut(flowinfo), core.ptr.from_mut(scope_id)
            )
        }
        if fd < 0 {
            let code = sys.errno()
            if timed_out != 0 { throw io.with_kind(code, ErrorKind.TimedOut) }
            throw io.from_raw_os_error(code)
        }
        (TcpStream(fd), decode_socket_addr(family, bytes, port, flowinfo, scope_id))
    }
}

extend<region r> Incoming<region r> implements core.iter.Iterator {
    type Item = (Outcome<TcpStream, Error>);

    mut fn next(): (Outcome<TcpStream, Error>)? {
        let accepted = capture (*self.listener).accept()
        match take accepted {
            success((stream, _)) => present(success(stream)),
            failure(error) => present(failure(error))
        }
    }
}

extend AsyncTcpListener {
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }

    pub async fn accept(): (AsyncTcpStream, SocketAddr) throws Error {
        while true {
            var timed_out = 0i32
            var family = 0i32
            var bytes = [0u8; 16]
            var port = 0u16
            var flowinfo = 0u32
            var scope_id = 0u32
            let fd = unsafe {
                sys.mettle_rt_sock_accept(
                    self.fd, -1, 1, core.ptr.from_mut(timed_out),
                    core.ptr.from_mut(family),
                    sys.data_mut(mut bytes), 16usize, core.ptr.from_mut(port),
                    core.ptr.from_mut(flowinfo), core.ptr.from_mut(scope_id)
                )
            }
            if fd >= 0 {
                if unsafe { sys.mettle_rt_set_nonblocking(fd) } != 0 {
                    let error = io.last_os_error()
                    let _closed = unsafe { sys.close(fd) }
                    throw error
                }
                return (AsyncTcpStream(fd),
                        decode_socket_addr(family, bytes, port, flowinfo, scope_id))
            }
            let error = io.last_os_error()
            if error.kind().is(ErrorKind.Interrupted) { continue }
            if error.kind().is(ErrorKind.WouldBlock) {
                let waited = await task.readable(self.fd)
                if waited == -1 { throw io.from_kind(ErrorKind.Unsupported) }
                if waited != 0 { throw io.from_raw_os_error(waited) }
                continue
            }
            throw error
        }
        throw io.from_kind(ErrorKind.Other)
    }
}

extend TcpStream {
    pub static fn connect<A: ToSocketAddrs + unsized>(read addr: A): TcpStream throws Error { try tcp_connect(addr) }
    pub static fn connect_timeout(addr: SocketAddr, timeout: Duration): TcpStream throws Error {
        try tcp_connect_timeout(addr, timeout)
    }
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub fn peer_addr(): SocketAddr throws Error { try local_of(self.fd, 1) }
    pub fn peek(mut buf: [u8]): usize throws Error {
        try socket_peek(self.fd, mut buf)
    }
    pub fn try_clone(): TcpStream throws Error {
        let cloned = unsafe { sys.mettle_rt_dup(self.fd) }
        if cloned < 0 { throw io.last_os_error() }
        TcpStream(cloned)
    }
    pub fn set_nonblocking(on: bool): Unit throws Error {
        try set_nonblocking(self.fd, on)
    }
    pub fn set_nodelay(on: bool): Unit throws Error {
        var enabled = 0i32
        if on { enabled = 1 }
        if unsafe { sys.mettle_rt_sock_set_nodelay(self.fd, enabled) } != 0 {
            throw io.last_os_error()
        }
    }
    pub fn nodelay(): bool throws Error {
        var enabled = 0i32
        if unsafe { sys.mettle_rt_sock_get_nodelay(self.fd, core.ptr.from_mut(enabled)) } != 0 {
            throw io.last_os_error()
        }
        enabled != 0
    }
    pub fn take_error(): Error? throws Error { try take_socket_error(self.fd) }
    pub fn set_read_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 0, limit) }
    pub fn set_write_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 1, limit) }
    pub fn read_timeout(): Duration? throws Error { try get_timeout(self.fd, 0) }
    pub fn write_timeout(): Duration? throws Error { try get_timeout(self.fd, 1) }
    pub fn set_ttl(ttl: u32): Unit throws Error { try set_socket_option(self.fd, OPTION_TTL, ttl) }
    pub fn ttl(): u32 throws Error { try get_socket_option(self.fd, OPTION_TTL) }
    pub fn wait_readable(limit: Duration): bool throws Error {
        let started = std.time.now()
        loop {
            let remaining = limit.saturating_sub(started.elapsed())
            let nanos = remaining.as_nanos()
            let millis = (nanos + 999999u128) / 1000000u128
            let chunk = if millis > 2147483647u128 { 2147483647i32 } else { millis as i32 }
            let result = unsafe { sys.mettle_rt_poll(self.fd, 0, chunk) }
            if result < 0 { throw io.last_os_error() }
            if result > 0 { return true }
            if started.elapsed() >= limit { return false }
        }
    }
    pub fn shutdown(how: Shutdown): Unit throws Error {
        let raw = match how {
            Shutdown.Read => 0i32,
            Shutdown.Write => 1i32,
            Shutdown.Both => 2i32
        }
        if unsafe { sys.shutdown(self.fd, raw) } != 0 { throw io.last_os_error() }
    }
}

extend TcpStream implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try stream_read(self.fd, mut buf) }
}

extend TcpStream implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error { try stream_write(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

extend<region r> read TcpStream from r implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try stream_read(self.fd, mut buf) }
}

extend<region r> read TcpStream from r implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error { try stream_write(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

pub type UdpSocket {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

@cfg(target_os = "linux")
extend UdpSocket implements std.os.fd.AsRawFd {
    fn as_raw_fd(): i32 { self.fd }
}
@cfg(target_os = "linux")
extend UdpSocket implements std.os.fd.AsFd {
    fn as_fd<region r>(receiver read self: Self from r): std.os.fd.BorrowedFd<region r> {
        unsafe { std.os.fd.BorrowedFd<region r>.borrow_raw(self.fd) }
    }
}

extend UdpSocket implements From<sys.OwnedFd> {
    static fn from(take fd: sys.OwnedFd): UdpSocket { UdpSocket(fd.into_raw_fd()) }
}

extend UdpSocket implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try debug_socket("UdpSocket", self.fd, mut f)
    }
}

extend UdpSocket {
    pub static fn bind<A: ToSocketAddrs + unsized>(read addr: A): UdpSocket throws Error { try udp_bind(addr) }
}

pub fn udp_bind<A: ToSocketAddrs + unsized>(read addr: A): UdpSocket throws Error {
    var addresses = try addr.to_socket_addrs()
    var last_error = io.from_kind(ErrorKind.InvalidInput)
    while true {
        let address = match take addresses.next() {
            present(value) => value,
            none => throw last_error
        }
        match take capture udp_bind_address(address) {
            success(socket) => { return socket },
            failure(error) => { last_error = error }
        }
    }
}

fn udp_bind_address(addr: SocketAddr): UdpSocket throws Error {
    let fd = try new_socket(1, family_of(addr.ip))
    let socket = UdpSocket(fd)
    try bind_address(fd, addr)
    socket
}

extend AsyncTcpStream {
    pub async static fn connect(addr: SocketAddr): AsyncTcpStream throws Error {
        try await async_tcp_connect(addr)
    }

    pub async fn read_some(mut buf: [u8]): usize throws Error {
        if buf.len() == 0usize { return 0usize }
        while true {
            let n = unsafe { sys.`read`(self.fd, sys.data_mut(mut buf), buf.len()) }
            if n >= 0isize { return n as usize }
            let error = io.last_os_error()
            if error.kind().is(ErrorKind.Interrupted) { continue }
            if error.kind().is(ErrorKind.WouldBlock) {
                let waited = await task.readable(self.fd)
                if waited == -1 { throw io.from_kind(ErrorKind.Unsupported) }
                if waited != 0 { throw io.from_raw_os_error(waited) }
                continue
            }
            throw error
        }
        0usize
    }

    pub async fn write_some(read buf: [u8]): usize throws Error {
        if buf.len() == 0usize { return 0usize }
        while true {
            let n = unsafe { sys.mettle_rt_sock_send(self.fd, slice.data(buf), buf.len()) }
            if n >= 0isize { return n as usize }
            let error = io.last_os_error()
            if error.kind().is(ErrorKind.Interrupted) { continue }
            if error.kind().is(ErrorKind.WouldBlock) {
                let waited = await task.writable(self.fd)
                if waited == -1 { throw io.from_kind(ErrorKind.Unsupported) }
                if waited != 0 { throw io.from_raw_os_error(waited) }
                continue
            }
            throw error
        }
        0usize
    }

    pub async fn write_all(read buf: [u8]): Unit throws Error {
        var written = 0usize
        while written < buf.len() {
            let n = try await self.write_some(buf.split_at(written).1)
            if n == 0usize { throw io.from_kind(ErrorKind.WriteZero) }
            written += n
        }
    }

    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub fn peer_addr(): SocketAddr throws Error { try local_of(self.fd, 1) }
}

extend UdpSocket {
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub fn peer_addr(): SocketAddr throws Error { try local_of(self.fd, 1) }
    pub fn take_error(): Error? throws Error { try take_socket_error(self.fd) }
    pub fn try_clone(): UdpSocket throws Error {
        let cloned = unsafe { sys.mettle_rt_dup(self.fd) }
        if cloned < 0 { throw io.last_os_error() }
        UdpSocket(cloned)
    }
    pub fn set_nonblocking(on: bool): Unit throws Error {
        try set_nonblocking(self.fd, on)
    }
    pub fn set_read_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 0, limit) }
    pub fn set_write_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 1, limit) }
    pub fn read_timeout(): Duration? throws Error { try get_timeout(self.fd, 0) }
    pub fn write_timeout(): Duration? throws Error { try get_timeout(self.fd, 1) }
    pub fn set_ttl(ttl: u32): Unit throws Error { try set_socket_option(self.fd, OPTION_TTL, ttl) }
    pub fn ttl(): u32 throws Error { try get_socket_option(self.fd, OPTION_TTL) }
    pub fn set_broadcast(on: bool): Unit throws Error {
        try set_socket_option(self.fd, OPTION_BROADCAST, if on { 1u32 } else { 0u32 })
    }
    pub fn broadcast(): bool throws Error { (try get_socket_option(self.fd, OPTION_BROADCAST)) != 0u32 }
    pub fn set_multicast_loop_v4(on: bool): Unit throws Error {
        try set_socket_option(self.fd, OPTION_MULTICAST_LOOP_V4, if on { 1u32 } else { 0u32 })
    }
    pub fn multicast_loop_v4(): bool throws Error { (try get_socket_option(self.fd, OPTION_MULTICAST_LOOP_V4)) != 0u32 }
    pub fn set_multicast_loop_v6(on: bool): Unit throws Error {
        try set_socket_option(self.fd, OPTION_MULTICAST_LOOP_V6, if on { 1u32 } else { 0u32 })
    }
    pub fn multicast_loop_v6(): bool throws Error { (try get_socket_option(self.fd, OPTION_MULTICAST_LOOP_V6)) != 0u32 }
    pub fn set_multicast_ttl_v4(ttl: u32): Unit throws Error { try set_socket_option(self.fd, OPTION_MULTICAST_TTL_V4, ttl) }
    pub fn multicast_ttl_v4(): u32 throws Error { try get_socket_option(self.fd, OPTION_MULTICAST_TTL_V4) }
    pub fn join_multicast_v4(read group: Ipv4Addr, read interface_addr: Ipv4Addr): Unit throws Error {
        let group_bytes = group.octets()
        let interface_bytes = interface_addr.octets()
        if unsafe { sys.mettle_rt_sock_membership_v4(self.fd, slice.data(group_bytes), slice.data(interface_bytes), 1) } != 0 {
            throw io.last_os_error()
        }
    }
    pub fn leave_multicast_v4(read group: Ipv4Addr, read interface_addr: Ipv4Addr): Unit throws Error {
        let group_bytes = group.octets()
        let interface_bytes = interface_addr.octets()
        if unsafe { sys.mettle_rt_sock_membership_v4(self.fd, slice.data(group_bytes), slice.data(interface_bytes), 0) } != 0 {
            throw io.last_os_error()
        }
    }
    pub fn join_multicast_v6(read group: Ipv6Addr, interface_index: u32): Unit throws Error {
        let bytes = group.octets()
        if unsafe { sys.mettle_rt_sock_membership_v6(self.fd, slice.data(bytes), interface_index, 1) } != 0 {
            throw io.last_os_error()
        }
    }
    pub fn leave_multicast_v6(read group: Ipv6Addr, interface_index: u32): Unit throws Error {
        let bytes = group.octets()
        if unsafe { sys.mettle_rt_sock_membership_v6(self.fd, slice.data(bytes), interface_index, 0) } != 0 {
            throw io.last_os_error()
        }
    }

    pub fn connect<A: ToSocketAddrs + unsized>(read addr: A): Unit throws Error {
        var addresses = try addr.to_socket_addrs()
        var last_error = io.from_kind(ErrorKind.InvalidInput)
        while true {
            let address = match take addresses.next() {
                present(value) => value,
                none => throw last_error
            }
            match take capture connect_address(self.fd, address) {
                success(_) => { return },
                failure(error) => { last_error = error }
            }
        }
    }

    pub fn send_to<A: ToSocketAddrs + unsized>(read buf: [u8], read addr: A): usize throws Error {
        var addresses = try addr.to_socket_addrs()
        let destination = match take addresses.next() {
            present(value) => value,
            none => throw io.from_kind(ErrorKind.InvalidInput)
        }
        let result = match destination.ip {
            IpAddr.V4(ip) => {
                let bytes = ip.octets()
                unsafe { sys.mettle_rt_sock_sendto(self.fd, slice.data(buf), buf.len(), 4, slice.data(bytes), 4usize, destination.port, 0u32, 0u32) }
            },
            IpAddr.V6(ip) => {
                let bytes = ip.octets()
                unsafe {
                    sys.mettle_rt_sock_sendto(self.fd, slice.data(buf), buf.len(), 6, slice.data(bytes), 16usize, destination.port, destination.flowinfo, destination.scope_id)
                }
            }
        }
        if result < 0isize { throw net_error(self.fd) }
        result as usize
    }

    pub fn recv_from(mut buf: [u8]): (usize, SocketAddr) throws Error {
        try datagram_recv_from(self.fd, mut buf, 0)
    }

    pub fn peek_from(mut buf: [u8]): (usize, SocketAddr) throws Error {
        try datagram_recv_from(self.fd, mut buf, 1)
    }

    pub fn send(read buf: [u8]): usize throws Error {
        let count = unsafe { sys.mettle_rt_sock_send(self.fd, slice.data(buf), buf.len()) }
        if count < 0isize { throw net_error(self.fd) }
        count as usize
    }
    pub fn recv(mut buf: [u8]): usize throws Error { try datagram_recv(self.fd, mut buf, 0) }
    pub fn peek(mut buf: [u8]): usize throws Error { try datagram_recv(self.fd, mut buf, 2) }
}

fn datagram_recv_from(fd: i32, mut buf: [u8], peek: i32): (usize, SocketAddr) throws Error {
    var family = 0i32
    var address = [0u8; 16]
    var port = 0u16
    var flowinfo = 0u32
    var scope_id = 0u32
    let result = unsafe {
        sys.mettle_rt_sock_recvfrom(
            fd, sys.data_mut(mut buf), buf.len(), peek, core.ptr.from_mut(family),
            sys.data_mut(mut address), 16usize, core.ptr.from_mut(port),
            core.ptr.from_mut(flowinfo), core.ptr.from_mut(scope_id)
        )
    }
    if result < 0isize { throw net_error(fd) }
    (result as usize, decode_socket_addr(family, address, port, flowinfo, scope_id))
}

fn datagram_recv(fd: i32, mut buf: [u8], flags: i32): usize throws Error {
    while true {
        let count = unsafe { recv(fd, sys.data_mut(mut buf), buf.len(), flags) }
        if count >= 0isize { return count as usize }
        let error = net_error(fd)
        if !error.kind().is(ErrorKind.Interrupted) { throw error }
    }
    0usize
}

type ResolveHandle {
    raw: ptr<mut u8>
    drop { unsafe { sys.mettle_rt_resolve_free(self.raw) } }
}

pub fn resolve(read host: Text, port: u16): List<SocketAddr> throws Error {
    var count = 0usize
    let raw = unsafe {
        sys.mettle_rt_resolve(
            slice.data(host.as_bytes()), host.len(), port, core.ptr.from_mut(count)
        )
    }
    if raw == core.ptr.null_mut<u8>() { throw io.last_os_error() }
    let handle = ResolveHandle(raw)
    var addresses = vec.new<SocketAddr>()
    var index = 0usize
    while index < count {
        var family = 0i32
        var bytes = [0u8; 16]
        var result_port = 0u16
        var flowinfo = 0u32
        var scope_id = 0u32
        if unsafe {
            sys.mettle_rt_resolve_get(
                handle.raw, index, core.ptr.from_mut(family), sys.data_mut(mut bytes),
                16usize, core.ptr.from_mut(result_port), core.ptr.from_mut(flowinfo),
                core.ptr.from_mut(scope_id)
            )
        } != 0 { throw io.last_os_error() }
        addresses.push(decode_socket_addr(family, bytes, result_port, flowinfo, scope_id))
        index += 1usize
    }
    addresses
}


extend Ipv4Addr implements FromStr {
    type Error = AddrParseError
    static fn from_str(read input: Text): Ipv4Addr throws AddrParseError { try parse_ipv4(input) }
}
extend Ipv6Addr implements FromStr {
    type Error = AddrParseError
    static fn from_str(read input: Text): Ipv6Addr throws AddrParseError { try parse_ipv6(input) }
}
extend IpAddr implements FromStr {
    type Error = AddrParseError
    static fn from_str(read input: Text): IpAddr throws AddrParseError { try parse_ip_addr(input) }
}
extend SocketAddr implements FromStr {
    type Error = AddrParseError
    static fn from_str(read input: Text): SocketAddr throws AddrParseError { try parse_socket_addr(input) }
}
extend SocketAddrV4 implements FromStr {
    type Error = AddrParseError
    static fn from_str(read input: Text): SocketAddrV4 throws AddrParseError {
        let address = try parse_socket_addr(input)
        match address.ip {
            IpAddr.V4(ip) => SocketAddrV4(ip, address.port),
            IpAddr.V6(_) => throw invalid_address()
        }
    }
}
extend SocketAddrV6 implements FromStr {
    type Error = AddrParseError
    static fn from_str(read input: Text): SocketAddrV6 throws AddrParseError {
        let address = try parse_socket_addr(input)
        match address.ip {
            IpAddr.V4(_) => throw invalid_address(),
            IpAddr.V6(ip) => SocketAddrV6(ip, address.port, address.flowinfo, address.scope_id)
        }
    }
}

fn unix_socket(kind: i32): i32 throws Error {
    let fd = unsafe { sys.mettle_rt_unix_sock_new(kind) }
    if fd < 0 { throw io.last_os_error() }
    fd
}

fn unix_bind(fd: i32, read input: PathInput): Unit throws Error {
    let bytes = input.as_path().as_bytes()
    if unsafe {
        sys.mettle_rt_unix_sock_bind(fd, core.slice.data(bytes), bytes.len())
    } != 0 {
        throw io.last_os_error()
    }
}

fn unix_connect(fd: i32, read input: PathInput): Unit throws Error {
    let bytes = input.as_path().as_bytes()
    if unsafe {
        sys.mettle_rt_unix_sock_connect(fd, core.slice.data(bytes), bytes.len())
    } != 0 {
        throw io.last_os_error()
    }
}

pub type UnixStream {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

pub type UnixListener {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

pub type UnixDatagram {
    fd: i32
    drop { if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } } }
}

extend UnixStream {
    pub static fn connect(read input: PathInput): UnixStream throws Error {
        let fd = try unix_socket(0i32)
        match take capture unix_connect(fd, input) {
            success(_) => UnixStream(fd),
            failure(error) => {
                let closed = unsafe { sys.close(fd) }
                throw error
            }
        }
    }

    pub fn try_clone(): UnixStream throws Error {
        let cloned = unsafe { sys.mettle_rt_dup(self.fd) }
        if cloned < 0 { throw io.last_os_error() }
        UnixStream(cloned)
    }

    pub fn shutdown(how: Shutdown): Unit throws Error {
        let raw = match how {
            Shutdown.Read => 0i32,
            Shutdown.Write => 1i32,
            Shutdown.Both => 2i32
        }
        if unsafe { sys.shutdown(self.fd, raw) } != 0 { throw io.last_os_error() }
    }
}

extend UnixStream implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try stream_read(self.fd, mut buf) }
}

extend<region r> read UnixStream from r implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try stream_read(self.fd, mut buf) }
}

extend UnixStream implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error { try stream_write(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

extend<region r> read UnixStream from r implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error { try stream_write(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

extend UnixListener {
    pub static fn bind(read input: PathInput): UnixListener throws Error {
        let fd = try unix_socket(0i32)
        match take capture unix_bind(fd, input) {
            success(_) => {},
            failure(error) => {
                let closed = unsafe { sys.close(fd) }
                throw error
            }
        }
        if unsafe { sys.mettle_rt_unix_sock_listen(fd, 128i32) } != 0 {
            let error = io.last_os_error()
            let closed = unsafe { sys.close(fd) }
            throw error
        }
        UnixListener(fd)
    }

    pub fn accept(): UnixStream throws Error {
        loop {
            let fd = unsafe { sys.mettle_rt_unix_sock_accept(self.fd) }
            if fd >= 0 { return UnixStream(fd) }
            let error = io.last_os_error()
            if error.kind().is(ErrorKind.Interrupted) { continue }
            throw error
        }
        core.intrinsics.abort()
    }
}

extend UnixDatagram {
    pub static fn bind(read input: PathInput): UnixDatagram throws Error {
        let fd = try unix_socket(1i32)
        match take capture unix_bind(fd, input) {
            success(_) => UnixDatagram(fd),
            failure(error) => {
                let closed = unsafe { sys.close(fd) }
                throw error
            }
        }
    }

    pub fn connect(read input: PathInput): Unit throws Error {
        try unix_connect(self.fd, input)
    }

    pub fn send(read bytes: [u8]): usize throws Error {
        let sent = unsafe {
            sys.mettle_rt_sock_send(self.fd, core.slice.data(bytes), bytes.len())
        }
        if sent < 0 { throw io.last_os_error() }
        sent as usize
    }

    pub fn recv(mut bytes: [u8]): usize throws Error {
        try stream_read(self.fd, mut bytes)
    }
}
