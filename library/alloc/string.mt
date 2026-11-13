import core.iter.{Iterator, BidirectionalIterator}
import super.alloc.{Allocator, Global, AllocError, panic_precondition}
import core.clone.Clone
import core.default.Default
import core.fmt
import core.ops.{Deref, IndexRange, IndexRangeMut, RangeEnd}
import core.hash.{Hash, Hasher}
import core.borrow.KeyView
import core.borrow.{AsRef, AsMut, Borrow, OwnedType, ToOwned}
import super.vec.{List, slice_ptr}
import core.cmp.{Ordering, PartialEq, Eq, PartialOrd, Ord}
import core.text.{
    Text,
    from_utf8_unchecked,
    from_utf8_unchecked_mut
}
extend<A: Allocator> String implements ExtendItems<alloc.boxed.Box<Text, A>> {
    mut fn extend<I: OwnedIterable<Item = alloc.boxed.Box<Text, A>>>(
        take items: I
    ): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(value) => self.push_str(value.get()),
                none => { break }
            }
        }
    }
}
extend<A: Allocator> String implements FromItems<alloc.boxed.Box<Text, A>> {
    static fn from_iter<I: OwnedIterable<Item = alloc.boxed.Box<Text, A>>>(
        take items: I
    ): String {
        var result = new()
        String.(ExtendItems<alloc.boxed.Box<Text, A>>).extend(mut result, take items)
        result
    }
}
import core.iter.{OwnedIterable, FromItems, ExtendItems}
import core.convert.{From, TryFrom}
import core.text.FromStr
import core.ops.{Add, AddAssign}
import super.borrow.BorrowedOrOwned

// Owned, growable UTF-8 text: a `List<u8>` whose bytes are always well formed.
pub type String<A: Allocator = Global> {
    v: List<u8, A>
}

// Safety: retained and unvisited bytes are separate valid UTF-8 extents; the guard rejoins them.
type StringRetainGuard<A: Allocator> {
    bytes: ptr<mut List<u8, A>>
    original_len: usize
    read_at: usize
    write_at: usize
    drop {
        unsafe {
            let pointer = (*self.bytes).as_mut_ptr()
            let remaining = self.original_len - self.read_at
            core.ptr.`copy`(pointer.add(self.read_at).cast_const(), pointer.add(self.write_at), remaining)
            (*self.bytes).set_len(self.write_at + remaining)
        }
    }
}

// Produces independently owned UTF-8 using Global and the default Display
// options. Allocation or formatting failure panics; rendering cost follows
// Display plus the bytes appended to the result.
pub interface ToString {
    fn to_string(): String;
}

// Invalid input handed back to the caller together with the failing offset.
pub type FromUtf8Error<A: Allocator = Global> {
    pub bytes: List<u8, A>
    pub valid_up_to: usize
}

pub type FromUtf16Error {
    pub index: usize
    pub surrogate: u16
}

pub type StringDrain<region r, A: Allocator> {
    bytes: super.vec.Drain<region r, u8, A>
}
extend<region r, A: Allocator> StringDrain<region r, A> {
    pub fn as_str(): read Text from self {
        unsafe { from_utf8_unchecked(self.bytes.as_slice()) }
    }
}
extend<region r, A: Allocator> StringDrain<region r, A> implements AsRef<Text> {
    fn as_ref(): read Text from self { self.as_str() }
}
extend<region r, A: Allocator> StringDrain<region r, A> implements AsRef<[u8]> {
    fn as_ref(): read [u8] from self { self.bytes.as_slice() }
}
extend<region r, A: Allocator> StringDrain<region r, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("Drain")
        try debug.field(self.as_str())
        try debug.finish()
    }
}
extend<region r, A: Allocator> StringDrain<region r, A> implements Iterator {
    type Item = char
    mut fn next(): char? {
        let next_char = {
            let text = unsafe { from_utf8_unchecked(self.bytes.as_slice()) }
            text.chars().next()
        }
        match next_char {
            present(c) => {
                var consumed = 0usize
                while consumed < c.len_utf8() {
                    match self.bytes.next() {
                        present(_) => {},
                        none => { panic_precondition() }
                    }
                    consumed += 1usize
                }
                present(c)
            },
            none => none
        }
    }
}
extend<region r, A: Allocator> StringDrain<region r, A> implements BidirectionalIterator {
    mut fn next_back(): char? {
        let previous_char = {
            let text = unsafe { from_utf8_unchecked(self.bytes.as_slice()) }
            var chars = text.chars()
            chars.next_back()
        }
        match previous_char {
            present(c) => {
                var consumed = 0usize
                while consumed < c.len_utf8() {
                    match self.bytes.next_back() {
                        present(_) => {},
                        none => { panic_precondition() }
                    }
                    consumed += 1usize
                }
                present(c)
            },
            none => none
        }
    }
}

