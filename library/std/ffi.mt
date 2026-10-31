// Operating-system strings: arbitrary bytes (never required to be Unicode)
// that round-trip losslessly. `OsStr` is the unsized view, `OsString` the
// owner. Interior NUL bytes are representable here and rejected only where a
// C string is required (`cstring`).
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.alloc.AllocError
import package.alloc.string.String
import package.alloc.string.FromUtf8Error
import package.core.text.Text
import package.core.slice
import super.io
import super.io.ErrorKind

pub type OsStr { bytes: [u8] }

// Any byte sequence is a valid OS string.
pub fn os_str(bytes: read [u8]): read OsStr from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read OsStr>>(fat) }
    unsafe { read *view }
}

pub fn os_str_mut(bytes: mut [u8]): mut OsStr from bytes {
    let fat = core.ptr.from_mut(bytes)
    let view = unsafe { core.mem.transmute<ptr<mut OsStr>>(fat) }
    unsafe { mut *view }
}

pub fn os_str_from_text(text: read Text): read OsStr from text { os_str(text.as_bytes()) }
pub fn os_str_from_encoded_bytes_unchecked(bytes: read [u8]): read OsStr from bytes {
    os_str(bytes)
}

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
    pub static fn new(bytes: read [u8]): read OsStr from bytes { os_str(bytes) }
    pub static fn from_encoded_bytes_unchecked(bytes: read [u8]): read OsStr from bytes {
        os_str_from_encoded_bytes_unchecked(bytes)
    }
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn as_encoded_bytes(): read [u8] from self { read self.bytes }
    pub fn len(): usize { self.bytes.len() }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn is_ascii(): bool {
        var i = 0usize
        while i < self.bytes.len() {
            if self.bytes[i] > 127u8 { return false }
            i += 1usize
        }
        true
    }
    // The text when the bytes are well-formed UTF-8.
    pub fn to_str(): (read Text from self)? { package.core.text.from_utf8(read self.bytes) }
    pub fn to_string_lossy(): String { lossy(read self.bytes) }
    pub fn display(): String { self.to_string_lossy() }
    pub fn to_os_string(): OsString { os_string_from_bytes(read self.bytes) }
    pub fn into_os_string(): OsString { self.to_os_string() }
    pub fn same(other: read OsStr): bool { bytes_equal(read self.bytes, other.as_bytes()) }
    pub fn eq_ignore_ascii_case(other: read OsStr): bool {
        let right = other.as_bytes()
        if self.bytes.len() != right.len() { return false }
        var i = 0usize
        while i < self.bytes.len() {
            let a = ascii_lower(self.bytes[i])
            let b = ascii_lower(right[i])
            if a != b { return false }
            i += 1usize
        }
        true
    }
    pub fn to_ascii_lowercase(): OsString {
        let result = os_string_from_bytes(read self.bytes)
        var output = result
        output.make_ascii_lowercase()
        output
    }
    pub fn to_ascii_uppercase(): OsString {
        let result = os_string_from_bytes(read self.bytes)
        var output = result
        output.make_ascii_uppercase()
        output
    }
    pub mut fn make_ascii_lowercase(): Unit {
        var i = 0usize
        while i < self.bytes.len() {
            self.bytes[i] = ascii_lower(self.bytes[i])
            i += 1usize
        }
    }
    pub mut fn make_ascii_uppercase(): Unit {
        var i = 0usize
        while i < self.bytes.len() {
            self.bytes[i] = ascii_upper(self.bytes[i])
            i += 1usize
        }
    }
}

fn ascii_lower(value: u8): u8 {
    if value >= 65u8 && value <= 90u8 { value + 32u8 } else { value }
}

