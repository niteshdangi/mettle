import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.{From, Into}
import core.fmt.{Debug, Display, Formatter, Write}
import core.hash.{Hash, Hasher}
import core.ops.{BitAnd, BitAndAssign, BitOr, BitOrAssign, Not}
import core.clone.Clone

pub copy type Ipv4Addr { bits: u32 }
pub copy type Ipv6Addr { bytes: [u8; 16] }
pub copy enum IpAddr { V4(Ipv4Addr), V6(Ipv6Addr) }

pub copy type SocketAddr {
    pub ip: IpAddr
    pub port: u16
    pub flowinfo: u32
    pub scope_id: u32
}
pub copy type SocketAddrV4 { pub ip: Ipv4Addr; pub port: u16 }
pub copy type SocketAddrV6 {
    pub ip: Ipv6Addr
    pub port: u16
    pub flowinfo: u32
    pub scope_id: u32
}


pub const fn ipv4(a: u8, b: u8, c: u8, d: u8): Ipv4Addr {
    Ipv4Addr(((a as u32) << 24u32) | ((b as u32) << 16u32) | ((c as u32) << 8u32) | d as u32)
}

pub const fn localhost(): Ipv4Addr { ipv4(127u8, 0u8, 0u8, 1u8) }
pub const fn unspecified(): Ipv4Addr { Ipv4Addr(0u32) }

