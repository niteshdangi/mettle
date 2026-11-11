// Operating-system strings: arbitrary bytes (never required to be Unicode)
// that round-trip losslessly. `OsStr` is the unsized view, `OsString` the
// owner. Interior NUL bytes are representable here and rejected only where a
// C string is required (`cstring`).
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.alloc.AllocError
import package.alloc.string.String
import package.alloc.string.FromUtf8Error
import package.core.borrow.{AsRef, Borrow, ToOwned}
import package.core.convert.Into
import package.core.clone.Clone
import package.core.default.Default
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.fmt
import package.core.iter.{ExtendItems, FromItems, Iterator, OwnedIterable, RangeBounds}
import package.core.hash.{Hash, Hasher}
import package.core.ops.Deref
import package.core.text.{FromStr, Text}
import package.core.slice
import super.io
import super.io.ErrorKind

pub type OsStr { bytes: [u8] }
static EMPTY_OS_BYTES: [u8; 0] = []

// Any byte sequence is a valid OS string.
pub fn os_str(read bytes: [u8]): read OsStr from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read OsStr>>(fat) }
    unsafe { read *view }
}

pub fn os_str_mut(mut bytes: [u8]): mut OsStr from bytes {
    let fat = core.ptr.from_mut(bytes)
    let view = unsafe { core.mem.transmute<ptr<mut OsStr>>(fat) }
    unsafe { mut *view }
}

pub fn os_str_from_text(read text: Text): read OsStr from text { os_str(text.as_bytes()) }
pub fn os_str_from_encoded_bytes_unchecked(read bytes: [u8]): read OsStr from bytes {
    os_str(bytes)
}

pub fn lossy(read bytes: [u8]): String {
    package.alloc.string.from_utf8_lossy(bytes)
}

