// Synchronous POSIX TCP and UDP sockets, IPv4/IPv6 addresses, and DNS lookup.
import package.core.outcome
import package.core.fmt.{Debug, Display, Formatter, Write}
import package.core.slice
import package.core.text.Text
import package.alloc.vec
import package.alloc.vec.List
import super.io
import super.io.{Error, ErrorKind, Reader, Writer}
import super.sys
import super.time.Duration

pub copy type Ipv4Addr { bits: u32 }
pub copy type Ipv6Addr { bytes: [u8; 16] }
pub copy enum IpAddr { V4(Ipv4Addr), V6(Ipv6Addr) }

pub copy type SocketAddr {
    pub ip: IpAddr
    pub port: u16
    pub flowinfo: u32
    pub scope_id: u32
}

pub fn ipv4(a: u8, b: u8, c: u8, d: u8): Ipv4Addr {
    Ipv4Addr(((a as u32) << 24u32) | ((b as u32) << 16u32) | ((c as u32) << 8u32) | d as u32)
}

pub fn localhost(): Ipv4Addr { ipv4(127u8, 0u8, 0u8, 1u8) }
pub fn unspecified(): Ipv4Addr { Ipv4Addr(0u32) }

pub fn ipv6(a: u16, b: u16, c: u16, d: u16, e: u16, f: u16, g: u16, h: u16): Ipv6Addr {
    Ipv6Addr([
        (a >> 8u16) as u8, a as u8,
        (b >> 8u16) as u8, b as u8,
        (c >> 8u16) as u8, c as u8,
        (d >> 8u16) as u8, d as u8,
        (e >> 8u16) as u8, e as u8,
        (f >> 8u16) as u8, f as u8,
        (g >> 8u16) as u8, g as u8,
        (h >> 8u16) as u8, h as u8
    ])
}

pub fn ipv6_localhost(): Ipv6Addr { ipv6(0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16) }
pub fn ipv6_unspecified(): Ipv6Addr { ipv6(0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16) }

pub fn socket_addr(ip: Ipv4Addr, port: u16): SocketAddr {
    SocketAddr(IpAddr.V4(ip), port, 0u32, 0u32)
}

pub fn socket_addr_ip(ip: IpAddr, port: u16): SocketAddr {
    SocketAddr(ip, port, 0u32, 0u32)
}

pub fn socket_addr_v6(ip: Ipv6Addr, port: u16, flowinfo: u32, scope_id: u32): SocketAddr {
    SocketAddr(IpAddr.V6(ip), port, flowinfo, scope_id)
}

extend Ipv4Addr {
    pub fn octets(): [u8; 4] {
        [(self.bits >> 24u32) as u8, (self.bits >> 16u32) as u8, (self.bits >> 8u32) as u8, self.bits as u8]
    }
    pub fn is_loopback(): bool { (self.bits >> 24u32) == 127u32 }
    pub fn same(other: Ipv4Addr): bool { self.bits == other.bits }
}

extend Ipv6Addr {
    pub fn segments(): [u16; 8] {
        [
            ((self.bytes[0usize] as u16) << 8u16) | self.bytes[1usize] as u16,
            ((self.bytes[2usize] as u16) << 8u16) | self.bytes[3usize] as u16,
            ((self.bytes[4usize] as u16) << 8u16) | self.bytes[5usize] as u16,
            ((self.bytes[6usize] as u16) << 8u16) | self.bytes[7usize] as u16,
            ((self.bytes[8usize] as u16) << 8u16) | self.bytes[9usize] as u16,
            ((self.bytes[10usize] as u16) << 8u16) | self.bytes[11usize] as u16,
            ((self.bytes[12usize] as u16) << 8u16) | self.bytes[13usize] as u16,
            ((self.bytes[14usize] as u16) << 8u16) | self.bytes[15usize] as u16
        ]
    }

    pub fn is_loopback(): bool {
        var i = 0usize
        while i < 15usize {
            if self.bytes[i] != 0u8 { return false }
            i += 1usize
        }
        self.bytes[15usize] == 1u8
    }

    pub fn is_unspecified(): bool {
        var i = 0usize
        while i < 16usize {
            if self.bytes[i] != 0u8 { return false }
            i += 1usize
        }
        true
    }

    pub fn same(other: Ipv6Addr): bool {
        var i = 0usize
        while i < 16usize {
            if self.bytes[i] != other.bytes[i] { return false }
            i += 1usize
        }
        true
    }
}