fn ascii_upper(value: u8): u8 {
    if value >= 97u8 && value <= 122u8 { value - 32u8 } else { value }
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

pub type OsString { v: List<u8> }

pub fn new_os_string(): OsString { OsString(vec.new<u8>()) }
pub fn os_string_with_capacity(capacity: usize): OsString {
    OsString(vec.with_capacity<u8>(capacity))
}
pub fn os_string_from_encoded_bytes_unchecked(bytes: take List<u8>): OsString {
    OsString(bytes)
}

pub fn os_string_from_bytes(bytes: read [u8]): OsString {
    var v = vec.with_capacity<u8>(bytes.len())
    v.extend_from_slice(bytes)
    OsString(v)
}

pub fn os_string_from_text(text: read Text): OsString { os_string_from_bytes(text.as_bytes()) }

pub fn os_string_from_vec(bytes: take List<u8>): OsString { OsString(bytes) }

extend OsString {
    pub static fn new(): OsString { new_os_string() }
    pub static fn with_capacity(capacity: usize): OsString { os_string_with_capacity(capacity) }
    pub static fn from_encoded_bytes_unchecked(bytes: take List<u8>): OsString {
        os_string_from_encoded_bytes_unchecked(bytes)
    }
    pub fn as_os_str(): read OsStr from self { os_str(self.v.as_slice()) }
    pub mut fn as_mut_os_str(): mut OsStr from self { os_str_mut(self.v.as_mut_slice()) }
    pub fn as_bytes(): read [u8] from self { self.v.as_slice() }
    pub fn as_encoded_bytes(): read [u8] from self { self.v.as_slice() }
    pub fn capacity(): usize { self.v.capacity() }
    pub fn len(): usize { self.v.len() }
    pub fn is_empty(): bool { self.v.is_empty() }
    pub fn is_ascii(): bool { self.as_os_str().is_ascii() }
    pub fn display(): String { self.as_os_str().display() }
    pub fn to_str(): (read Text from self)? { self.as_os_str().to_str() }
    pub fn to_string_lossy(): String { self.as_os_str().to_string_lossy() }
    pub fn to_os_string(): OsString { os_string_from_bytes(self.as_bytes()) }
    pub fn eq_ignore_ascii_case(other: read OsString): bool {
        self.as_os_str().eq_ignore_ascii_case(other.as_os_str())
    }
    pub mut fn push_bytes(bytes: read [u8]): Unit { self.v.extend_from_slice(bytes) }
    pub mut fn push(s: read OsStr): Unit { self.v.extend_from_slice(s.as_bytes()) }
    pub mut fn clear(): Unit { self.v.clear() }
    pub mut fn reserve(extra: usize): Unit { self.v.reserve(extra) }
    pub mut fn reserve_exact(extra: usize): Unit { self.v.reserve_exact(extra) }
    pub mut fn try_reserve(extra: usize): Unit throws AllocError { try self.v.try_reserve(extra) }
    pub mut fn try_reserve_exact(extra: usize): Unit throws AllocError {
        try self.v.try_reserve_exact(extra)
    }
    pub mut fn shrink_to_fit(): Unit { self.v.shrink_to_fit() }
    pub mut fn shrink_to(minimum: usize): Unit {
        if minimum > self.v.capacity() {
            self.v.reserve(minimum - self.v.len())
        } else if minimum <= self.v.len() {
            self.v.shrink_to_fit()
        }
    }
    pub mut fn make_ascii_lowercase(): Unit {
        var i = 0usize
        while i < self.v.len() {
            self.v[i] = ascii_lower(self.v[i])
            i += 1usize
        }
    }
    pub mut fn make_ascii_uppercase(): Unit {
        var i = 0usize
        while i < self.v.len() {
            self.v[i] = ascii_upper(self.v[i])
            i += 1usize
        }
    }
    pub fn to_ascii_lowercase(): OsString {
        let result = os_string_from_bytes(self.as_bytes())
        var output = result
        output.make_ascii_lowercase()
        output
    }
    pub fn to_ascii_uppercase(): OsString {
        let result = os_string_from_bytes(self.as_bytes())
        var output = result
        output.make_ascii_uppercase()
        output
    }
    pub take fn into_boxed_os_str(): package.alloc.boxed.Box<OsStr> {
        let boxed = self.v.into_boxed_slice()
        unsafe { core.mem.transmute<package.alloc.boxed.Box<OsStr>>(boxed) }
    }
    pub take fn into_bytes(): List<u8> { self.v }
    pub take fn into_encoded_bytes(): List<u8> { self.v }
    pub take fn into_string(): String throws FromUtf8Error {
        try package.alloc.string.from_utf8(self.v)
    }
    pub fn same(other: read OsString): bool { bytes_equal(self.v.as_slice(), other.as_bytes()) }
}

// A NUL-terminated copy of `bytes` for passing to C.
pub fn cstring(bytes: read [u8]): List<u8> throws io.Error {
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

// `interior` marks a zero byte before the final terminator. A missing
// terminator uses `interior == false` and `position == bytes.len()`.
pub copy type CStrError { pub position: usize; pub interior: bool }

// Unsized NUL-terminated byte string. The bytes include the trailing zero,
// and no earlier byte is zero.
pub type CStr { bytes: [u8] }

fn nul_at(bytes: read [u8]): usize? {
    var index = 0usize
    while index < bytes.len() {
        if bytes[index] == 0u8 { return present(index) }
        index += 1usize
    }
    none
}

fn check_terminated(bytes: read [u8]): Unit throws CStrError {
    if bytes.len() == 0usize || bytes[bytes.len() - 1usize] != 0u8 {
        throw CStrError(bytes.len(), false)
    }
    var index = 0usize
    while index + 1usize < bytes.len() {
        if bytes[index] == 0u8 { throw CStrError(index, true) }
        index += 1usize
    }
}

pub fn c_str_from_bytes_with_nul(bytes: read [u8]): read CStr from bytes throws CStrError {
    try check_terminated(bytes)
    unsafe { c_str_from_bytes_with_nul_unchecked(bytes) }
}

// Safety: `bytes` ends in NUL and contains no earlier NUL.
pub unsafe fn c_str_from_bytes_with_nul_unchecked(bytes: read [u8]): read CStr from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read CStr>>(fat) }
    unsafe { read *view }
}

