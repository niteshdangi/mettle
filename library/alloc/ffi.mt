pub import core.ffi.{CStr, FromBytesWithNulError, FromBytesUntilNulError}
import core.borrow.{AsRef, Borrow, OwnedType, ToOwned}
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.Into
import core.default.Default
import core.fmt
import core.hash.{Hash, Hasher}
import core.iter.{Iterator, OwnedIterable}
import core.ops.Deref
import core.text.{FromStr, Text, Utf8Error}
import super.borrow.BorrowedOrOwned
import super.boxed.Heap
import super.string.String
import super.vec
import super.vec.List

pub type NulError { bytes: List<u8>; position: usize }
copy enum NulErrorKind { InteriorNul, NotTerminated }
pub type FromVecWithNulError { bytes: List<u8>; kind: NulErrorKind }
pub type IntoStringError { value: CString; error: Utf8Error }

extend NulError {
    pub fn nul_position(): usize { self.position }
    pub take fn into_vec(): List<u8> { self.bytes }
}
extend NulError implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("nul byte found in provided data at position: ")
        try usize.(fmt.Display).fmt(self.position, mut f)
    }
}
extend NulError implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("NulError")
        try debug.field(self.position)
        try debug.field(self.bytes.as_slice())
        try debug.finish()
    }
}
extend NulError implements core.error.Error {}

extend FromVecWithNulError {
    pub fn as_bytes(): read [u8] from self { self.bytes.as_slice() }
    pub take fn into_bytes(): List<u8> { self.bytes }
}
extend IntoStringError {
    pub fn as_c_str(): read CStr from self { self.value.as_c_str() }
    pub fn utf8_error(): Utf8Error { self.error }
    pub take fn into_cstring(): CString { self.value }
}

// The owned buffer always contains exactly one NUL, at its end.
pub type CString { v: List<u8> }

fn clone_bytes(read bytes: [u8]): List<u8> {
    var duplicate = vec.with_capacity<u8>(bytes.len())
    duplicate.extend_from_slice(bytes)
    duplicate
}

fn lossy_view<region r>(read bytes: [u8] from r): BorrowedOrOwned<region r, Text> {
    match core.text.from_utf8(bytes) {
        success(text) => BorrowedOrOwned<region r, Text>.Borrowed(text),
        failure(_) => BorrowedOrOwned<region r, Text>.Owned(super.string.from_utf8_lossy(bytes))
    }
}

fn new_c_string(): CString {
    var bytes = vec.new<u8>()
    bytes.push(0u8)
    CString(bytes)
}

extend CString {
    pub static fn new<T: Into<List<u8>>>(take bytes: T): CString throws NulError {
        var owned = bytes.into()
        var i = 0usize
        while i < owned.len() {
            if owned[i] == 0u8 { throw NulError(owned, i) }
            i += 1usize
        }
        owned.push(0u8)
        CString(owned)
    }

    pub static fn from_vec_with_nul(
        take bytes: List<u8>
    ): CString throws FromVecWithNulError {
        if bytes.is_empty() { throw FromVecWithNulError(bytes, NulErrorKind.NotTerminated) }
        let terminator = bytes.len() - 1usize
        var i = 0usize
        while i < terminator {
            if bytes[i] == 0u8 { throw FromVecWithNulError(bytes, NulErrorKind.InteriorNul) }
            i += 1usize
        }
        if bytes[terminator] != 0u8 {
            throw FromVecWithNulError(bytes, NulErrorKind.NotTerminated)
        }
        CString(bytes)
    }

    // Safety: bytes must contain no NUL byte.
    pub static unsafe fn from_vec_unchecked(take bytes: List<u8>): CString {
        var owned = bytes
        owned.push(0u8)
        CString(owned)
    }

    // Safety: bytes must end in one NUL and contain no earlier NUL.
    pub static unsafe fn from_vec_with_nul_unchecked(take bytes: List<u8>): CString {
        CString(bytes)
    }

    pub const fn as_c_str(): read CStr from self {
        unsafe { CStr.from_bytes_with_nul_unchecked(self.v.as_slice()) }
    }
    pub const fn as_ptr(): ptr<read i8> { self.as_c_str().as_ptr() }
    pub const fn count_bytes(): usize { self.v.as_slice().len() - 1usize }
    pub const fn is_empty(): bool { self.v.as_slice().len() == 1usize }
    pub const fn as_bytes_with_nul(): read [u8] from self { self.v.as_slice() }
    pub const fn as_bytes(): read [u8] from self { self.as_c_str().to_bytes() }
    pub const fn to_str(): Outcome<read Text from self, Utf8Error> { self.as_c_str().to_str() }
    pub fn to_string_lossy<region r>(
        receiver read self: CString from r
    ): BorrowedOrOwned<region r, Text> { lossy_view<region r>(self.as_bytes()) }
    pub take fn into_bytes_with_nul(): List<u8> { self.v }
    pub take fn into_bytes(): List<u8> {
        var bytes = self.v
        match bytes.pop() {
            present(terminator) => {
                if terminator != 0u8 { core.panic.panic("invalid C string") }
                bytes
            },
            none => core.panic.panic("invalid C string")
        }
    }
    pub take fn into_heap_c_str(): Heap<CStr> {
        let raw = self.v.into_heap_slice().into_raw()
        let pointer = unsafe { core.mem.transmute<ptr<mut CStr>>(raw.0) }
        unsafe { super.boxed.from_raw_in(pointer, raw.1) }
    }
    pub take fn into_raw(): ptr<mut i8> { self.into_heap_c_str().into_raw().0.cast<i8>() }

    // Safety: the exact outstanding into_raw pointer retains its original first NUL and allocation.
    pub static unsafe fn from_raw(pointer: ptr<mut i8>): CString {
        let length = unsafe { CStr.from_ptr(pointer.cast_const()) }.count_bytes() + 1usize
        let bytes = vec.slice_ptr_mut(pointer.cast<u8>(), length)
        let view = unsafe { core.mem.transmute<ptr<mut CStr>>(bytes) }
        let boxed: Heap<CStr> = unsafe { super.boxed.from_raw(view) }
        CString.(core.convert.From<Heap<CStr>>).from(take boxed)
    }
    pub take fn into_string(): String throws IntoStringError {
        let invalid = match core.text.from_utf8(self.as_bytes()) {
            success(_) => none,
            failure(error) => present(error)
        }
        match invalid {
            present(error) => throw IntoStringError(self, error),
            none => unsafe { String.from_utf8_unchecked(self.into_bytes()) }
        }
    }
}