extend IpAddr {
    pub fn is_loopback(): bool {
        match self {
            IpAddr.V4(ip) => ip.is_loopback(),
            IpAddr.V6(ip) => ip.is_loopback()
        }
    }

    pub fn same(other: IpAddr): bool {
        match self {
            IpAddr.V4(a) => match other {
                IpAddr.V4(b) => a.same(b),
                _ => false
            },
            IpAddr.V6(a) => match other {
                IpAddr.V6(b) => a.same(b),
                _ => false
            }
        }
    }
}

extend SocketAddr {
    pub fn same(other: SocketAddr): bool {
        self.ip.same(other.ip) && self.port == other.port &&
            self.flowinfo == other.flowinfo && self.scope_id == other.scope_id
    }
}

fn invalid_address(): Error { io.from_kind(ErrorKind.InvalidInput) }

fn parse_decimal(text: read Text, limit: u32): u32 throws Error {
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

fn parse_ipv4(text: read Text): Ipv4Addr throws Error {
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

fn parse_ipv6_side(text: read Text, start_index: usize, allow_ipv4: bool, groups: mut [u16; 8]): usize throws Error {
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

pub fn parse_ipv6(text: read Text): Ipv6Addr throws Error {
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
        var shifted = [0u16; 8]
        var j = 0usize
        while j < left_count {
            shifted[j] = groups[j]
            j += 1usize
        }
        j = 0usize
        while j < right_count {
            shifted[8usize - right_count + j] = right_groups[j]
            j += 1usize
        }
        groups = shifted
    }

    var address_bytes = [0u8; 16]
    i = 0usize
    while i < 8usize {
        address_bytes[i * 2usize] = (groups[i] >> 8u16) as u8
        address_bytes[i * 2usize + 1usize] = groups[i] as u8
        i += 1usize
    }
    Ipv6Addr(address_bytes)
}

extend Ipv6Addr {
    pub static fn localhost(): Ipv6Addr { ipv6_localhost() }
    pub static fn unspecified(): Ipv6Addr { ipv6_unspecified() }
    pub static fn parse(text: read Text): Ipv6Addr throws Error { try parse_ipv6(text) }
}

pub fn parse_ip_addr(text: read Text): IpAddr throws Error {
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

fn parse_port(text: read Text): u16 throws Error {
    let value = try parse_decimal(text, 65535u32)
    value as u16
}

pub fn parse_socket_addr(text: read Text): SocketAddr throws Error {
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
        let mut scope_id = 0u32
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
    pub static fn parse(text: read Text): SocketAddr throws Error { try parse_socket_addr(text) }
}

fn write_hex16<W: Write>(value: u16, f: mut Formatter<W>): Unit throws package.core.fmt.Error {
    let digits = "0123456789abcdef".as_bytes()
    var shift = 12u32
    var started = false
    while true {
        let digit = ((value >> shift) & 15u16) as usize
        if digit != 0usize || started || shift == 0u32 {
            try f.write_char(digits[digit] as char)
            started = true
        }
        if shift == 0u32 { break }
        shift -= 4u32
    }
}

fn write_ipv6<W: Write>(value: Ipv6Addr, f: mut Formatter<W>): Unit throws package.core.fmt.Error {
    var mapped = true
    var byte_index = 0usize
    while byte_index < 10usize {
        if value.bytes[byte_index] != 0u8 { mapped = false }
        byte_index += 1usize
    }
    if mapped && value.bytes[10usize] == 255u8 && value.bytes[11usize] == 255u8 {
        try f.write_str("::ffff:")
        let address = ipv4(value.bytes[12usize], value.bytes[13usize], value.bytes[14usize], value.bytes[15usize])
        return try Ipv4Addr.(Display).fmt(address, mut f)
    }

    let groups = value.segments()
    var best_start = 8usize
    var best_length = 1usize
    var i = 0usize
    while i < 8usize {
        if groups[i] != 0u16 {
            i += 1usize
        } else {
            let start = i
            while i < 8usize && groups[i] == 0u16 { i += 1usize }
            let length = i - start
            if length > best_length {
                best_start = start
                best_length = length
            }
        }
    }

    i = 0usize
    var separator = false
    var compressed = false
    while i < 8usize {
        if i == best_start {
            try f.write_str("::")
            i += best_length
            compressed = true
            separator = false
        } else {
            if separator && !compressed { try f.write_char(':') }
            try write_hex16(groups[i], mut f)
            separator = true
            compressed = false
            i += 1usize
        }
    }
}

extend Ipv4Addr implements Display {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        let values = self.octets()
        var i = 0usize
        while i < 4usize {
            if i != 0usize { try f.write_char('.') }
            try u8.(Display).fmt(values[i], mut f)
            i += 1usize
        }
    }
}
extend Ipv4Addr implements Debug {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        try Ipv4Addr.(Display).fmt(self, mut f)
    }
}
extend Ipv6Addr implements Display {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        try write_ipv6(self, mut f)
    }
}
extend Ipv6Addr implements Debug {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        try write_ipv6(self, mut f)
    }
}
extend IpAddr implements Display {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        match self {
            IpAddr.V4(ip) => try Ipv4Addr.(Display).fmt(ip, mut f),
            IpAddr.V6(ip) => try Ipv6Addr.(Display).fmt(ip, mut f)
        }
    }
}
extend IpAddr implements Debug {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        match self {
            IpAddr.V4(ip) => try Ipv4Addr.(Debug).fmt(ip, mut f),
            IpAddr.V6(ip) => try Ipv6Addr.(Debug).fmt(ip, mut f)
        }
    }
}
extend SocketAddr implements Display {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        match self.ip {
            IpAddr.V4(ip) => try Ipv4Addr.(Display).fmt(ip, mut f),
            IpAddr.V6(ip) => {
                try f.write_char('[')
                try Ipv6Addr.(Display).fmt(ip, mut f)
                if self.scope_id != 0u32 {
                    try f.write_char('%')
                    try u32.(Display).fmt(self.scope_id, mut f)
                }
                try f.write_char(']')
            }
        }
        try f.write_char(':')
        try u16.(Display).fmt(self.port, mut f)
    }
}
extend SocketAddr implements Debug {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws package.core.fmt.Error {
        try SocketAddr.(Display).fmt(self, mut f)
    }
}