pub fn c_str_from_bytes_until_nul(bytes: read [u8]): (read CStr from bytes)? {
    match nul_at(bytes) {
        present(index) => present(unsafe {
            c_str_from_bytes_with_nul_unchecked(
                package.core.slice.subslice_unchecked(bytes, 0usize, index + 1usize))
        }),
        none => none
    }
}

// Safety: `ptr` points at a NUL-terminated string that stays valid for `r`.
pub unsafe fn c_str_from_ptr<region r>(ptr: ptr<read u8>): read CStr from r {
    var length = 0usize
    while unsafe { *ptr.add(length) } != 0u8 { length += 1usize }
    let bytes = unsafe { package.core.slice.from_raw_parts<r, u8>(ptr, length + 1usize) }
    unsafe { c_str_from_bytes_with_nul_unchecked(bytes) }
}

extend CStr {
    pub static fn from_bytes_with_nul(bytes: read [u8]): read CStr from bytes throws CStrError {
        try c_str_from_bytes_with_nul(bytes)
    }
    pub unsafe static fn from_bytes_with_nul_unchecked(bytes: read [u8]): read CStr from bytes {
        unsafe { c_str_from_bytes_with_nul_unchecked(bytes) }
    }
    pub static fn from_bytes_until_nul(bytes: read [u8]): (read CStr from bytes)? {
        c_str_from_bytes_until_nul(bytes)
    }
    pub unsafe static fn from_ptr<region r>(pointer: ptr<read u8>): read CStr from r {
        unsafe { c_str_from_ptr<r>(pointer) }
    }
    pub fn to_bytes_with_nul(): read [u8] from self { read self.bytes }
    pub fn to_bytes(): read [u8] from self {
        let end = self.bytes.len() - 1usize
        unsafe { package.core.slice.subslice_unchecked(read self.bytes, 0usize, end) }
    }
    pub fn count_bytes(): usize { self.bytes.len() - 1usize }
    pub fn to_str(): (read Text from self)? { package.core.text.from_utf8(self.to_bytes()) }
    pub fn to_string_lossy(): String { lossy(self.to_bytes()) }
    pub fn into_c_string(): CString {
        var owned = vec.with_capacity<u8>(self.bytes.len())
        owned.extend_from_slice(read self.bytes)
        CString(owned)
    }
}

// Owned NUL-terminated bytes with no interior NUL. The stored list includes
// the trailing zero.
pub type CString { bytes: List<u8> }

pub fn c_string_from_bytes(bytes: read [u8]): CString throws CStrError {
    match nul_at(bytes) {
        present(index) => { throw CStrError(index, true) },
        none => {}
    }
    var owned = vec.with_capacity<u8>(bytes.len() + 1usize)
    owned.extend_from_slice(bytes)
    owned.push(0u8)
    CString(owned)
}

extend CString {
    // Safety: `bytes` has no interior NUL. A trailing NUL is appended.
    pub unsafe static fn from_vec_unchecked(bytes: take List<u8>): CString {
        var owned = bytes
        owned.push(0u8)
        CString(owned)
    }
    pub static fn from_vec_with_nul(bytes: take List<u8>): CString throws CStrError {
        try check_terminated(bytes.as_slice())
        CString(bytes)
    }
    // Safety: `bytes` ends in NUL and contains no earlier NUL.
    pub unsafe static fn from_vec_with_nul_unchecked(bytes: take List<u8>): CString {
        CString(bytes)
    }
    pub fn as_bytes_with_nul(): read [u8] from self { self.bytes.as_slice() }
    pub fn as_bytes(): read [u8] from self { self.as_c_str().to_bytes() }
    pub fn as_c_str(): read CStr from self {
        unsafe { c_str_from_bytes_with_nul_unchecked(self.bytes.as_slice()) }
    }
    pub fn count_bytes(): usize { self.as_c_str().count_bytes() }
    pub take fn into_bytes_with_nul(): List<u8> {
        unsafe {
            let bytes = core.ptr.`read`(core.ptr.from_ref(self.bytes))
            core.mem.forget(take self)
            bytes
        }
    }
    pub take fn into_bytes(): List<u8> {
        var bytes = self.into_bytes_with_nul()
        let _ = bytes.pop()
        bytes
    }
    pub take fn into_boxed_c_str(): package.alloc.boxed.Box<CStr> {
        let boxed = self.into_bytes_with_nul().into_boxed_slice()
        unsafe { core.mem.transmute<package.alloc.boxed.Box<CStr>>(boxed) }
    }
}