extend CStr {
    pub fn to_string_lossy<region r>(
        receiver read self: CStr from r
    ): BorrowedOrOwned<region r, Text> { lossy_view<region r>(self.to_bytes()) }
    pub fn to_owned(): CString { CString(clone_bytes(self.to_bytes_with_nul())) }
    pub fn into_c_string(): CString { self.to_owned() }
}

extend CString implements core.convert.From<Heap<CStr>> {
    static fn from(take value: Heap<CStr>): CString {
        let raw = value.into_raw()
        let pointer = unsafe { core.mem.transmute<ptr<mut [u8]>>(raw.0) }
        let bytes: Heap<[u8]> = unsafe { super.boxed.from_raw_in(pointer, raw.1) }
        CString(List<u8>.(core.convert.From<Heap<[u8]>>).from(take bytes))
    }
}
extend Heap<CStr> {
    pub take fn into_c_string(): CString {
        CString.(core.convert.From<Heap<CStr>>).from(take self)
    }
}
extend<region r> CString implements core.convert.From<BorrowedOrOwned<region r, CStr>> {
    static fn from(take value: BorrowedOrOwned<region r, CStr>): CString { value.into_owned() }
}
extend String implements core.convert.TryFrom<CString> {
    type Error = IntoStringError
    static fn try_from(take value: CString): Outcome<String, IntoStringError> {
        capture value.into_string()
    }
}
extend<region r> CStr implements PartialEq<BorrowedOrOwned<region r, CStr>> {
    fn eq(read other: BorrowedOrOwned<region r, CStr>): bool {
        CStr.(PartialEq).eq(read self, other.as_ref())
    }
}
extend<region r> CString implements PartialEq<BorrowedOrOwned<region r, CStr>> {
    fn eq(read other: BorrowedOrOwned<region r, CStr>): bool {
        CStr.(PartialEq).eq(self.as_c_str(), other.as_ref())
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
    const fn deref(): read CStr from self { self.as_c_str() }
}
extend CStr implements OwnedType { type Owned = CString }
extend CStr implements ToOwned {
    fn to_owned(): CString { CString(clone_bytes(self.to_bytes_with_nul())) }
}
extend CString implements core.ops.Index<core.iter.RangeFull> {
    type Output = CStr
    fn index(read index: core.iter.RangeFull): read CStr from self { self.as_c_str() }
}
extend CString implements PartialEq<CStr> {
    fn eq(read other: CStr): bool { CStr.(PartialEq).eq(self.as_c_str(), other) }
}
extend<region r> CString implements PartialEq<read CStr from r> {
    fn eq(read other: read CStr from r): bool { CStr.(PartialEq).eq(self.as_c_str(), *other) }
}
extend CStr implements PartialEq<CString> {
    fn eq(read other: CString): bool { CStr.(PartialEq).eq(read self, other.as_c_str()) }
}
extend CString implements PartialEq {
    fn eq(read other: CString): bool { CStr.(PartialEq).eq(self.as_c_str(), other.as_c_str()) }
}
extend CString implements Eq {}
extend CString implements PartialOrd {
    fn partial_cmp(read other: CString): Ordering? {
        present(self.as_c_str().cmp(other.as_c_str()))
    }
}
extend CString implements Ord {
    fn cmp(read other: CString): Ordering { self.as_c_str().cmp(other.as_c_str()) }
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
extend<region r> CString implements core.convert.From<read CStr from r> {
    static fn from(take value: read CStr from r): CString {
        CString(clone_bytes(value.to_bytes_with_nul()))
    }
}
extend CString implements core.convert.From<List<core.num.NonZero<u8>>> {
    static fn from(take values: List<core.num.NonZero<u8>>): CString {
        var bytes = vec.new<u8>()
        var source = values.into_iter()
        while true {
            match take source.next() {
                present(value) => {
                    bytes.push(u8.(core.convert.From<core.num.NonZero<u8>>).from(value))
                },
                none => { break }
            }
        }
        bytes.push(0u8)
        CString(bytes)
    }
}
extend CString implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("CString")
        try debug.field(self.to_string_lossy().as_ref())
        try debug.finish()
    }
}
extend List<u8> implements core.convert.From<CString> {
    static fn from(take value: CString): List<u8> { value.into_bytes() }
}