// Callers must provide well-formed UTF-8 bytes.
const fn from_valid_bytes<A: Allocator>(take bytes: List<u8, A>): String<A> {
    let result: String<A>
    result.v = take bytes
    result
}

pub const fn new_in<A: Allocator>(take a: A): String<A> {
    from_valid_bytes(super.vec.new_in<u8, A>(take a))
}
pub const fn new(): String { new_in(Global()) }
pub fn try_with_capacity_in<A: Allocator>(n: usize, take a: A): String<A> throws AllocError {
    from_valid_bytes(try super.vec.try_with_capacity_in<u8, A>(n, take a))
}
pub fn with_capacity_in<A: Allocator>(n: usize, take a: A): String<A> {
    from_valid_bytes(super.vec.with_capacity_in<u8, A>(n, take a))
}
pub fn try_with_capacity(n: usize): String throws AllocError {
    try try_with_capacity_in(n, Global())
}
pub fn with_capacity(n: usize): String {
    from_valid_bytes(super.vec.with_capacity<u8>(n))
}
pub fn from_text(read t: Text): String {
    var s = new()
    s.push_str(t)
    s
}
pub fn from_text_in<A: Allocator>(read t: Text, take a: A): String<A> {
    var s = new_in(a)
    s.push_str(t)
    s
}

// Validates `bytes`; on failure the buffer comes back in the error.
pub fn from_utf8<A: Allocator>(take bytes: List<u8, A>): String<A> throws FromUtf8Error<A> {
    let invalid = match core.text.from_utf8(bytes.as_slice()) {
        success(_) => none,
        failure(error) => present(error.valid_up_to())
    }
    match invalid {
        present(offset) => { throw FromUtf8Error(bytes, offset) },
        none => {}
    }
    from_valid_bytes(take bytes)
}

extend String {
    pub init(read text: Text) {
        self.v = super.vec.new<u8>()
        self.push_str(text)
    }
    pub static fn from_utf16(read units: [u16]): String throws FromUtf16Error {
        try alloc.string.from_utf16(units)
    }
    pub static fn from_utf16_lossy(read units: [u16]): String {
        alloc.string.from_utf16_lossy(units)
    }
    pub static fn from_utf16be(read bytes: [u8]): String throws FromUtf16Error {
        try alloc.string.from_utf16be(bytes)
    }
    pub static fn from_utf16le(read bytes: [u8]): String throws FromUtf16Error {
        try alloc.string.from_utf16le(bytes)
    }
    pub static fn from_utf16be_lossy(read bytes: [u8]): String {
        alloc.string.from_utf16be_lossy(bytes)
    }
    pub static fn from_utf16le_lossy(read bytes: [u8]): String {
        alloc.string.from_utf16le_lossy(bytes)
    }
    // Safety: the pointer and capacity must satisfy List's Global allocation
    // invariants, and the initialized bytes must be well-formed UTF-8.
    pub unsafe static fn from_raw_parts(
        pointer: ptr<mut u8>,
        length: usize,
        capacity: usize
    ): String {
        from_valid_bytes(
            unsafe { List<u8>.from_raw_parts(pointer, length, capacity) }
        )
    }
    pub take fn into_raw_parts(): (ptr<mut u8>, usize, usize) {
        self.into_bytes().into_raw_parts()
    }
    pub static fn from_utf8<A: Allocator>(
        take bytes: List<u8, A>
    ): String<A> throws FromUtf8Error<A> {
        try alloc.string.from_utf8(take bytes)
    }
    pub static fn from_utf8_lossy(read bytes: [u8]): String {
        alloc.string.from_utf8_lossy(bytes)
    }
    pub static fn from_utf8_lossy_owned(take bytes: List<u8>): String {
        alloc.string.from_utf8_lossy_owned(take bytes)
    }
    // Safety: every byte must be well-formed UTF-8.
    pub unsafe static fn from_utf8_unchecked<A: Allocator>(
        take bytes: List<u8, A>
    ): String<A> {
        from_valid_bytes(take bytes)
    }
}

extend<A: Allocator> String<A> {
    pub init(read text: Text, take allocator: A) {
        self.v = super.vec.new_in<u8, A>(take allocator)
        self.push_str(text)
    }
}

fn encode_utf8(c: char, mut out: [u8; 4]): usize {
    let v = c as u32
    if v < 0x80u32 {
        out[0usize] = v as u8
        return 1usize
    }
    if v < 0x800u32 {
        out[0usize] = (0xc0u32 | (v >> 6u32)) as u8
        out[1usize] = (0x80u32 | (v & 0x3fu32)) as u8
        return 2usize
    }
    if v < 0x10000u32 {
        out[0usize] = (0xe0u32 | (v >> 12u32)) as u8
        out[1usize] = (0x80u32 | ((v >> 6u32) & 0x3fu32)) as u8
        out[2usize] = (0x80u32 | (v & 0x3fu32)) as u8
        return 3usize
    }
    out[0usize] = (0xf0u32 | (v >> 18u32)) as u8
    out[1usize] = (0x80u32 | ((v >> 12u32) & 0x3fu32)) as u8
    out[2usize] = (0x80u32 | ((v >> 6u32) & 0x3fu32)) as u8
    out[3usize] = (0x80u32 | (v & 0x3fu32)) as u8
    4usize
}