pub const fn ipv6(a: u16, b: u16, c: u16, d: u16, e: u16, f: u16, g: u16, h: u16): Ipv6Addr {
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

pub const fn ipv6_localhost(): Ipv6Addr { ipv6(0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 1u16) }
pub const fn ipv6_unspecified(): Ipv6Addr { ipv6(0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16, 0u16) }

pub const fn socket_addr(ip: Ipv4Addr, port: u16): SocketAddr {
    SocketAddr(IpAddr.V4(ip), port, 0u32, 0u32)
}

pub const fn socket_addr_ip(ip: IpAddr, port: u16): SocketAddr {
    SocketAddr(ip, port, 0u32, 0u32)
}

pub const fn socket_addr_v4(ip: Ipv4Addr, port: u16): SocketAddrV4 {
    SocketAddrV4(ip, port)
}

pub const fn socket_addr_v6(ip: Ipv6Addr, port: u16, flowinfo: u32, scope_id: u32): SocketAddr {
    SocketAddr(IpAddr.V6(ip), port, flowinfo, scope_id)
}

pub const fn socket_addr_v6_parts(ip: Ipv6Addr, port: u16, flowinfo: u32, scope_id: u32): SocketAddrV6 {
    SocketAddrV6(ip, port, flowinfo, scope_id)
}

extend SocketAddrV4 {
    pub static const fn new(ip: Ipv4Addr, port: u16): SocketAddrV4 { SocketAddrV4(ip, port) }
    pub const fn ip(): Ipv4Addr { self.ip }
    pub mut const fn set_ip(ip: Ipv4Addr): Unit { self.ip = ip }
    pub const fn port(): u16 { self.port }
    pub mut const fn set_port(port: u16): Unit { self.port = port }
    pub fn to_socket_addr(): SocketAddr { socket_addr(self.ip, self.port) }
}

extend SocketAddrV6 {
    pub static const fn new(ip: Ipv6Addr, port: u16, flowinfo: u32, scope_id: u32): SocketAddrV6 {
        SocketAddrV6(ip, port, flowinfo, scope_id)
    }
    pub const fn ip(): Ipv6Addr { self.ip }
    pub mut const fn set_ip(ip: Ipv6Addr): Unit { self.ip = ip }
    pub const fn port(): u16 { self.port }
    pub mut const fn set_port(port: u16): Unit { self.port = port }
    pub const fn flowinfo(): u32 { self.flowinfo }
    pub mut const fn set_flowinfo(flowinfo: u32): Unit { self.flowinfo = flowinfo }
    pub const fn scope_id(): u32 { self.scope_id }
    pub mut const fn set_scope_id(scope_id: u32): Unit { self.scope_id = scope_id }
    pub fn to_socket_addr(): SocketAddr {
        socket_addr_v6(self.ip, self.port, self.flowinfo, self.scope_id)
    }
}

extend Ipv4Addr {
    pub const BITS: u32 = 32u32
    pub const BROADCAST: Ipv4Addr = Ipv4Addr(4294967295u32)
    pub const LOCALHOST: Ipv4Addr = Ipv4Addr(2130706433u32)
    pub const UNSPECIFIED: Ipv4Addr = Ipv4Addr(0u32)

    pub static const fn new(a: u8, b: u8, c: u8, d: u8): Ipv4Addr { ipv4(a, b, c, d) }
    pub static const fn from_bits(bits: u32): Ipv4Addr { Ipv4Addr(bits) }
    pub static const fn from_octets(octets: [u8; 4]): Ipv4Addr {
        ipv4(octets[0usize], octets[1usize], octets[2usize], octets[3usize])
    }
    pub const fn to_bits(): u32 { self.bits }
    pub const fn octets(): [u8; 4] {
        [(self.bits >> 24u32) as u8, (self.bits >> 16u32) as u8, (self.bits >> 8u32) as u8, self.bits as u8]
    }
    pub const fn is_loopback(): bool { (self.bits >> 24u32) == 127u32 }
    pub const fn is_unspecified(): bool { self.bits == 0u32 }
    pub const fn is_broadcast(): bool { self.bits == 4294967295u32 }
    pub const fn is_multicast(): bool { (self.bits >> 28u32) == 14u32 }
    pub const fn is_link_local(): bool { (self.bits & 4294901760u32) == 2851995648u32 }
    pub const fn is_private(): bool {
        let a = (self.bits >> 24u32) & 255u32
        let b = (self.bits >> 16u32) & 255u32
        (a == 10u32) || (a == 172u32 && b >= 16u32 && b <= 31u32) ||
            (a == 192u32 && b == 168u32)
    }
    pub const fn is_documentation(): bool {
        let a = (self.bits >> 24u32) & 255u32
        let b = (self.bits >> 16u32) & 255u32
        (a == 192u32 && b == 0u32 && ((self.bits >> 8u32) & 255u32) == 2u32) ||
            (a == 198u32 && b == 51u32 && ((self.bits >> 8u32) & 255u32) == 100u32) ||
            (a == 203u32 && b == 0u32 && ((self.bits >> 8u32) & 255u32) == 113u32)
    }
    pub const fn to_ipv6_compatible(): Ipv6Addr {
        ipv6(0u16, 0u16, 0u16, 0u16, 0u16, 0u16,
             (self.bits >> 16u32) as u16, self.bits as u16)
    }
    pub const fn to_ipv6_mapped(): Ipv6Addr {
        ipv6(0u16, 0u16, 0u16, 0u16, 0u16, 65535u16,
             (self.bits >> 16u32) as u16, self.bits as u16)
    }
    pub fn same(other: Ipv4Addr): bool { self.bits == other.bits }
}

extend Ipv6Addr {
    pub const BITS: u32 = 128u32
    pub const LOCALHOST: Ipv6Addr = Ipv6Addr([
        0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8,
        0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8
    ])
    pub const UNSPECIFIED: Ipv6Addr = Ipv6Addr([0u8; 16])

    pub static const fn new(a: u16, b: u16, c: u16, d: u16, e: u16, f: u16, g: u16, h: u16): Ipv6Addr {
        ipv6(a, b, c, d, e, f, g, h)
    }
    pub static const fn from_bits(bits: u128): Ipv6Addr {
        Ipv6Addr([
            (bits >> 120u32) as u8, (bits >> 112u32) as u8,
            (bits >> 104u32) as u8, (bits >> 96u32) as u8,
            (bits >> 88u32) as u8, (bits >> 80u32) as u8,
            (bits >> 72u32) as u8, (bits >> 64u32) as u8,
            (bits >> 56u32) as u8, (bits >> 48u32) as u8,
            (bits >> 40u32) as u8, (bits >> 32u32) as u8,
            (bits >> 24u32) as u8, (bits >> 16u32) as u8,
            (bits >> 8u32) as u8, bits as u8
        ])
    }
    pub static const fn from_segments(segments: [u16; 8]): Ipv6Addr {
        ipv6(
            segments[0usize], segments[1usize], segments[2usize], segments[3usize],
            segments[4usize], segments[5usize], segments[6usize], segments[7usize]
        )
    }
    pub static const fn from_octets(bytes: [u8; 16]): Ipv6Addr { Ipv6Addr(bytes) }
    pub const fn octets(): [u8; 16] { self.bytes }
    pub const fn to_bits(): u128 {
        var bits = 0u128
        var i = 0usize
        while i < 16usize {
            bits = bits | ((self.bytes[i] as u128) << ((15u32 - i as u32) * 8u32))
            i += 1usize
        }
        bits
    }
    pub const fn segments(): [u16; 8] {
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

    pub const fn is_loopback(): bool {
        var i = 0usize
        while i < 15usize {
            if self.bytes[i] != 0u8 { return false }
            i += 1usize
        }
        self.bytes[15usize] == 1u8
    }

    pub const fn is_unspecified(): bool {
        var i = 0usize
        while i < 16usize {
            if self.bytes[i] != 0u8 { return false }
            i += 1usize
        }
        true
    }

    pub const fn is_multicast(): bool { self.bytes[0usize] == 255u8 }
    pub const fn is_unicast_link_local(): bool {
        self.bytes[0usize] == 254u8 && (self.bytes[1usize] & 192u8) == 128u8
    }
    pub const fn is_unique_local(): bool { (self.bytes[0usize] & 254u8) == 252u8 }
    pub const fn to_ipv4(): Ipv4Addr? {
        var i = 0usize
        while i < 10usize {
            if self.bytes[i] != 0u8 { return none }
            i += 1usize
        }
        let compatible = self.bytes[10usize] == 0u8 && self.bytes[11usize] == 0u8
        let mapped = self.bytes[10usize] == 255u8 && self.bytes[11usize] == 255u8
        if !compatible && !mapped { return none }
        present(ipv4(self.bytes[12usize], self.bytes[13usize], self.bytes[14usize], self.bytes[15usize]))
    }
    pub fn to_ipv4_compatible(): Ipv4Addr? {
        var i = 0usize
        while i < 12usize {
            if self.bytes[i] != 0u8 { return none }
            i += 1usize
        }
        if self.bytes[12usize] == 0u8 && self.bytes[13usize] == 0u8 &&
           self.bytes[14usize] == 0u8 && self.bytes[15usize] <= 1u8 {
            return none
        }
        present(ipv4(self.bytes[12usize], self.bytes[13usize], self.bytes[14usize], self.bytes[15usize]))
    }
    pub const fn to_ipv4_mapped(): Ipv4Addr? {
        var i = 0usize
        while i < 10usize {
            if self.bytes[i] != 0u8 { return none }
            i += 1usize
        }
        if self.bytes[10usize] != 255u8 || self.bytes[11usize] != 255u8 { return none }
        present(ipv4(self.bytes[12usize], self.bytes[13usize], self.bytes[14usize], self.bytes[15usize]))
    }
    pub const fn to_canonical(): IpAddr {
        match self.to_ipv4_mapped() {
            present(address) => IpAddr.V4(address),
            none => IpAddr.V6(self)
        }
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
    pub const fn is_ipv4(): bool { match self { IpAddr.V4(_) => true, _ => false } }
    pub const fn is_ipv6(): bool { match self { IpAddr.V6(_) => true, _ => false } }
    pub const fn is_loopback(): bool {
        match self {
            IpAddr.V4(ip) => ip.is_loopback(),
            IpAddr.V6(ip) => ip.is_loopback()
        }
    }

    pub const fn is_multicast(): bool {
        match self {
            IpAddr.V4(ip) => ip.is_multicast(),
            IpAddr.V6(ip) => ip.is_multicast()
        }
    }
    pub const fn is_unspecified(): bool {
        match self {
            IpAddr.V4(ip) => ip.is_unspecified(),
            IpAddr.V6(ip) => ip.is_unspecified()
        }
    }
    pub const fn to_canonical(): IpAddr {
        match self {
            IpAddr.V4(ip) => IpAddr.V4(ip),
            IpAddr.V6(ip) => ip.to_canonical()
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
    pub static const fn new(ip: IpAddr, port: u16): SocketAddr { socket_addr_ip(ip, port) }
    pub static const fn V4(addr: SocketAddrV4): SocketAddr {
        socket_addr(addr.ip, addr.port)
    }
    pub static const fn V6(addr: SocketAddrV6): SocketAddr {
        SocketAddr(IpAddr.V6(addr.ip), addr.port, addr.flowinfo, addr.scope_id)
    }
    pub const fn ip(): IpAddr { self.ip }
    pub mut const fn set_ip(ip: IpAddr): Unit {
        if self.ip.is_ipv4() != ip.is_ipv4() {
            self.flowinfo = 0u32
            self.scope_id = 0u32
        }
        self.ip = ip
    }
    pub const fn port(): u16 { self.port }
    pub mut const fn set_port(port: u16): Unit { self.port = port }
    pub const fn is_ipv4(): bool { self.ip.is_ipv4() }
    pub const fn is_ipv6(): bool { self.ip.is_ipv6() }
    pub fn same(other: SocketAddr): bool {
        self.ip.same(other.ip) && self.port == other.port &&
            self.flowinfo == other.flowinfo && self.scope_id == other.scope_id
    }
}

fn write_hex16(value: u16, mut f: Formatter): Unit throws core.fmt.Error {
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

fn write_ipv6(value: Ipv6Addr, mut f: Formatter): Unit throws core.fmt.Error {
    var mapped = true
    var byte_index = 0usize
    while byte_index < 10usize {
        if value.bytes[byte_index] != 0u8 { mapped = false }
        byte_index += 1usize
    }
    if mapped && value.bytes[10usize] == 255u8 && value.bytes[11usize] == 255u8 {
        try f.write_str("::ffff:")
        let address = ipv4(value.bytes[12usize], value.bytes[13usize], value.bytes[14usize], value.bytes[15usize])
        return try write_ipv4(address, mut f)
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

fn write_ipv4(value: Ipv4Addr, mut f: Formatter): Unit throws core.fmt.Error {
    let values = value.octets()
    var i = 0usize
    while i < 4usize {
        if i != 0usize { try f.write_char('.') }
        try u8.(Display).fmt(values[i], mut f)
        i += 1usize
    }
}

fn write_socket(value: SocketAddr, mut f: Formatter): Unit throws core.fmt.Error {
    match value.ip {
        IpAddr.V4(ip) => try write_ipv4(ip, mut f),
        IpAddr.V6(ip) => {
            try f.write_char('[')
            try write_ipv6(ip, mut f)
            if value.scope_id != 0u32 {
                try f.write_char('%')
                try u32.(Display).fmt(value.scope_id, mut f)
            }
            try f.write_char(']')
        }
    }
    try f.write_char(':')
    try u16.(Display).fmt(value.port, mut f)
}

interface AddressText {
    fn write_text(mut f: Formatter): Unit throws core.fmt.Error;
}
extend Ipv4Addr implements AddressText {
    fn write_text(mut f: Formatter): Unit throws core.fmt.Error { try write_ipv4(self, mut f) }
}
extend Ipv6Addr implements AddressText {
    fn write_text(mut f: Formatter): Unit throws core.fmt.Error { try write_ipv6(self, mut f) }
}
extend SocketAddr implements AddressText {
    fn write_text(mut f: Formatter): Unit throws core.fmt.Error { try write_socket(self, mut f) }
}

// Renders without the caller's flags, then pads the whole address as one text.
fn pad_address<T: AddressText>(value: T, mut f: Formatter): Unit throws core.fmt.Error {
    var buffer = [0u8; 64]
    var sink = core.fmt.buffer_writer(mut buffer)
    var inner = core.fmt.formatter(mut sink, core.fmt.spec())
    try T.(AddressText).write_text(value, mut inner)
    let length = sink.len()
    match core.fmt.written_text(read buffer, length) {
        present(text) => try f.pad(text),
        none => throw core.fmt.Error()
    }
}

extend Ipv4Addr implements Display {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error { try pad_address(self, mut f) }
}
extend Ipv4Addr implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try Ipv4Addr.(Display).fmt(self, mut f)
    }
}
extend Ipv6Addr implements Display {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error { try pad_address(self, mut f) }
}
extend Ipv6Addr implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try Ipv6Addr.(Display).fmt(self, mut f)
    }
}
extend IpAddr implements Display {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        match self {
            IpAddr.V4(ip) => try Ipv4Addr.(Display).fmt(ip, mut f),
            IpAddr.V6(ip) => try Ipv6Addr.(Display).fmt(ip, mut f)
        }
    }
}
extend IpAddr implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        match self {
            IpAddr.V4(ip) => try Ipv4Addr.(Debug).fmt(ip, mut f),
            IpAddr.V6(ip) => try Ipv6Addr.(Debug).fmt(ip, mut f)
        }
    }
}
extend SocketAddr implements Display {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error { try pad_address(self, mut f) }
}
extend SocketAddr implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try SocketAddr.(Display).fmt(self, mut f)
    }
}
extend SocketAddrV4 implements Display {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try SocketAddr.(Display).fmt(self.to_socket_addr(), mut f)
    }
}
extend SocketAddrV4 implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try SocketAddrV4.(Display).fmt(self, mut f)
    }
}
extend SocketAddrV6 implements Display {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try SocketAddr.(Display).fmt(self.to_socket_addr(), mut f)
    }
}
extend SocketAddrV6 implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try SocketAddrV6.(Display).fmt(self, mut f)
    }
}


