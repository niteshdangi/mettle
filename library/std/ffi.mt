// Operating-system strings: arbitrary bytes (never required to be Unicode)
// that round-trip losslessly. `OsStr` is the unsized view, `OsString` the
// owner. Interior NUL bytes are representable here and rejected only where a
// C string is required (`cstring`).
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.alloc.AllocError
import package.alloc.string.String
import package.alloc.string.FromUtf8Error
import package.core.convert.Into
import package.core.clone.Clone
import package.core.default.Default
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.hash.{Hash, Hasher}
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
    pub take fn into_bytes(): List<u8> { self.v }
    pub take fn into_encoded_bytes(): List<u8> { self.v }
    pub take fn into_string(): String throws FromUtf8Error {
        try package.alloc.string.from_utf8(self.v)
    }
    pub fn same(other: read OsString): bool { bytes_equal(self.v.as_slice(), other.as_bytes()) }
}

pub copy enum FromBytesWithNulError {
    InteriorNul { position: usize },
    NotNulTerminated
}

pub copy type FromBytesUntilNulError {}

pub type NulError {
    bytes: List<u8>
    position: usize
}

copy enum NulErrorKind { InteriorNul, NotTerminated }

extend NulError {
    pub fn nul_position(): usize { self.position }
    pub take fn into_vec(): List<u8> { self.bytes }
}

pub type FromVecWithNulError {
    bytes: List<u8>
    kind: NulErrorKind
}

extend FromVecWithNulError {
    pub fn as_bytes(): read [u8] from self { self.bytes.as_slice() }
    pub take fn into_bytes(): List<u8> { self.bytes }
}

pub type IntoStringError { value: CString }

extend IntoStringError {
    pub fn as_c_str<region r>(
        receiver self: read IntoStringError from r
    ): CStr<region r> { self.value.as_c_str() }
    pub take fn into_cstring(): CString { self.value }
}

// A borrowed, validated NUL-terminated byte string. Construction is restricted
// to the validating constructors below; the terminator is part of `bytes`.
pub type CStr<region r> { bytes: read [u8] from r }

// Owned C strings always contain one final NUL and no earlier NUL.
pub type CString { v: List<u8> }

fn clone_bytes(bytes: read [u8]): List<u8> {
    var duplicate = vec.with_capacity<u8>(bytes.len())
    duplicate.extend_from_slice(bytes)
    duplicate
}

fn c_str_from_bytes_with_nul<region r>(
    bytes: read [u8] from r
): CStr<region r> throws FromBytesWithNulError {
    if bytes.is_empty() {
        throw FromBytesWithNulError.NotNulTerminated
    }
    let terminator = bytes.len() - 1usize
    var i = 0usize
    while i < terminator {
        if bytes[i] == 0u8 {
            throw FromBytesWithNulError.InteriorNul(i)
        }
        i += 1usize
    }
    if bytes[terminator] != 0u8 {
        throw FromBytesWithNulError.NotNulTerminated
    }
    CStr(read bytes)
}

fn c_str_from_bytes_until_nul<region r>(
    bytes: read [u8] from r
): CStr<region r> throws FromBytesUntilNulError {
    var i = 0usize
    while i < bytes.len() && bytes[i] != 0u8 { i += 1usize }
    if i == bytes.len() { throw FromBytesUntilNulError() }
    match slice.subslice(bytes, 0usize, i + 1usize) {
        present(terminated) => CStr(terminated),
        none => throw FromBytesUntilNulError()
    }
}

extend<region r> CStr<region r> {
    pub static fn from_bytes_with_nul<region s>(
        bytes: read [u8] from s
    ): CStr<region s> throws FromBytesWithNulError {
        try c_str_from_bytes_with_nul(bytes)
    }

    pub static fn from_bytes_until_nul<region s>(
        bytes: read [u8] from s
    ): CStr<region s> throws FromBytesUntilNulError {
        try c_str_from_bytes_until_nul(bytes)
    }

    pub fn as_ptr(): ptr<read i8> { self.bytes.as_ptr().cast<i8>() }
    pub fn count_bytes(): usize { self.bytes.len() - 1usize }
    pub fn is_empty(): bool { self.bytes.len() == 1usize }
    pub fn to_bytes_with_nul(): read [u8] from r { self.bytes }
    pub fn to_bytes(): read [u8] from r {
        match slice.subslice(self.bytes, 0usize, self.bytes.len() - 1usize) {
            present(bytes) => bytes,
            none => package.core.panic.panic("invalid C string")
        }
    }
    pub fn to_str(): (read Text from r)? {
        package.core.text.from_utf8(self.to_bytes())
    }
    pub fn to_string_lossy(): String { lossy(self.to_bytes()) }
    pub fn to_owned(): CString { CString(clone_bytes(self.bytes)) }
}