extend OsStr {
    pub static fn new(read bytes: [u8]): read OsStr from bytes { os_str(bytes) }
    pub static fn from_encoded_bytes_unchecked(read bytes: [u8]): read OsStr from bytes {
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
    pub fn to_str(): (read Text from self)? {
        match package.core.text.from_utf8(read self.bytes) {
            success(text) => present(text),
            failure(_) => none
        }
    }
    pub fn to_string_lossy(): String { lossy(read self.bytes) }
    pub fn display(): String { self.to_string_lossy() }
    pub fn to_os_string(): OsString { os_string_from_bytes(read self.bytes) }
    pub fn into_os_string(): OsString { self.to_os_string() }
    pub fn same(read other: OsStr): bool { bytes_equal(read self.bytes, other.as_bytes()) }
    pub fn eq_ignore_ascii_case(read other: OsStr): bool {
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

pub fn bytes_equal(read a: [u8], read b: [u8]): bool {
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
pub fn os_string_from_encoded_bytes_unchecked(take bytes: List<u8>): OsString {
    OsString(bytes)
}

pub fn os_string_from_bytes(read bytes: [u8]): OsString {
    var v = vec.with_capacity<u8>(bytes.len())
    v.extend_from_slice(bytes)
    OsString(v)
}

pub fn os_string_from_text(read text: Text): OsString { os_string_from_bytes(text.as_bytes()) }

pub fn os_string_from_vec(take bytes: List<u8>): OsString { OsString(bytes) }

extend OsString {
    pub static fn new(): OsString { new_os_string() }
    pub static fn with_capacity(capacity: usize): OsString { os_string_with_capacity(capacity) }
    pub static fn from_encoded_bytes_unchecked(take bytes: List<u8>): OsString {
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
    pub fn eq_ignore_ascii_case(read other: OsString): bool {
        self.as_os_str().eq_ignore_ascii_case(other.as_os_str())
    }
    pub mut fn push_bytes(read bytes: [u8]): Unit { self.v.extend_from_slice(bytes) }
    pub mut fn push(read s: OsStr): Unit { self.v.extend_from_slice(s.as_bytes()) }
    pub mut fn clear(): Unit { self.v.clear() }
    pub mut fn reserve(extra: usize): Unit { self.v.reserve(extra) }
    pub mut fn reserve_exact(extra: usize): Unit { self.v.reserve_exact(extra) }
    pub mut fn try_reserve(extra: usize): Unit throws AllocError { try self.v.try_reserve(extra) }
    pub mut fn try_reserve_exact(extra: usize): Unit throws AllocError {
        try self.v.try_reserve_exact(extra)
    }
    pub mut fn shrink_to_fit(): Unit { self.v.shrink_to_fit() }
    pub mut fn shrink_to(minimum: usize): Unit {
        self.v.shrink_to(minimum)
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
    pub take fn leak(): mut OsStr from static { os_str_mut(self.v.leak()) }
    pub take fn into_string(): String throws FromUtf8Error {
        try package.alloc.string.from_utf8(self.v)
    }
    pub fn same(read other: OsString): bool { bytes_equal(self.v.as_slice(), other.as_bytes()) }
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
    pub fn as_c_str(): read CStr from self { self.value.as_c_str() }
    pub take fn into_cstring(): CString { self.value }
}

// A borrowed, validated NUL-terminated byte string. Construction is restricted
// to the validating constructors below; the terminator is part of `bytes`.
pub type CStr { bytes: [u8] }
static EMPTY_C_STR_BYTES: [u8; 1] = [0u8]

// Owned C strings always contain one final NUL and no earlier NUL.
pub type CString { v: List<u8> }

// Safety: bytes contain exactly one NUL, at the end. The slice-tail cast
// preserves the byte extent, alignment and provenance; the view borrows bytes.
unsafe fn c_str_view(read bytes: [u8]): read CStr from bytes {
    let pointer = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read CStr>>(pointer) }
    unsafe { read *view }
}

fn clone_bytes(read bytes: [u8]): List<u8> {
    var duplicate = vec.with_capacity<u8>(bytes.len())
    duplicate.extend_from_slice(bytes)
    duplicate
}

fn c_str_from_bytes_with_nul(
    read bytes: [u8]
): read CStr from bytes throws FromBytesWithNulError {
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
    unsafe { c_str_view(bytes) }
}

fn c_str_from_bytes_until_nul(
    read bytes: [u8]
): read CStr from bytes throws FromBytesUntilNulError {
    var i = 0usize
    while i < bytes.len() && bytes[i] != 0u8 { i += 1usize }
    if i == bytes.len() { throw FromBytesUntilNulError() }
    match slice.subslice(bytes, 0usize, i + 1usize) {
        present(terminated) => unsafe { c_str_view(terminated) },
        none => throw FromBytesUntilNulError()
    }
}

extend CStr {
    pub static fn from_bytes_with_nul(
        read bytes: [u8]
    ): read CStr from bytes throws FromBytesWithNulError {
        try c_str_from_bytes_with_nul(bytes)
    }

    pub static fn from_bytes_until_nul(
        read bytes: [u8]
    ): read CStr from bytes throws FromBytesUntilNulError {
        try c_str_from_bytes_until_nul(bytes)
    }

    // Safety: the bytes must end in one NUL and contain no earlier NUL.
    pub static unsafe fn from_bytes_with_nul_unchecked(
        read bytes: [u8]
    ): read CStr from bytes { unsafe { c_str_view(bytes) } }

    // Safety: `pointer` stays readable through NUL and the result does not outlive it.
    pub static unsafe fn from_ptr<region s>(
        pointer: ptr<read i8>
    ): read CStr from s {
        let bytes = unsafe {
            slice.from_raw_parts<u8>(pointer.cast<u8>(), super.sys.strlen(pointer.cast<u8>()) + 1usize)
        }
        unsafe { c_str_view(bytes) }
    }

    pub fn as_ptr(): ptr<read i8> { self.bytes.as_ptr().cast<i8>() }
    pub fn count_bytes(): usize { self.bytes.len() - 1usize }
    pub fn is_empty(): bool { self.bytes.len() == 1usize }
    pub fn to_bytes_with_nul(): read [u8] from self { read self.bytes }
    pub fn to_bytes(): read [u8] from self {
        match slice.subslice(read self.bytes, 0usize, self.bytes.len() - 1usize) {
            present(bytes) => bytes,
            none => package.core.panic.panic("invalid C string")
        }
    }
    pub fn to_str(): (read Text from self)? {
        match package.core.text.from_utf8(self.to_bytes()) {
            success(text) => present(text),
            failure(_) => none
        }
    }
    pub fn to_string_lossy(): String { lossy(self.to_bytes()) }
    pub fn to_owned(): CString { CString(clone_bytes(read self.bytes)) }
    pub fn into_c_string(): CString { self.to_owned() }
}

fn c_string_new(take bytes: List<u8>): CString throws NulError {
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
    take bytes: List<u8>
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
    pub static fn new<T: Into<List<u8>>>(take bytes: T): CString throws NulError {
        try c_string_new(bytes.into())
    }

    pub static fn from_vec_with_nul(
        take bytes: List<u8>
    ): CString throws FromVecWithNulError {
        try c_string_from_vec_with_nul(bytes)
    }

    // Safety: `bytes` must contain no NUL byte.
    pub static unsafe fn from_vec_unchecked(take bytes: List<u8>): CString {
        var owned = bytes
        owned.push(0u8)
        CString(owned)
    }

    // Safety: `bytes` must end in one NUL and contain no earlier NUL.
    pub static unsafe fn from_vec_with_nul_unchecked(take bytes: List<u8>): CString {
        CString(bytes)
    }

    pub fn as_c_str(): read CStr from self {
        unsafe { c_str_view(self.v.as_slice()) }
    }
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
        match package.core.text.from_utf8(self.as_bytes()) {
            success(text) => present(text),
            failure(_) => none
        }
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

extend CString implements Borrow<CStr> {
    fn borrow(): read CStr from self { self.as_c_str() }
}

extend CString implements AsRef<CStr> {
    fn as_ref(): read CStr from self { self.as_c_str() }
}

extend CString implements Deref {
    type Target = CStr
    fn deref(): read CStr from self { self.as_c_str() }
}

extend CStr implements ToOwned {
    type Owned = CString
    fn to_owned(): CString { CString(clone_bytes(read self.bytes)) }
}

extend<region r> read CStr from r implements Default {
    static fn default(): read CStr from r {
        unsafe { c_str_view(EMPTY_C_STR_BYTES) }
    }
}

extend CString implements package.core.ops.Index<package.core.iter.RangeFull> {
    type Output = CStr
    fn index(read index: package.core.iter.RangeFull): read CStr from self {
        self.as_c_str()
    }
}

extend CStr implements package.core.ops.Index<package.core.iter.RangeFrom<usize>> {
    type Output = CStr
    fn index(read index: package.core.iter.RangeFrom<usize>): read CStr from self {
        let start = match take index.start_bound() {
            package.core.iter.Bound.Included(value) => *value,
            _ => package.core.panic.panic("invalid C string range")
        }
        if start >= self.bytes.len() {
            package.core.panic.panic("C string index out of bounds")
        }
        match slice.subslice(read self.bytes, start, self.bytes.len()) {
            present(bytes) => unsafe { c_str_view(bytes) },
            none => package.core.panic.panic("C string index out of bounds")
        }
    }
}

extend CStr implements PartialEq {
    fn eq(read other: CStr): bool {
        bytes_equal(self.to_bytes(), other.to_bytes())
    }
}

extend CStr implements Eq {}

extend CStr implements PartialOrd {
    fn partial_cmp(read other: CStr): Ordering? {
        present(self.to_bytes().cmp(other.to_bytes()))
    }
}

extend CStr implements Ord {
    fn cmp(read other: CStr): Ordering {
        self.to_bytes().cmp(other.to_bytes())
    }
}

extend CString implements PartialEq<CStr> {
    fn eq(read other: CStr): bool {
        bytes_equal(self.as_bytes(), other.to_bytes())
    }
}

extend CStr implements PartialEq<CString> {
    fn eq(read other: CString): bool {
        bytes_equal(self.to_bytes(), other.as_bytes())
    }
}

extend CString implements PartialEq {
    fn eq(read other: CString): bool { bytes_equal(self.as_bytes(), other.as_bytes()) }
}

extend CString implements Eq {}

extend CString implements PartialOrd {
    fn partial_cmp(read other: CString): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend CString implements Ord {
    fn cmp(read other: CString): Ordering { self.as_bytes().cmp(other.as_bytes()) }
}

extend CStr implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.to_bytes().hash(mut state) }
}

extend CString implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.as_bytes().hash(mut state) }
}

extend CString implements FromStr {
    type Error = NulError
    static fn from_str(read input: Text): CString throws NulError {
        try CString.new(clone_bytes(input.as_bytes()))
    }
}

extend<region r> CString implements package.core.convert.From<read CStr from r> {
    static fn from(take value: read CStr from r): CString {
        CString(clone_bytes(read value.bytes))
    }
}

extend CString implements package.core.convert.From<List<package.core.num.NonZero<u8>>> {
    static fn from(take values: List<package.core.num.NonZero<u8>>): CString {
        var bytes = vec.new<u8>()
        var source = values.into_iter()
        while true {
            match take source.next() {
                present(value) => {
                    bytes.push(u8.(package.core.convert.From<package.core.num.NonZero<u8>>).from(value))
                },
                none => { break }
            }
        }
        bytes.push(0u8)
        CString(bytes)
    }
}

extend CStr implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("CStr")
        try debug.field(self.to_string_lossy().as_text())
        try debug.finish()
    }
}

extend CString implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("CString")
        try debug.field(self.to_string_lossy().as_text())
        try debug.finish()
    }
}