extend Ipv4Addr implements PartialEq {
    fn eq(read other: Ipv4Addr): bool { self.bits == other.bits }
}
extend Ipv4Addr implements Eq {}
extend Ipv4Addr implements PartialOrd {
    fn partial_cmp(read other: Ipv4Addr): Ordering? { present(self.cmp(other)) }
}
extend Ipv4Addr implements Ord {
    fn cmp(read other: Ipv4Addr): Ordering { self.bits.cmp(other.bits) }
}
extend Ipv4Addr implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.bits.hash(mut state) }
}
extend Ipv4Addr implements Not {
    type Output = Ipv4Addr
    fn not(): Ipv4Addr { Ipv4Addr(!self.bits) }
}
extend Ipv4Addr implements BitAnd<Ipv4Addr> {
    type Output = Ipv4Addr
    fn bitand(read rhs: Ipv4Addr): Ipv4Addr { Ipv4Addr(self.bits & rhs.bits) }
}
extend Ipv4Addr implements BitOr<Ipv4Addr> {
    type Output = Ipv4Addr
    fn bitor(read rhs: Ipv4Addr): Ipv4Addr { Ipv4Addr(self.bits | rhs.bits) }
}
extend Ipv4Addr implements BitAndAssign<Ipv4Addr> {
    mut fn bitand_assign(read rhs: Ipv4Addr): Unit { self.bits = self.bits & rhs.bits }
}
extend Ipv4Addr implements BitOrAssign<Ipv4Addr> {
    mut fn bitor_assign(read rhs: Ipv4Addr): Unit { self.bits = self.bits | rhs.bits }
}
extend Ipv4Addr implements From<u32> {
    static fn from(take value: u32): Ipv4Addr { Ipv4Addr(value) }
}
extend u32 implements From<Ipv4Addr> {
    static fn from(take value: Ipv4Addr): u32 { value.to_bits() }
}
extend Ipv4Addr implements From<[u8; 4]> {
    static fn from(take value: [u8; 4]): Ipv4Addr { Ipv4Addr.from_octets(value) }
}
extend Ipv6Addr implements PartialEq {
    fn eq(read other: Ipv6Addr): bool { self.to_bits() == other.to_bits() }
}
extend Ipv6Addr implements Eq {}
extend Ipv6Addr implements PartialOrd {
    fn partial_cmp(read other: Ipv6Addr): Ordering? { present(self.cmp(other)) }
}
extend Ipv6Addr implements Ord {
    fn cmp(read other: Ipv6Addr): Ordering { self.to_bits().cmp(other.to_bits()) }
}
extend Ipv6Addr implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.to_bits().hash(mut state) }
}
extend Ipv6Addr implements Not {
    type Output = Ipv6Addr
    fn not(): Ipv6Addr { Ipv6Addr.from_bits(!self.to_bits()) }
}
extend Ipv6Addr implements BitAnd<Ipv6Addr> {
    type Output = Ipv6Addr
    fn bitand(read rhs: Ipv6Addr): Ipv6Addr { Ipv6Addr.from_bits(self.to_bits() & rhs.to_bits()) }
}
extend Ipv6Addr implements BitOr<Ipv6Addr> {
    type Output = Ipv6Addr
    fn bitor(read rhs: Ipv6Addr): Ipv6Addr { Ipv6Addr.from_bits(self.to_bits() | rhs.to_bits()) }
}
extend Ipv6Addr implements BitAndAssign<Ipv6Addr> {
    mut fn bitand_assign(read rhs: Ipv6Addr): Unit {
        self.bytes = Ipv6Addr.from_bits(self.to_bits() & rhs.to_bits()).bytes
    }
}
extend Ipv6Addr implements BitOrAssign<Ipv6Addr> {
    mut fn bitor_assign(read rhs: Ipv6Addr): Unit {
        self.bytes = Ipv6Addr.from_bits(self.to_bits() | rhs.to_bits()).bytes
    }
}
extend Ipv6Addr implements From<u128> {
    static fn from(take value: u128): Ipv6Addr { Ipv6Addr.from_bits(value) }
}
extend u128 implements From<Ipv6Addr> {
    static fn from(take value: Ipv6Addr): u128 { value.to_bits() }
}
extend Ipv6Addr implements From<[u8; 16]> {
    static fn from(take value: [u8; 16]): Ipv6Addr { Ipv6Addr.from_octets(value) }
}
extend Ipv6Addr implements From<[u16; 8]> {
    static fn from(take value: [u16; 8]): Ipv6Addr { Ipv6Addr.from_segments(value) }
}
extend IpAddr implements PartialEq {
    fn eq(read other: IpAddr): bool { self.same(other) }
}
extend IpAddr implements Eq {}
extend IpAddr implements PartialOrd {
    fn partial_cmp(read other: IpAddr): Ordering? { present(self.cmp(other)) }
}
extend IpAddr implements PartialEq<Ipv4Addr> {
    fn eq(read other: Ipv4Addr): bool {
        match self { IpAddr.V4(ip) => ip == other, IpAddr.V6(_) => false }
    }
}
extend IpAddr implements PartialEq<Ipv6Addr> {
    fn eq(read other: Ipv6Addr): bool {
        match self { IpAddr.V6(ip) => ip == other, IpAddr.V4(_) => false }
    }
}
extend IpAddr implements PartialOrd<Ipv4Addr> {
    fn partial_cmp(read other: Ipv4Addr): Ordering? {
        match self {
            IpAddr.V4(ip) => present(ip.cmp(other)),
            IpAddr.V6(_) => present(Ordering.Greater)
        }
    }
}
extend IpAddr implements PartialOrd<Ipv6Addr> {
    fn partial_cmp(read other: Ipv6Addr): Ordering? {
        match self {
            IpAddr.V4(_) => present(Ordering.Less),
            IpAddr.V6(ip) => present(ip.cmp(other))
        }
    }
}
extend Ipv4Addr implements PartialEq<IpAddr> {
    fn eq(read other: IpAddr): bool {
        match other {
            IpAddr.V4(ip) => self == ip,
            IpAddr.V6(_) => false
        }
    }
}
extend Ipv4Addr implements PartialOrd<IpAddr> {
    fn partial_cmp(read other: IpAddr): Ordering? {
        match other {
            IpAddr.V4(ip) => present(self.cmp(ip)),
            IpAddr.V6(_) => present(Ordering.Less)
        }
    }
}
extend Ipv6Addr implements PartialEq<IpAddr> {
    fn eq(read other: IpAddr): bool {
        match other {
            IpAddr.V4(_) => false,
            IpAddr.V6(ip) => self == ip
        }
    }
}
extend Ipv6Addr implements PartialOrd<IpAddr> {
    fn partial_cmp(read other: IpAddr): Ordering? {
        match other {
            IpAddr.V4(_) => present(Ordering.Greater),
            IpAddr.V6(ip) => present(self.cmp(ip))
        }
    }
}
extend IpAddr implements Ord {
    fn cmp(read other: IpAddr): Ordering {
        match self {
            IpAddr.V4(a) => match other {
                IpAddr.V4(b) => a.cmp(b),
                IpAddr.V6(_) => Ordering.Less
            },
            IpAddr.V6(a) => match other {
                IpAddr.V4(_) => Ordering.Greater,
                IpAddr.V6(b) => a.cmp(b)
            }
        }
    }
}
extend IpAddr implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        match self {
            IpAddr.V4(ip) => {
                state.write_u8(4u8)
                ip.hash(mut state)
            },
            IpAddr.V6(ip) => {
                state.write_u8(6u8)
                ip.hash(mut state)
            }
        }
    }
}
extend IpAddr implements From<Ipv4Addr> {
    static fn from(take value: Ipv4Addr): IpAddr { IpAddr.V4(value) }
}
extend IpAddr implements From<Ipv6Addr> {
    static fn from(take value: Ipv6Addr): IpAddr { IpAddr.V6(value) }
}
extend IpAddr implements From<[u8; 4]> {
    static fn from(take value: [u8; 4]): IpAddr { IpAddr.V4(Ipv4Addr.from_octets(value)) }
}
extend IpAddr implements From<[u8; 16]> {
    static fn from(take value: [u8; 16]): IpAddr { IpAddr.V6(Ipv6Addr.from_octets(value)) }
}
extend IpAddr implements From<[u16; 8]> {
    static fn from(take value: [u16; 8]): IpAddr { IpAddr.V6(Ipv6Addr.from_segments(value)) }
}
extend SocketAddrV4 implements PartialEq {
    fn eq(read other: SocketAddrV4): bool {
        self.ip == other.ip && self.port == other.port
    }
}
extend SocketAddrV4 implements Eq {}
extend SocketAddrV4 implements PartialOrd {
    fn partial_cmp(read other: SocketAddrV4): Ordering? { present(self.cmp(other)) }
}
extend SocketAddrV4 implements Ord {
    fn cmp(read other: SocketAddrV4): Ordering {
        self.ip.cmp(other.ip).then(self.port.cmp(other.port))
    }
}
extend SocketAddrV4 implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.ip.hash(mut state)
        self.port.hash(mut state)
    }
}
extend SocketAddr implements PartialEq {
    fn eq(read other: SocketAddr): bool { self.same(other) }
}
extend SocketAddr implements Eq {}
extend SocketAddr implements PartialOrd {
    fn partial_cmp(read other: SocketAddr): Ordering? { present(self.cmp(other)) }
}
extend SocketAddr implements Ord {
    fn cmp(read other: SocketAddr): Ordering {
        let by_ip = self.ip.cmp(other.ip)
        let by_port = by_ip.then(self.port.cmp(other.port))
        let by_flow = by_port.then(self.flowinfo.cmp(other.flowinfo))
        by_flow.then(self.scope_id.cmp(other.scope_id))
    }
}
extend SocketAddr implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.ip.hash(mut state)
        self.port.hash(mut state)
        self.flowinfo.hash(mut state)
        self.scope_id.hash(mut state)
    }
}
extend SocketAddr implements From<SocketAddrV4> {
    static fn from(take value: SocketAddrV4): SocketAddr {
        socket_addr(value.ip, value.port)
    }
}
extend SocketAddr implements From<SocketAddrV6> {
    static fn from(take value: SocketAddrV6): SocketAddr {
        socket_addr_v6(value.ip, value.port, value.flowinfo, value.scope_id)
    }
}
extend<I: Into<IpAddr>> SocketAddr implements From<(I, u16)> {
    static fn from(take value: (I, u16)): SocketAddr {
        socket_addr_ip(value.0.into(), value.1)
    }
}
extend SocketAddrV6 implements PartialEq {
    fn eq(read other: SocketAddrV6): bool {
        self.ip == other.ip && self.port == other.port &&
            self.flowinfo == other.flowinfo && self.scope_id == other.scope_id
    }
}
extend SocketAddrV6 implements Eq {}
extend SocketAddrV6 implements PartialOrd {
    fn partial_cmp(read other: SocketAddrV6): Ordering? { present(self.cmp(other)) }
}
extend SocketAddrV6 implements Ord {
    fn cmp(read other: SocketAddrV6): Ordering {
        let by_ip = self.ip.cmp(other.ip)
        let by_port = by_ip.then(self.port.cmp(other.port))
        let by_flow = by_port.then(self.flowinfo.cmp(other.flowinfo))
        by_flow.then(self.scope_id.cmp(other.scope_id))
    }
}
extend SocketAddrV6 implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.ip.hash(mut state)
        self.port.hash(mut state)
        self.flowinfo.hash(mut state)
        self.scope_id.hash(mut state)
    }
}
extend Ipv4Addr implements Clone {
    fn clone(): Ipv4Addr { self }
}
extend Ipv6Addr implements Clone {
    fn clone(): Ipv6Addr { self }
}
extend IpAddr implements Clone {
    fn clone(): IpAddr { self }
}
extend SocketAddr implements Clone {
    fn clone(): SocketAddr { self }
}
extend SocketAddrV4 implements Clone {
    fn clone(): SocketAddrV4 { self }
}
extend SocketAddrV6 implements Clone {
    fn clone(): SocketAddrV6 { self }
}