fn valid_utf8_width(read bytes: [u8], start: usize): usize {
    let first = bytes[start]
    if first < 0x80u8 { return 1usize }
    if first >= 0xc2u8 && first <= 0xdfu8 {
        if bytes.len() - start < 2usize { return 0usize }
        return if bytes[start + 1usize] >= 0x80u8 && bytes[start + 1usize] <= 0xbfu8 { 2usize } else { 0usize }
    }
    if first >= 0xe0u8 && first <= 0xefu8 {
        if bytes.len() - start < 3usize { return 0usize }
        let second = bytes[start + 1usize]
        let third = bytes[start + 2usize]
        let second_ok = if first == 0xe0u8 { second >= 0xa0u8 && second <= 0xbfu8 }
            else if first == 0xedu8 { second >= 0x80u8 && second <= 0x9fu8 }
            else { second >= 0x80u8 && second <= 0xbfu8 }
        if !second_ok || third < 0x80u8 || third > 0xbfu8 { return 0usize }
        return 3usize
    }
    if first >= 0xf0u8 && first <= 0xf4u8 {
        if bytes.len() - start < 4usize { return 0usize }
        let second = bytes[start + 1usize]
        let third = bytes[start + 2usize]
        let fourth = bytes[start + 3usize]
        let second_ok = if first == 0xf0u8 { second >= 0x90u8 && second <= 0xbfu8 }
            else if first == 0xf4u8 { second >= 0x80u8 && second <= 0x8fu8 }
            else { second >= 0x80u8 && second <= 0xbfu8 }
        if !second_ok || third < 0x80u8 || third > 0xbfu8 ||
            fourth < 0x80u8 || fourth > 0xbfu8 { return 0usize }
        return 4usize
    }
    0usize
}

fn invalid_utf8_width(read bytes: [u8], start: usize): usize {
    let first = bytes[start]
    let expected = if first >= 0xc2u8 && first <= 0xdfu8 { 2usize }
        else if first >= 0xe0u8 && first <= 0xefu8 { 3usize }
        else if first >= 0xf0u8 && first <= 0xf4u8 { 4usize }
        else { return 1usize }
    var consumed = 1usize
    while consumed < expected && start + consumed < bytes.len() {
        let next = bytes[start + consumed]
        if next < 0x80u8 || next > 0xbfu8 { break }
        if consumed == 1usize &&
            (first == 0xe0u8 && next < 0xa0u8 ||
             first == 0xedu8 && next > 0x9fu8 ||
             first == 0xf0u8 && next < 0x90u8 ||
             first == 0xf4u8 && next > 0x8fu8) { break }
        consumed += 1usize
    }
    consumed
}