// A NUL-terminated copy of `bytes` for passing to C.
pub fn cstring(read bytes: [u8]): List<u8> throws io.Error {
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
    static fn from(take value: CString): List<u8> { value.into_bytes() }
}

// Value types duplicate by copy; owners clone their buffers.
extend OsString implements Clone {
    fn clone(): OsString { OsString(self.v.clone()) }
}

extend<region r> OsString implements Borrow<OsStr> {
    fn borrow(): read OsStr from self { self.as_os_str() }
}

extend<region r> OsString implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.as_os_str() }
}

extend OsStr implements ToOwned {
    type Owned = OsString
    fn to_owned(): OsString { os_string_from_bytes(self.as_bytes()) }
}

extend<region r, region s> read OsStr from r implements PartialEq<read OsStr from s> {
    fn eq(read other: read OsStr from s): bool {
        bytes_equal(self.as_bytes(), other.as_bytes())
    }
}

extend<region r, region s> read OsStr from r implements PartialEq<read Text from s> {
    fn eq(read other: read Text from s): bool {
        bytes_equal(self.as_bytes(), other.as_bytes())
    }
}

extend<region r> read OsStr from r implements Eq {}

extend<region r, region s> read OsStr from r implements PartialOrd<read OsStr from s> {
    fn partial_cmp(read other: read OsStr from s): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend<region r, region s> read OsStr from r implements PartialOrd<read Text from s> {
    fn partial_cmp(read other: read Text from s): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend<region r> read OsStr from r implements Ord {
    fn cmp(read other: read OsStr from r): Ordering {
        self.as_bytes().cmp(other.as_bytes())
    }
}

extend OsStr implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.as_bytes().hash(mut state) }
}

