// Operating-system strings: arbitrary bytes (never required to be Unicode)
// that round-trip losslessly. `OsStr` is the unsized view, `OsString` the
// owner. Interior NUL bytes are representable here and rejected only where a
// C string is required (`cstring`).
import package.alloc.vec;
import package.alloc.vec.Vec;
import package.alloc.string.String;
import package.core.text.Text;
import package.core.slice;
import super.io;
import super.io.ErrorKind;

pub type OsStr { bytes: [u8] }

// Any byte sequence is a valid OS string.
pub fn os_str(bytes: read [u8]): read OsStr from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read OsStr>>(fat) }
    unsafe { read *view }
}

pub fn os_str_from_text(text: read Text): read OsStr from text { os_str(text.as_bytes()) }

fn push_replacement(out: mut String): Unit { out.push('\u{fffd}') }

// Decodes `bytes`, replacing each ill-formed byte with U+FFFD.
pub fn lossy(bytes: read [u8]): String {
    var out = package.alloc.string.with_capacity(bytes.len())
    var i = 0usize
    while i < bytes.len() {
        var width = 1usize
        var matched = false
        while width <= 4usize && i + width <= bytes.len() && !matched {
            match package.core.text.from_utf8(unsafe { slice.subslice_unchecked(bytes, i, i + width) }) {
                present(t) => { out.push_str(t); matched = true },
                none => { width += 1usize }
            }
        }
        if matched { i += width } else { push_replacement(out); i += 1usize }
    }
    out
}

extend OsStr {
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn len(): usize { self.bytes.len() }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    // The text when the bytes are well-formed UTF-8.
    pub fn to_str(): (read Text from self)? { package.core.text.from_utf8(read self.bytes) }
    pub fn to_string_lossy(): String { lossy(read self.bytes) }
    pub fn to_os_string(): OsString { os_string_from_bytes(read self.bytes) }
    pub fn same(other: read OsStr): bool { bytes_equal(read self.bytes, other.as_bytes()) }
}

pub fn bytes_equal(a: read [u8], b: read [u8]): bool {
    if a.len() != b.len() { return false }
    var i = 0usize
    while i < a.len() {
        if a[i] != b[i] { return false }
        i += 1usize
    }
    true
}

pub type OsString { v: Vec<u8> }

pub fn new_os_string(): OsString { OsString(vec.new<u8>()) }

pub fn os_string_from_bytes(bytes: read [u8]): OsString {
    var v = vec.with_capacity<u8>(bytes.len())
    v.extend_from_slice(bytes)
    OsString(v)
}

pub fn os_string_from_text(text: read Text): OsString { os_string_from_bytes(text.as_bytes()) }

pub fn os_string_from_vec(bytes: take Vec<u8>): OsString { OsString(bytes) }

extend OsString {
    pub fn as_os_str(): read OsStr from self { os_str(self.v.as_slice()) }
    pub fn as_bytes(): read [u8] from self { self.v.as_slice() }
    pub fn len(): usize { self.v.len() }
    pub fn is_empty(): bool { self.v.is_empty() }
    pub mut fn push_bytes(bytes: read [u8]): Unit { self.v.extend_from_slice(bytes) }
    pub mut fn push(s: read OsStr): Unit { self.v.extend_from_slice(s.as_bytes()) }
    pub take fn into_bytes(): Vec<u8> { self.v }
    pub fn same(other: read OsString): bool { bytes_equal(self.v.as_slice(), other.as_bytes()) }
}

// A NUL-terminated copy of `bytes` for passing to C.
pub fn cstring(bytes: read [u8]): Vec<u8> throws io.Error {
    var out = vec.with_capacity<u8>(bytes.len() + 1usize)
    var i = 0usize
    while i < bytes.len() {
        if bytes[i] == 0u8 { throw io.from_kind(ErrorKind.InvalidInput) }
        i += 1usize
    }
    out.extend_from_slice(bytes)
    out.push(0u8)
    out
}