pub fn from_utf8_lossy(read bytes: [u8]): String {
    var result = new()
    var index = 0usize
    while index < bytes.len() {
        let width = valid_utf8_width(bytes, index)
        if width != 0usize {
            let part = match core.slice.subslice(bytes, index, index + width) {
                present(value) => value,
                none => { panic_precondition() }
            }
            let text = match core.text.from_utf8(part) {
                success(value) => value,
                failure(_) => { panic_precondition() }
            }
            result.push_str(text)
            index += width
        } else {
            result.push(match core.char.from_u32(0xfffdu32) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += invalid_utf8_width(bytes, index)
        }
    }
    result
}

// Lossy conversion that takes the byte buffer; same replacement rules as from_utf8_lossy.
pub fn from_utf8_lossy_owned(take bytes: List<u8>): String {
    from_utf8_lossy(bytes.as_slice())
}

pub fn from_utf16(read units: [u16]): String throws FromUtf16Error {
    var result = new()
    var index = 0usize
    while index < units.len() {
        let first = units[index] as u32
        var scalar = first
        if first >= 0xd800u32 && first <= 0xdbffu32 {
            if index + 1usize >= units.len() {
                throw FromUtf16Error(index, units[index])
            }
            let second = units[index + 1usize] as u32
            if second < 0xdc00u32 || second > 0xdfffu32 {
                throw FromUtf16Error(index, units[index])
            }
            scalar = 0x10000u32 + ((first - 0xd800u32) << 10u32) +
                (second - 0xdc00u32)
            index += 1usize
        } else if first >= 0xdc00u32 && first <= 0xdfffu32 {
            throw FromUtf16Error(index, units[index])
        }
        result.push(match core.char.from_u32(scalar) {
            present(value) => value,
            none => { throw FromUtf16Error(index, units[index]) }
        })
        index += 1usize
    }
    result
}

pub fn from_utf16_lossy(read units: [u16]): String {
    var result = new()
    var index = 0usize
    while index < units.len() {
        let first = units[index] as u32
        if first >= 0xd800u32 && first <= 0xdbffu32 &&
            index + 1usize < units.len() &&
            (units[index + 1usize] as u32) >= 0xdc00u32 &&
            (units[index + 1usize] as u32) <= 0xdfffu32 {
            let second = units[index + 1usize] as u32
            let scalar = 0x10000u32 + ((first - 0xd800u32) << 10u32) +
                (second - 0xdc00u32)
            result.push(match core.char.from_u32(scalar) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += 2usize
        } else if first >= 0xd800u32 && first <= 0xdfffu32 {
            result.push(match core.char.from_u32(0xfffdu32) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += 1usize
        } else {
            result.push(match core.char.from_u32(first) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += 1usize
        }
    }
    result
}

fn utf16_endian_units(read bytes: [u8], big_endian: bool): List<u16> {
    var converted = super.vec.with_capacity<u16>(bytes.len() / 2usize)
    var index = 0usize
    while bytes.len() - index >= 2usize {
        let first = bytes[index] as u16
        let second = bytes[index + 1usize] as u16
        converted.push(if big_endian {
            (first << 8u16) | second
        } else {
            first | (second << 8u16)
        })
        index += 2usize
    }
    converted
}

fn from_utf16_endian(read bytes: [u8], big_endian: bool): String throws FromUtf16Error {
    let converted = utf16_endian_units(bytes, big_endian)
    let result = try from_utf16(converted.as_slice())
    if bytes.len() % 2usize != 0usize {
        // An odd tail identifies its incomplete unit and the one available byte.
        throw FromUtf16Error(bytes.len() / 2usize, bytes[bytes.len() - 1usize] as u16)
    }
    result
}

fn from_utf16_endian_lossy(read bytes: [u8], big_endian: bool): String {
    let converted = utf16_endian_units(bytes, big_endian)
    var result = from_utf16_lossy(converted.as_slice())
    if bytes.len() % 2usize != 0usize { result.push('\u{fffd}') }
    result
}

pub fn from_utf16be(read bytes: [u8]): String throws FromUtf16Error {
    try from_utf16_endian(bytes, true)
}

pub fn from_utf16le(read bytes: [u8]): String throws FromUtf16Error {
    try from_utf16_endian(bytes, false)
}

pub fn from_utf16be_lossy(read bytes: [u8]): String {
    from_utf16_endian_lossy(bytes, true)
}

pub fn from_utf16le_lossy(read bytes: [u8]): String {
    from_utf16_endian_lossy(bytes, false)
}

fn first_char(read t: Text): char {
    var it = t.chars()
    match it.next() { present(c) => c, none => panic_precondition() }
}

extend<A: Allocator> String<A> {
    pub fn len(): usize { self.v.len() }
    pub fn capacity(): usize { self.v.capacity() }
    pub fn is_empty(): bool { self.v.is_empty() }
    pub fn as_bytes(): read [u8] from self { self.v.as_slice() }
    // Safety: the bytes must be restored to well-formed UTF-8 before the
    // string is next observed as text or dropped.
    pub mut unsafe fn as_bytes_mut(): mut [u8] from self {
        self.v.as_mut_slice()
    }
    pub fn as_ptr(): ptr<read u8> { self.v.as_ptr() }
    pub mut fn as_mut_ptr(): ptr<mut u8> { self.v.as_mut_ptr() }
    // Borrowed text view; while it lives the string cannot change.
    pub const fn as_text(): read Text from self { unsafe { from_utf8_unchecked(self.v.as_slice()) } }
    pub mut const fn as_mut_str(): mut Text from self {
        match take core.text.from_utf8_mut(self.v.as_mut_slice()) {
            success(text) => text,
            failure(_) => { panic_precondition() }
        }
    }
    pub mut fn get_mut(start: usize, end: usize): (mut Text from self)? {
        self.as_mut_str().get_mut(start, end)
    }
    // Safety: both endpoints are in bounds and UTF-8 scalar boundaries.
    pub unsafe fn get_unchecked(
        start: usize,
        end: usize
    ): read Text from self {
        unsafe { self.as_text().get_unchecked(start, end) }
    }
    // Safety: both endpoints are in bounds and UTF-8 scalar boundaries.
    pub mut unsafe fn get_unchecked_mut(
        start: usize,
        end: usize
    ): mut Text from self {
        unsafe { self.as_mut_str().get_unchecked_mut(start, end) }
    }
    pub mut const fn split_at_mut(
        mid: usize
    ): (mut Text from self, mut Text from self) {
        self.as_mut_str().split_at_mut(mid)
    }
    pub mut const fn split_at_mut_checked(
        mid: usize
    ): (mut Text from self, mut Text from self)? {
        self.as_mut_str().split_at_mut_checked(mid)
    }
    pub fn substr_range(read substring: Text): core.iter.Range<usize>? {
        self.as_text().substr_range(substring)
    }
    pub take fn into_boxed_str(): alloc.boxed.Box<Text, A> {
        alloc.boxed.from_string(take self)
    }
    pub take fn leak(): mut Text from static {
        let bytes = self.into_bytes().leak()
        unsafe { from_utf8_unchecked_mut(bytes) }
    }
    pub take fn into_raw_parts_with_alloc(): (
        ptr<mut u8>,
        usize,
        usize,
        A
    ) {
        self.into_bytes().into_raw_parts_with_alloc()
    }
    pub take fn into_bytes(): List<u8, A> {
        unsafe {
            let v = core.ptr.`read`(core.ptr.from_ref(self.v))
            core.mem.forget(take self)
            v
        }
    }
    // Safety: the bytes must be well-formed UTF-8 again before the string is
    // next observed as text (including on drop-free early exits such as errors).
    pub mut unsafe const fn as_mut_vec(): mut List<u8, A> from self { mut self.v }
    pub mut fn try_reserve(extra: usize): Unit throws AllocError { try self.v.try_reserve(extra) }
    pub mut fn reserve(extra: usize): Unit { self.v.reserve(extra) }
    pub mut fn try_reserve_exact(extra: usize): Unit throws AllocError {
        try self.v.try_reserve_exact(extra)
    }
    pub mut fn reserve_exact(extra: usize): Unit { self.v.reserve_exact(extra) }
    pub mut fn shrink_to_fit(): Unit { self.v.shrink_to_fit() }

    pub mut fn make_ascii_lowercase(): Unit {
        var index = 0usize
        while index < self.v.len() {
            let byte = self.v.as_slice()[index]
            if byte >= 0x41u8 && byte <= 0x5au8 {
                self.v.as_mut_slice()[index] = byte + 0x20u8
            }
            index += 1usize
        }
    }

    pub mut fn make_ascii_uppercase(): Unit {
        var index = 0usize
        while index < self.v.len() {
            let byte = self.v.as_slice()[index]
            if byte >= 0x61u8 && byte <= 0x7au8 {
                self.v.as_mut_slice()[index] = byte - 0x20u8
            }
            index += 1usize
        }
    }

    pub mut fn try_push_str(read t: Text): Unit throws AllocError {
        let bytes = t.as_bytes()
        try self.v.try_reserve(bytes.len())
        var i = 0usize
        while i < bytes.len() {
            let b = bytes[i]
            self.v.push(b)
            i += 1usize
        }
    }
    pub mut fn push_str(read t: Text): Unit {
        let bytes = t.as_bytes()
        self.v.reserve(bytes.len())
        var i = 0usize
        while i < bytes.len() {
            let b = bytes[i]
            self.v.push(b)
            i += 1usize
        }
    }
    pub mut fn push(c: char): Unit {
        var buf = [0u8, 0u8, 0u8, 0u8]
        let n = encode_utf8(c, mut buf)
        self.v.reserve(n)
        var i = 0usize
        while i < n {
            let b = buf[i]
            self.v.push(b)
            i += 1usize
        }
    }
    pub mut fn insert(index: usize, c: char): Unit {
        if !self.as_text().is_char_boundary(index) { panic_precondition() }
        var buf = [0u8, 0u8, 0u8, 0u8]
        let n = encode_utf8(c, mut buf)
        var i = 0usize
        while i < n {
            let b = buf[i]
            self.v.insert(index + i, b)
            i += 1usize
        }
    }
    pub mut fn insert_str(index: usize, read t: Text): Unit {
        if !self.as_text().is_char_boundary(index) { panic_precondition() }
        let bytes = t.as_bytes()
        var i = 0usize
        while i < bytes.len() {
            let b = bytes[i]
            self.v.insert(index + i, b)
            i += 1usize
        }
    }
    // Removes and returns the last scalar.
    pub mut fn pop(): char? {
        if self.v.is_empty() { return none }
        var start = self.v.len() - 1usize
        while !self.as_text().is_char_boundary(start) { start -= 1usize }
        let c = match self.as_text().get(start, self.v.len()) {
            present(t) => first_char(t),
            none => panic_precondition()
        }
        self.v.truncate(start)
        present(c)
    }
    // Removes the scalar starting at `index`; panics off a boundary or past the end.
    pub mut fn remove(index: usize): char {
        if index >= self.v.len() || !self.as_text().is_char_boundary(index) { panic_precondition() }
        var end = index + 1usize
        while !self.as_text().is_char_boundary(end) { end += 1usize }
        let c = match self.as_text().get(index, end) {
            present(t) => first_char(t),
            none => panic_precondition()
        }
        var i = index
        while i < end {
            self.v.remove(index)
            i += 1usize
        }
        c
    }
    // Shortens to `n` bytes; panics when `n` splits a scalar.
    pub mut fn truncate(n: usize): Unit {
        if n >= self.v.len() { return () }
        if !self.as_text().is_char_boundary(n) { panic_precondition() }
        self.v.truncate(n)
    }
    pub mut fn split_off(at: usize): String<A> where A: Clone {
        if !self.as_text().is_char_boundary(at) { panic_precondition() }
        from_valid_bytes(self.v.split_off(at))
    }
    pub mut fn shrink_to(minimum: usize): Unit { self.v.shrink_to(minimum) }
    pub mut fn drain(start: usize, end: usize): StringDrain<region self, A> {
        let valid = {
            let text = self.as_text()
            start <= end && end <= text.len() &&
                text.is_char_boundary(start) && text.is_char_boundary(end)
        }
        if !valid {
            panic_precondition()
        }
        StringDrain(self.v.drain(start..end))
    }
    pub mut fn replace_range(start: usize, end: usize, read replacement: Text): Unit {
        let valid = {
            let text = self.as_text()
            start <= end && end <= text.len() &&
                text.is_char_boundary(start) && text.is_char_boundary(end)
        }
        if !valid {
            panic_precondition()
        }
        self.v.reserve(replacement.len())
        var removed = start
        while removed < end {
            let _byte = self.v.remove(start)
            removed += 1usize
        }
        let bytes = replacement.as_bytes()
        var index = 0usize
        while index < bytes.len() {
            let byte = bytes[index]
            self.v.insert(start + index, byte)
            index += 1usize
        }
    }
    pub mut fn extend_from_within(start: usize, end: usize): Unit {
        let valid = {
            let text = self.as_text()
            start <= end && end <= text.len() &&
                text.is_char_boundary(start) && text.is_char_boundary(end)
        }
        if !valid {
            panic_precondition()
        }
        let count = end - start
        self.v.reserve(count)
        var index = 0usize
        while index < count {
            let byte = self.v.as_slice()[start + index]
            self.v.push(byte)
            index += 1usize
        }
    }
    pub mut fn clear(): Unit { self.v.clear() }

    // Keeps the scalars for which `keep` returns true, compacting in place.
    pub mut fn retain<F: mut fn(char): bool>(mut keep: F): Unit {
        let original_len = self.v.len()
        let pointer = self.v.as_mut_ptr()
        unsafe { self.v.set_len(0usize) }
        var guard = StringRetainGuard(core.ptr.from_mut(self.v), original_len, 0usize, 0usize)
        while guard.read_at < original_len {
            let c = {
                let rest = unsafe {
                    from_utf8_unchecked(read *slice_ptr(pointer.add(guard.read_at), original_len - guard.read_at))
                }
                first_char(rest)
            }
            let width = c.len_utf8()
            if keep(c) {
                unsafe {
                    core.ptr.`copy`(pointer.add(guard.read_at).cast_const(), pointer.add(guard.write_at), width)
                }
                guard.write_at += width
            }
            guard.read_at += width
        }
    }
}

extend<A: Allocator + Clone> String<A> implements Clone {
    fn clone(): String<A> { from_valid_bytes(self.v.clone()) }
}
extend<A: Allocator + Default> String<A> implements Default {
    static fn default(): String<A> { new_in<A>(A.(Default).default()) }
}

extend<A: Allocator> String<A> implements PartialEq {
    fn eq(read other: String<A>): bool { self.as_text() == other.as_text() }
}
extend<A: Allocator> String<A> implements Eq {}

extend<A: Allocator> String<A> implements PartialOrd {
    fn partial_cmp(read other: String<A>): Ordering? { self.as_text().partial_cmp(other.as_text()) }
}
extend<A: Allocator> String<A> implements Ord {
    fn cmp(read other: String<A>): Ordering { self.as_text().cmp(other.as_text()) }
}

// A String key can be searched by its Text; String hashes as Text does.
extend<A: Allocator> String<A> implements KeyView<Text> {
    fn key_view(): read Text from self { self.as_text() }
}
extend<A: Allocator> String<A> implements AsRef<Text> {
    fn as_ref(): read Text from self { self.as_text() }
}
extend<A: Allocator> String<A> implements Borrow<Text> {
    fn borrow(): read Text from self { self.as_text() }
}
extend Text implements OwnedType {
    type Owned = String
}
extend Text implements ToOwned {
    fn to_owned(): String { from_text(self) }
}
extend<A: Allocator> String<A> implements AsMut<Text> {
    mut fn as_mut(): mut Text from self { self.as_mut_str() }
}
extend<A: Allocator> String<A> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.as_text().hash(mut state) }
}

// Appends formatted output to the string; allocation failure aborts like push.
extend<A: Allocator> String<A> implements fmt.Write {
    mut fn write_str(read s: Text): Unit throws fmt.Error {
        self.push_str(s)
    }
}
extend<A: Allocator> String<A> {
    pub mut fn write_fmt(message: format fmt.Message): Unit throws fmt.Error {
        try message.write_to(mut self)
    }
}

extend<T: fmt.Display + unsized> T implements ToString {
    fn to_string(): String {
        var output = new()
        {
            var formatter = fmt.formatter(mut output, fmt.spec())
            match capture T.(fmt.Display).fmt(self, mut formatter) {
                success(_) => {},
                failure(_) => { panic_precondition() }
            }
        }
        output
    }
}

// `String` views as `Text`: every `Text` method applies, and `s[a..b]` slices
// with the same boundary checks.
extend<A: Allocator> String<A> implements Deref {
    type Target = Text
    const fn deref(): read Text from self { self.as_text() }
}
extend<A: Allocator> String<A> implements core.ops.DerefMut {
    mut const fn deref_mut(): mut Text from self { self.as_mut_str() }
}
extend<A: Allocator> String<A> implements IndexRange {
    type Output = Text
    fn index_range(start: usize, end: RangeEnd): read Text from self { self.as_text().index_range(start, end) }
}
extend<A: Allocator> String<A> implements IndexRangeMut {
    type Output = Text
    mut fn index_range_mut(start: usize, end: RangeEnd): mut Text from self {
        self.as_mut_str().index_range_mut(start, end)
    }
}
extend<A: Allocator> String<A> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.pad(self.as_text()) }
}
extend<A: Allocator> String<A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try Text.(fmt.Debug).fmt(self.as_text(), mut f) }
}

