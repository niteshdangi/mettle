// Operating-system strings: arbitrary bytes (never required to be Unicode)
// that round-trip losslessly. `OsStr` is the unsized view, `OsString` the
// owner. Interior NUL bytes are representable here and rejected only where a
// C string is required (`cstring`).
import alloc.vec
import alloc.vec.List
import alloc.boxed.Heap
import alloc.arc.Shared
import alloc.rc.LocalShared
import alloc.borrow.BorrowedOrOwned
import alloc.alloc.AllocError
import alloc.string.String
import alloc.string.FromUtf8Error
import core.borrow.{AsRef, Borrow, OwnedType, ToOwned}
import core.clone.Clone
import core.default.Default
import core.convert.{From, TryFrom}
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.fmt
import core.iter.{ExtendItems, FromItems, Iterator, OwnedIterable}
import core.hash.{Hash, Hasher}
import core.ops.Deref
import core.text.{FromStr, Text}
import super.io
import super.io.ErrorKind
pub import core.ffi.{CStr, FromBytesWithNulError, FromBytesUntilNulError}
pub import alloc.ffi.{CString, NulError, FromVecWithNulError, IntoStringError}

pub type OsStr { bytes: [u8] }
pub type Display<region r> { value: read OsStr from r }
static EMPTY_OS_BYTES: [u8; 0] = []

extend<region r> Display<region r> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let text = self.value.to_string_lossy()
        try Text.(fmt.Display).fmt(text.as_ref(), mut f)
    }
}

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
    alloc.string.from_utf8_lossy(bytes)
}

fn lossy_view<region r>(read bytes: [u8] from r): BorrowedOrOwned<region r, Text> {
    match core.text.from_utf8(bytes) {
        success(text) => BorrowedOrOwned<region r, Text>.Borrowed(text),
        failure(_) => BorrowedOrOwned<region r, Text>.Owned(lossy(bytes))
    }
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
        match core.text.from_utf8(read self.bytes) {
            success(text) => present(text),
            failure(_) => none
        }
    }
    pub fn to_string_lossy<region r>(
        receiver read self: OsStr from r
    ): BorrowedOrOwned<region r, Text> { lossy_view<region r>(read self.bytes) }
    pub fn display<region r>(receiver read self: OsStr from r): Display<region r> {
        Display(read self)
    }
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

pub type OsString { pub parent v: List<u8> }

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
        os_string_from_encoded_bytes_unchecked(take bytes)
    }
    pub fn as_os_str(): read OsStr from self { os_str(self.v.as_slice()) }
    pub mut fn as_mut_os_str(): mut OsStr from self { os_str_mut(self.v.as_mut_slice()) }
    pub fn as_bytes(): read [u8] from self { self.v.as_slice() }
    pub fn as_encoded_bytes(): read [u8] from self { self.v.as_slice() }
    pub fn capacity(): usize { self.v.capacity() }
    pub fn len(): usize { self.v.len() }
    pub fn is_empty(): bool { self.v.is_empty() }
    pub fn is_ascii(): bool { self.as_os_str().is_ascii() }
    pub fn display<region r>(receiver read self: OsString from r): Display<region r> {
        self.as_os_str().display()
    }
    pub fn to_str(): (read Text from self)? { self.as_os_str().to_str() }
    pub fn to_string_lossy<region r>(
        receiver read self: OsString from r
    ): BorrowedOrOwned<region r, Text> { self.as_os_str().to_string_lossy() }
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
    pub take fn into_heap_os_str(): Heap<OsStr> {
        let raw = self.v.into_heap_slice().into_raw()
        // OsStr preserves the heap byte slice's layout and length metadata.
        let pointer = unsafe { core.mem.transmute<ptr<mut OsStr>>(raw.0) }
        unsafe { alloc.boxed.from_raw_in(pointer, raw.1) }
    }
    pub take fn leak(): mut OsStr from static { os_str_mut(self.v.leak()) }
    pub take fn into_string(): String throws FromUtf8Error {
        try alloc.string.from_utf8(self.v)
    }
    pub fn same(read other: OsString): bool { bytes_equal(self.v.as_slice(), other.as_bytes()) }
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

// A borrowed owner converts like the owner, so iterators over `read OsString` feed `AsRef<OsStr>` APIs.
extend<region r> read OsString from r implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.as_os_str() }
}