extend<region r> read OsStr from r implements Default {
    static fn default(): read OsStr from r { os_str(EMPTY_OS_BYTES) }
}

extend OsString implements PartialEq {
    fn eq(read other: OsString): bool { bytes_equal(self.as_bytes(), other.as_bytes()) }
}

extend<region r> OsString implements PartialEq<read Text from r> {
    fn eq(read other: read Text from r): bool {
        bytes_equal(self.as_bytes(), other.as_bytes())
    }
}

extend OsString implements Eq {}

extend OsString implements PartialOrd {
    fn partial_cmp(read other: OsString): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend<region r> OsString implements PartialOrd<read Text from r> {
    fn partial_cmp(read other: read Text from r): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend OsString implements Ord {
    fn cmp(read other: OsString): Ordering { self.as_bytes().cmp(other.as_bytes()) }
}

extend OsString implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.as_bytes().hash(mut state) }
}

extend<region r> OsString implements PartialEq<read OsStr from r> {
    fn eq(read other: read OsStr from r): bool {
        bytes_equal(self.as_bytes(), other.as_bytes())
    }
}

extend<region r> read OsStr from r implements PartialEq<OsString> {
    fn eq(read other: OsString): bool {
        bytes_equal(self.as_bytes(), other.as_bytes())
    }
}