extend<A: Allocator> String<A> implements TryFrom<List<u8, A>> {
    type Error = FromUtf8Error<A>
    static fn try_from(take bytes: List<u8, A>): (Outcome<String<A>, FromUtf8Error<A>>) {
        match take capture from_utf8(bytes) {
            success(value) => success(value),
            failure(error) => failure(error)
        }
    }
}

extend<region r, A: Allocator> String<A> implements ExtendItems<read Text from r> {
    mut fn extend<I: OwnedIterable<Item = read Text from r>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(text) => self.push_str(text),
                none => { break }
            }
        }
    }
}

extend<region r> String implements FromItems<read Text from r> {
    static fn from_iter<I: OwnedIterable<Item = read Text from r>>(take items: I): String {
        var result = new()
        String.(ExtendItems<read Text from r>).extend(mut result, take items)
        result
    }
}
extend<A: Allocator> String<A> implements ExtendItems<char> {
    mut fn extend<I: OwnedIterable<Item = char>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(value) => self.push(value),
                none => { break }
            }
        }
    }
}
extend String implements FromItems<char> {
    static fn from_iter<I: OwnedIterable<Item = char>>(take items: I): String {
        var result = new()
        String.(ExtendItems<char>).extend(mut result, take items)
        result
    }
}
extend<region r, A: Allocator> String<A> implements ExtendItems<read char from r> {
    mut fn extend<I: OwnedIterable<Item = read char from r>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(value) => self.push(*value),
                none => { break }
            }
        }
    }
}
extend<region r> String implements FromItems<read char from r> {
    static fn from_iter<I: OwnedIterable<Item = read char from r>>(
        take items: I
    ): String {
        var result = new()
        String.(ExtendItems<read char from r>).extend(mut result, take items)
        result
    }
}
extend<A: Allocator> String<A> implements ExtendItems<String> {
    mut fn extend<I: OwnedIterable<Item = String>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(value) => self.push_str(value.as_text()),
                none => { break }
            }
        }
    }
}
extend String implements FromItems<String> {
    static fn from_iter<I: OwnedIterable<Item = String>>(take items: I): String {
        var result = new()
        String.(ExtendItems<String>).extend(mut result, take items)
        result
    }
}