extend OsStr implements OwnedType {
    type Owned = OsString
}
extend OsStr implements ToOwned {
    fn to_owned(): OsString { os_string_from_bytes(self.as_bytes()) }
}

extend OsStr implements PartialEq {
    fn eq(read other: OsStr): bool { bytes_equal(self.as_bytes(), other.as_bytes()) }
}
extend OsStr implements Eq {}
extend OsStr implements PartialOrd {
    fn partial_cmp(read other: OsStr): Ordering? {
        present(self.as_bytes().cmp(other.as_bytes()))
    }
}
extend OsStr implements Ord {
    fn cmp(read other: OsStr): Ordering { self.as_bytes().cmp(other.as_bytes()) }
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
        try Text.(fmt.Debug).fmt(text.as_ref(), mut f)
    }
}

extend OsString implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let text = self.to_string_lossy()
        try Text.(fmt.Debug).fmt(text.as_ref(), mut f)
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
        OsString.(ExtendItems<OsString>).extend(mut output, take items)
        output
    }
}

extend<region r> OsString implements FromItems<read OsStr from r> {
    static fn from_iter<I: OwnedIterable<Item = read OsStr from r>>(take items: I): OsString {
        var output = new_os_string()
        OsString.(ExtendItems<read OsStr from r>).extend(mut output, take items)
        output
    }
}

extend<region r> OsString implements ExtendItems<BorrowedOrOwned<region r, OsStr>> {
    mut fn extend<I: OwnedIterable<Item = BorrowedOrOwned<region r, OsStr>>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(item) => self.push(item.as_ref()),
                none => { break }
            }
        }
    }
}
extend<region r> OsString implements FromItems<BorrowedOrOwned<region r, OsStr>> {
    static fn from_iter<I: OwnedIterable<Item = BorrowedOrOwned<region r, OsStr>>>(
        take items: I
    ): OsString {
        var result = new_os_string()
        OsString.(ExtendItems<BorrowedOrOwned<region r, OsStr>>).extend(mut result, take items)
        result
    }
}

extend OsString implements Deref {
    type Target = OsStr
    fn deref(): read OsStr from self { self.as_os_str() }
}

extend OsString implements core.ops.DerefMut {
    mut fn deref_mut(): mut OsStr from self { self.as_mut_os_str() }
}

extend OsString implements core.ops.Index<core.iter.RangeFull> {
    type Output = OsStr
    fn index(read index: core.iter.RangeFull): read OsStr from self {
        self.as_os_str()
    }
}

extend OsString implements core.ops.IndexMut<core.iter.RangeFull> {
    type Output = OsStr
    mut fn index_mut(read index: core.iter.RangeFull): mut OsStr from self {
        self.as_mut_os_str()
    }
}

extend OsString implements FromStr {
    type Error = Never
    static fn from_str(read input: Text): OsString throws Never {
        os_string_from_text(input)
    }
}

extend OsString implements core.convert.From<String> {
    static fn from(take value: String): OsString {
        OsString(value.into_bytes())
    }
}

extend<region r> read Text from r implements TryFrom<read OsStr from r> {
    type Error = core.text.Utf8Error
    static fn try_from(take value: read OsStr from r): (Outcome<read Text from r, core.text.Utf8Error>) {
        core.text.from_utf8(value.as_bytes())
    }
}

extend Text implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { os_str(self.as_bytes()) }
}

extend String implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { os_str(self.as_bytes()) }
}

extend<region r, T: AsRef<OsStr> + unsized> OsString implements core.convert.From<read T from r> {
    static fn from(take value: read T from r): OsString {
        os_string_from_bytes(T.(AsRef<OsStr>).as_ref(value).as_bytes())
    }
}

extend OsString implements core.convert.From<Heap<OsStr>> {
    static fn from(take value: Heap<OsStr>): OsString {
        let raw = value.into_raw()
        let pointer = unsafe { core.mem.transmute<ptr<mut [u8]>>(raw.0) }
        let bytes: Heap<[u8]> = unsafe { alloc.boxed.from_raw_in(pointer, raw.1) }
        OsString(List<u8>.(core.convert.From<Heap<[u8]>>).from(take bytes))
    }
}