fn net_error(): Error {
    let e = io.last_os_error()
    if e.kind().is(ErrorKind.WouldBlock) { return io.with_kind(sys.errno(), ErrorKind.TimedOut) }
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
            if unsafe { sys.mettle_rt_sock_bind(fd, 6, slice.data(ip.bytes), 16usize, addr.port, addr.flowinfo, addr.scope_id) } != 0 {
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
            if unsafe { sys.mettle_rt_sock_connect(fd, 6, slice.data(ip.bytes), 16usize, addr.port, addr.flowinfo, addr.scope_id) } != 0 {
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
                throw net_error()
            }
        },
        IpAddr.V6(ip) => {
            if unsafe { sys.mettle_rt_sock_connect_timeout(fd, 6, slice.data(ip.bytes), 16usize, addr.port, addr.flowinfo, addr.scope_id, timeout_micros) } != 0 {
                throw net_error()
            }
        }
    }
}

fn decode_socket_addr(family: i32, bytes: [u8; 16], port: u16, flowinfo: u32, scope_id: u32): SocketAddr {
    if family == 4 {
        socket_addr(ipv4(bytes[0usize], bytes[1usize], bytes[2usize], bytes[3usize]), port)
    } else {
        socket_addr_v6(Ipv6Addr(bytes), port, flowinfo, scope_id)
    }
}

fn local_of(fd: i32, peer: i32): SocketAddr throws Error {
    var family = 0i32
    var bytes = [0u8; 16]
    var port = 0u16
    var flowinfo = 0u32
    var scope_id = 0u32
    if unsafe { sys.mettle_rt_sock_name(fd, peer, core.ptr.from_mut(family), sys.data_mut(bytes), 16usize, core.ptr.from_mut(port), core.ptr.from_mut(flowinfo), core.ptr.from_mut(scope_id)) } != 0 {
        throw io.last_os_error()
    }
    decode_socket_addr(family, bytes, port, flowinfo, scope_id)
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

pub fn tcp_listen(addr: SocketAddr): TcpListener throws Error {
    let fd = try new_socket(0, family_of(addr.ip))
    let listener = TcpListener(fd, -1)
    try bind_address(fd, addr)
    if unsafe { sys.listen(fd, 128) } != 0 { throw io.last_os_error() }
    listener
}

extend TcpListener {
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
        var family = 0i32
        var bytes = [0u8; 16]
        var port = 0u16
        var flowinfo = 0u32
        var scope_id = 0u32
        let fd = unsafe {
            sys.mettle_rt_sock_accept(
                self.fd, self.accept_millis, core.ptr.from_mut(family),
                sys.data_mut(bytes), 16usize, core.ptr.from_mut(port),
                core.ptr.from_mut(flowinfo), core.ptr.from_mut(scope_id)
            )
        }
        if fd < 0 { throw net_error() }
        (TcpStream(fd), decode_socket_addr(family, bytes, port, flowinfo, scope_id))
    }
}