extend String implements FromStr {
    type Error = Never
    static fn from_str(read input: Text): String throws Never { from_text(input) }
}
extend<region r> String implements From<read Text from r> {
    static fn from(take input: read Text from r): String { from_text(input) }
}
extend<region r> String implements From<mut Text from r> {
    static fn from(take input: mut Text from r): String { from_text(input) }
}
extend<region r> String implements From<BorrowedOrOwned<region r, Text>> {
    static fn from(take input: BorrowedOrOwned<region r, Text>): String {
        input.into_owned()
    }
}
extend<region r, A: Allocator> String<A> implements PartialEq<BorrowedOrOwned<region r, Text>> {
    fn eq(read other: BorrowedOrOwned<region r, Text>): bool {
        self.as_text() == other.as_ref()
    }
}
extend<region r, A: Allocator> String<A> implements ExtendItems<BorrowedOrOwned<region r, Text>> {
    mut fn extend<I: OwnedIterable<Item = BorrowedOrOwned<region r, Text>>>(
        take items: I
    ): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(value) => self.push_str(value.as_ref()),
                none => { break }
            }
        }
    }
}
extend<region r> String implements FromItems<BorrowedOrOwned<region r, Text>> {
    static fn from_iter<I: OwnedIterable<Item = BorrowedOrOwned<region r, Text>>>(
        take items: I
    ): String {
        var result = new()
        String.(ExtendItems<BorrowedOrOwned<region r, Text>>).extend(mut result, take items)
        result
    }
}
extend String implements From<char> {
    static fn from(take value: char): String {
        var result = new()
        result.push(value)
        result
    }
}
extend<A: Allocator> String<A> implements From<alloc.boxed.Box<Text, A>> {
    static fn from(
        take value: alloc.boxed.Box<Text, A>
    ): String<A> {
        let raw = value.into_raw()
        // Text and byte slices share length metadata and retain the allocator.
        let bytes_pointer = unsafe {
            core.mem.transmute<ptr<mut [u8]>>(raw.0)
        }
        let byte_box: alloc.boxed.Box<[u8], A> = unsafe {
            alloc.boxed.from_raw_in(bytes_pointer, raw.1)
        }
        let bytes = List<u8, A>.(
            From<alloc.boxed.Box<[u8], A>>
        ).from(take byte_box)
        from_valid_bytes(take bytes)
    }
}
extend<region r> String implements From<read String from r> {
    static fn from(take value: read String from r): String {
        from_text(value.as_text())
    }
}
extend<region r, A: Allocator> String<A> implements AddAssign<read Text from r> {
    mut fn add_assign(read rhs: read Text from r): Unit { self.push_str(rhs) }
}
extend<region r> String implements Add<read Text from r> {
    type Output = String
    fn add(read rhs: read Text from r): String {
        concat(self.as_text(), rhs)
    }
}
extend<A: Allocator> String<A> implements AsRef<[u8]> {
    fn as_ref(): read [u8] from self { self.as_bytes() }
}
extend<A: Allocator> String<A> implements PartialEq<Text> {
    fn eq(read other: Text): bool { self.as_text() == other }
}
extend<region r, A: Allocator> String<A> implements PartialEq<read Text from r> {
    fn eq(read other: read Text from r): bool { self.as_text() == *other }
}
extend<A: Allocator> String<A> implements PartialOrd<Text> {
    fn partial_cmp(read other: Text): Ordering? {
        self.as_text().partial_cmp(other)
    }
}