extend<region r> OsString implements PartialOrd<read OsStr from r> {
    fn partial_cmp(read other: read OsStr from r): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend<region r> read OsStr from r implements PartialOrd<OsString> {
    fn partial_cmp(read other: OsString): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}

extend OsString implements Default {
    static fn default(): OsString { new_os_string() }
}

extend OsString implements fmt.Write {
    mut fn write_str(read text: Text): Unit throws fmt.Error {
        self.push(os_str_from_text(text))
    }
}

extend OsStr implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let text = self.to_string_lossy()
        try Text.(fmt.Debug).fmt(text.as_text(), mut f)
    }
}

extend OsString implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let text = self.to_string_lossy()
        try Text.(fmt.Debug).fmt(text.as_text(), mut f)
    }
}

extend OsString implements ExtendItems<OsString> {
    mut fn extend<I: OwnedIterable<Item = OsString>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(item) => self.v.extend(item.into_bytes()),
                none => { break }
            }
        }
    }
}

extend<region r> OsString implements ExtendItems<read OsStr from r> {
    mut fn extend<I: OwnedIterable<Item = read OsStr from r>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(item) => self.push(item),
                none => { break }
            }
        }
    }
}

extend OsString implements FromItems<OsString> {
    static fn from_iter<I: OwnedIterable<Item = OsString>>(take items: I): OsString {
        var output = new_os_string()
        output.extend(items)
        output
    }
}

extend<region r> OsString implements FromItems<read OsStr from r> {
    static fn from_iter<I: OwnedIterable<Item = read OsStr from r>>(take items: I): OsString {
        var output = new_os_string()
        output.extend(items)
        output
    }
}

extend OsString implements Deref {
    type Target = OsStr
    fn deref(): read OsStr from self { self.as_os_str() }
}

extend OsString implements package.core.ops.DerefMut {
    mut fn deref_mut(): mut OsStr from self { self.as_mut_os_str() }
}

extend OsString implements package.core.ops.Index<package.core.iter.RangeFull> {
    type Output = OsStr
    fn index(read index: package.core.iter.RangeFull): read OsStr from self {
        self.as_os_str()
    }
}

extend OsString implements package.core.ops.IndexMut<package.core.iter.RangeFull> {
    type Output = OsStr
    mut fn index_mut(read index: package.core.iter.RangeFull): mut OsStr from self {
        self.as_mut_os_str()
    }
}

extend OsString implements FromStr {
    type Error = Never
    static fn from_str(read input: Text): OsString throws Never {
        os_string_from_text(input)
    }
}

extend OsString implements package.core.convert.From<String> {
    static fn from(take value: String): OsString {
        OsString(value.into_bytes())
    }
}

extend<region r> OsString implements package.core.convert.From<read Text from r> {
    static fn from(take value: read Text from r): OsString {
        os_string_from_text(value)
    }
}

extend<region r> OsString implements package.core.convert.From<read String from r> {
    static fn from(take value: read String from r): OsString {
        os_string_from_text(value.as_text())
    }
}

extend<region r> OsString implements package.core.convert.From<read OsStr from r> {
    static fn from(take value: read OsStr from r): OsString {
        os_string_from_bytes(value.as_bytes())
    }
}

extend<region r> OsString implements package.core.convert.From<read OsString from r> {
    static fn from(take value: read OsString from r): OsString {
        os_string_from_bytes(value.as_bytes())
    }
}