extend TcpStream {
    pub static fn connect_timeout(addr: SocketAddr, timeout: Duration): TcpStream throws Error {
        try tcp_connect_timeout(addr, timeout)
    }
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub fn peer_addr(): SocketAddr throws Error { try local_of(self.fd, 1) }
    pub fn set_read_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 0, limit) }
    pub fn set_write_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 1, limit) }
    pub fn wait_readable(limit: Duration): bool throws Error {
        let millis = limit.as_millis() as i32
        let result = unsafe { sys.mettle_rt_poll(self.fd, 0, millis) }
        if result < 0 { throw io.last_os_error() }
        result == 1
    }
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
    let fd = try new_socket(1, family_of(addr.ip))
    let socket = UdpSocket(fd)
    try bind_address(fd, addr)
    socket
}

extend UdpSocket {
    pub fn local_addr(): SocketAddr throws Error { try local_of(self.fd, 0) }
    pub fn set_read_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 0, limit) }
    pub fn set_write_timeout(limit: Duration?): Unit throws Error { try set_timeout(self.fd, 1, limit) }

    pub fn connect(addr: SocketAddr): Unit throws Error {
        try connect_address(self.fd, addr)
    }

    pub fn send_to(buf: read [u8], addr: SocketAddr): usize throws Error {
        let result = match addr.ip {
            IpAddr.V4(ip) => {
                let bytes = ip.octets()
                unsafe { sys.mettle_rt_sock_sendto(self.fd, slice.data(buf), buf.len(), 4, slice.data(bytes), 4usize, addr.port, 0u32, 0u32) }
            },
            IpAddr.V6(ip) => unsafe {
                sys.mettle_rt_sock_sendto(self.fd, slice.data(buf), buf.len(), 6, slice.data(ip.bytes), 16usize, addr.port, addr.flowinfo, addr.scope_id)
            }
        }
        if result < 0isize { throw net_error() }
        result as usize
    }

    pub fn recv_from(buf: mut [u8]): (usize, SocketAddr) throws Error {
        var family = 0i32
        var address = [0u8; 16]
        var port = 0u16
        var flowinfo = 0u32
        var scope_id = 0u32
        let result = unsafe {
            sys.mettle_rt_sock_recvfrom(
                self.fd, sys.data_mut(buf), buf.len(), core.ptr.from_mut(family),
                sys.data_mut(address), 16usize, core.ptr.from_mut(port),
                core.ptr.from_mut(flowinfo), core.ptr.from_mut(scope_id)
            )
        }
        if result < 0isize { throw net_error() }
        (result as usize, decode_socket_addr(family, address, port, flowinfo, scope_id))
    }

    pub fn send(buf: read [u8]): usize throws Error { try stream_write(self.fd, buf) }
    pub fn recv(buf: mut [u8]): usize throws Error { try stream_read(self.fd, buf) }
}

type ResolveHandle {
    raw: ptr<mut u8>
    drop { unsafe { sys.mettle_rt_resolve_free(self.raw) } }
}

pub fn resolve(host: read Text, port: u16): List<SocketAddr> throws Error {
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
                handle.raw, index, core.ptr.from_mut(family), sys.data_mut(bytes),
                16usize, core.ptr.from_mut(result_port), core.ptr.from_mut(flowinfo),
                core.ptr.from_mut(scope_id)
            )
        } != 0 { throw io.last_os_error() }
        addresses.push(decode_socket_addr(family, bytes, result_port, flowinfo, scope_id))
        index += 1usize
    }
    addresses
}