// Concatenation: a new string holding `a` followed by `b`.
pub fn concat(read a: Text, read b: Text): String {
    var s = with_capacity(a.len() + b.len())
    s.push_str(a)
    s.push_str(b)
    s
}

fn replace_text(read text: Text, read pattern: Text, read replacement: Text, limit: usize): String {
    var result = new()
    var remaining = limit
    if pattern.is_empty() {
        if remaining > 0usize {
            result.push_str(replacement)
            remaining -= 1usize
        }
        var chars = text.chars()
        while true {
            match chars.next() {
                present(c) => {
                    result.push(c)
                    if remaining > 0usize {
                        result.push_str(replacement)
                        remaining -= 1usize
                    }
                },
                none => { break }
            }
        }
        return result
    }

    var rest = read text
    while remaining > 0usize {
        match rest.find(read pattern) {
            present(at) => {
                match rest.get(0usize, at) {
                    present(prefix) => { result.push_str(prefix) },
                    none => { panic_precondition() }
                }
                result.push_str(replacement)
                let start = at + pattern.len()
                rest = match rest.get(start, rest.len()) {
                    present(suffix) => suffix,
                    none => { panic_precondition() }
                }
                remaining -= 1usize
            },
            none => { break }
        }
    }
    result.push_str(rest)
    result
}