extend Heap<OsStr> {
    pub take fn into_os_string(): OsString {
        OsString.(core.convert.From<Heap<OsStr>>).from(take self)
    }
}

extend Shared<OsStr> implements From<OsString> {
    static fn from(take value: OsString): Shared<OsStr> {
        Shared<OsStr>.(From<Heap<OsStr>>).from(value.into_heap_os_str())
    }
}
extend Heap<OsStr> implements From<OsString> {
    static fn from(take value: OsString): Heap<OsStr> {
        value.into_heap_os_str()
    }
}
extend<region r> Heap<OsStr> implements From<read OsStr from r> {
    static fn from(take value: read OsStr from r): Heap<OsStr> {
        value.to_os_string().into_heap_os_str()
    }
}
extend<region r> Heap<OsStr> implements From<mut OsStr from r> {
    static fn from(take value: mut OsStr from r): Heap<OsStr> {
        value.to_os_string().into_heap_os_str()
    }
}
extend<region r> Heap<OsStr> implements From<BorrowedOrOwned<region r, OsStr>> {
    static fn from(take value: BorrowedOrOwned<region r, OsStr>): Heap<OsStr> {
        value.into_owned().into_heap_os_str()
    }
}
extend LocalShared<OsStr> implements From<OsString> {
    static fn from(take value: OsString): LocalShared<OsStr> {
        LocalShared<OsStr>.(From<Heap<OsStr>>).from(value.into_heap_os_str())
    }
}
extend<region r> LocalShared<OsStr> implements From<read OsStr from r> {
    static fn from(take value: read OsStr from r): LocalShared<OsStr> {
        LocalShared<OsStr>.(From<OsString>).from(value.to_os_string())
    }
}
extend<region r> LocalShared<OsStr> implements From<mut OsStr from r> {
    static fn from(take value: mut OsStr from r): LocalShared<OsStr> {
        LocalShared<OsStr>.(From<OsString>).from(value.to_os_string())
    }
}
extend<region r> Shared<OsStr> implements From<read OsStr from r> {
    static fn from(take value: read OsStr from r): Shared<OsStr> {
        Shared<OsStr>.(From<OsString>).from(value.to_os_string())
    }
}
extend<region r> Shared<OsStr> implements From<mut OsStr from r> {
    static fn from(take value: mut OsStr from r): Shared<OsStr> {
        Shared<OsStr>.(From<OsString>).from(value.to_os_string())
    }
}

extend<region r> OsString implements core.convert.From<BorrowedOrOwned<region r, OsStr>> {
    static fn from(take value: BorrowedOrOwned<region r, OsStr>): OsString {
        value.into_owned()
    }
}

extend OsString implements core.convert.From<CString> {
    static fn from(take value: CString): OsString {
        OsString(value.into_bytes())
    }
}

extend<region r> OsStr implements PartialEq<BorrowedOrOwned<region r, OsStr>> {
    fn eq(read other: BorrowedOrOwned<region r, OsStr>): bool {
        bytes_equal(self.as_bytes(), other.as_ref().as_bytes())
    }
}
extend<region r> OsStr implements PartialOrd<BorrowedOrOwned<region r, OsStr>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, OsStr>): Ordering? {
        present(self.as_bytes().cmp(other.as_ref().as_bytes()))
    }
}
extend<region r> OsString implements PartialEq<BorrowedOrOwned<region r, OsStr>> {
    fn eq(read other: BorrowedOrOwned<region r, OsStr>): bool {
        bytes_equal(self.as_bytes(), other.as_ref().as_bytes())
    }
}
extend<region r> OsString implements PartialOrd<BorrowedOrOwned<region r, OsStr>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, OsStr>): Ordering? {
        present(self.as_bytes().cmp(other.as_ref().as_bytes()))
    }
}
extend<region r, region s> read OsStr from r implements PartialEq<BorrowedOrOwned<region s, OsStr>> {
    fn eq(read other: BorrowedOrOwned<region s, OsStr>): bool {
        bytes_equal(self.as_bytes(), other.as_ref().as_bytes())
    }
}
extend<region r, region s> read OsStr from r implements PartialOrd<BorrowedOrOwned<region s, OsStr>> {
    fn partial_cmp(read other: BorrowedOrOwned<region s, OsStr>): Ordering? {
        present(self.as_bytes().cmp(other.as_ref().as_bytes()))
    }
}