fn c_string_new(bytes: take List<u8>): CString throws NulError {
    var owned = bytes
    var i = 0usize
    while i < owned.len() {
        if owned[i] == 0u8 { throw NulError(owned, i) }
        i += 1usize
    }
    owned.push(0u8)
    CString(owned)
}

fn c_string_from_vec_with_nul(
    bytes: take List<u8>
): CString throws FromVecWithNulError {
    if bytes.is_empty() {
        throw FromVecWithNulError(bytes, NulErrorKind.NotTerminated)
    }
    let terminator = bytes.len() - 1usize
    var i = 0usize
    while i < terminator {
        if bytes[i] == 0u8 {
            throw FromVecWithNulError(bytes, NulErrorKind.InteriorNul)
        }
        i += 1usize
    }
    if bytes[terminator] != 0u8 {
        throw FromVecWithNulError(bytes, NulErrorKind.NotTerminated)
    }
    CString(bytes)
}

fn new_c_string(): CString {
    var bytes = vec.new<u8>()
    bytes.push(0u8)
    CString(bytes)
}

extend CString {
    pub static fn new<T: Into<List<u8>>>(bytes: take T): CString throws NulError {
        try c_string_new(bytes.into())
    }

    pub static fn from_vec_with_nul(
        bytes: take List<u8>
    ): CString throws FromVecWithNulError {
        try c_string_from_vec_with_nul(bytes)
    }

    pub fn as_c_str<region r>(
        receiver self: read CString from r
    ): CStr<region r> { CStr(self.v.as_slice()) }
    pub fn as_ptr(): ptr<read i8> { self.v.as_ptr().cast<i8>() }
    pub fn count_bytes(): usize { self.v.len() - 1usize }
    pub fn is_empty(): bool { self.v.len() == 1usize }
    pub fn as_bytes_with_nul(): read [u8] from self { self.v.as_slice() }
    pub fn as_bytes(): read [u8] from self {
        match slice.subslice(self.v.as_slice(), 0usize, self.v.len() - 1usize) {
            present(bytes) => bytes,
            none => package.core.panic.panic("invalid C string")
        }
    }
    pub fn to_str(): (read Text from self)? {
        package.core.text.from_utf8(self.as_bytes())
    }
    pub fn to_string_lossy(): String { lossy(self.as_bytes()) }
    pub take fn into_bytes_with_nul(): List<u8> { self.v }
    pub take fn into_bytes(): List<u8> {
        var bytes = self.v
        match bytes.pop() {
            present(terminator) => {
                if terminator != 0u8 { package.core.panic.panic("invalid C string") }
                bytes
            },
            none => package.core.panic.panic("invalid C string")
        }
    }
    pub take fn into_string(): String throws IntoStringError {
        match self.as_c_str().to_str() {
            present(text) => package.alloc.string.from_text(text),
            none => throw IntoStringError(self)
        }
    }
}

extend CString implements Default {
    static fn default(): CString { new_c_string() }
}

extend CString implements Clone {
    fn clone(): CString { CString(clone_bytes(self.v.as_slice())) }
}

extend<region r, region s> CStr<region r> implements PartialEq<CStr<region s>> {
    fn eq(other: read CStr<region s>): bool {
        bytes_equal(self.to_bytes(), other.to_bytes())
    }
}

extend<region r> CStr<region r> implements Eq {}

extend<region r, region s> CStr<region r> implements PartialOrd<CStr<region s>> {
    fn partial_cmp(other: read CStr<region s>): Ordering? {
        present(self.to_bytes().cmp(other.to_bytes()))
    }
}

extend<region r> CStr<region r> implements Ord {
    fn cmp(other: read CStr<region r>): Ordering {
        self.to_bytes().cmp(other.to_bytes())
    }
}

extend<region r> CString implements PartialEq<CStr<region r>> {
    fn eq(other: read CStr<region r>): bool {
        bytes_equal(self.as_bytes(), other.to_bytes())
    }
}

extend<region r> CStr<region r> implements PartialEq<CString> {
    fn eq(other: read CString): bool {
        bytes_equal(self.to_bytes(), other.as_bytes())
    }
}

extend CString implements PartialEq {
    fn eq(other: read CString): bool { bytes_equal(self.as_bytes(), other.as_bytes()) }
}

extend CString implements Eq {}

extend CString implements PartialOrd {
    fn partial_cmp(other: read CString): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend CString implements Ord {
    fn cmp(other: read CString): Ordering { self.as_bytes().cmp(other.as_bytes()) }
}

extend<region r> CStr<region r> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.to_bytes().hash(mut state) }
}

extend CString implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.as_bytes().hash(mut state) }
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

extend List<u8> implements package.core.convert.From<CString> {
    static fn from(value: take CString): List<u8> { value.into_bytes() }
}

// Value types duplicate by copy; owners clone their buffers.
extend OsString implements Clone {
    fn clone(): OsString { OsString(self.v.clone()) }
}