extend Text {
    pub fn repeat(count: usize): String {
        let total = match self.len().checked_mul(count) {
            present(length) => length,
            none => panic_precondition()
        }
        if total > 0x7fffffffffffffffusize { panic_precondition() }
        if total == 0usize { return new() }
        var result = with_capacity(total)
        var remaining = count
        while remaining != 0usize {
            result.push_str(read self)
            remaining -= 1usize
        }
        result
    }

    pub fn to_ascii_lowercase(): String {
        var result = self.repeat(1usize)
        result.make_ascii_lowercase()
        result
    }

    pub fn to_ascii_uppercase(): String {
        var result = self.repeat(1usize)
        result.make_ascii_uppercase()
        result
    }

    pub fn replace(read pattern: Text, read replacement: Text): String {
        replace_text(read self, pattern, replacement, 0xffffffffffffffffusize)
    }

    pub fn replacen(read pattern: Text, read replacement: Text, count: usize): String {
        replace_text(read self, pattern, replacement, count)
    }

    pub fn to_lowercase(): String {
        var result = new()
        var chars = self.lowercase_chars()
        while true {
            match chars.next() {
                present(c) => { result.push(c) },
                none => { break }
            }
        }
        result
    }

    pub fn to_uppercase(): String {
        var result = new()
        var chars = self.uppercase_chars()
        while true {
            match chars.next() {
                present(c) => { result.push(c) },
                none => { break }
            }
        }
        result
    }
}

extend<A: Allocator> List<u8, A> implements core.convert.From<String<A>> {
    static fn from(take text: String<A>): List<u8, A> { text.into_bytes() }
}
