import package.core.iter.{Iterator, BidirectionalIterator}
import super.alloc.{Allocator, Global, AllocError, panic_precondition}
import package.core.clone.Clone
import package.core.default.Default
import package.core.fmt
import package.core.ops.{Deref, IndexRange}
import package.core.hash.{Hash, Hasher}
import package.core.borrow.KeyView
import super.vec.{List, slice_ptr}
import package.core.cmp.{Ordering, PartialEq, Eq, PartialOrd, Ord}
import package.core.text.{Text, from_utf8_unchecked}

// Owned, growable UTF-8 text: a `List<u8>` whose bytes are always well formed.
pub type String<A: Allocator = Global> {
    v: List<u8, A>
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
fn from_valid_bytes<A: Allocator>(bytes: take List<u8, A>): String<A> {
    let result: String<A>
    result.v = take bytes
    result
}

pub fn new_in<A: Allocator>(a: take A): String<A> {
    from_valid_bytes(super.vec.new_in<u8, A>(take a))
}
pub fn new(): String { new_in(Global()) }
pub fn try_with_capacity_in<A: Allocator>(n: usize, a: take A): String<A> throws AllocError {
    from_valid_bytes(try super.vec.try_with_capacity_in<u8, A>(n, take a))
}
pub fn with_capacity_in<A: Allocator>(n: usize, a: take A): String<A> {
    from_valid_bytes(super.vec.with_capacity_in<u8, A>(n, take a))
}
pub fn try_with_capacity(n: usize): String throws AllocError {
    try try_with_capacity_in(n, Global())
}
pub fn with_capacity(n: usize): String {
    from_valid_bytes(super.vec.with_capacity<u8>(n))
}
pub fn from_text(t: read Text): String {
    var s = new()
    s.push_str(t)
    s
}
pub fn from_text_in<A: Allocator>(t: read Text, a: take A): String<A> {
    var s = new_in(a)
    s.push_str(t)
    s
}

// Validates `bytes`; on failure the buffer comes back in the error.
pub fn from_utf8<A: Allocator>(bytes: take List<u8, A>): String<A> throws FromUtf8Error<A> {
    let ok = match package.core.text.from_utf8(bytes.as_slice()) {
        present(_) => true,
        none => false
    }
    if !ok {
        let n = valid_prefix(bytes.as_slice())
        throw FromUtf8Error(bytes, n)
    }
    from_valid_bytes(take bytes)
}

extend String {
    pub init(text: read Text) {
        self.v = super.vec.new<u8>()
        self.push_str(text)
    }
}

extend<A: Allocator> String<A> {
    pub init(text: read Text, allocator: take A) {
        self.v = super.vec.new_in<u8, A>(take allocator)
        self.push_str(text)
    }
}

// Length of the longest well-formed prefix.
fn valid_prefix(bytes: read [u8]): usize {
    var end = bytes.len()
    while end > 0usize {
        let ok = match package.core.slice.subslice(bytes, 0usize, end) {
            present(part) => match package.core.text.from_utf8(part) { present(_) => true, none => false },
            none => false
        }
        if ok { return end }
        end -= 1usize
    }
    0usize
}

fn encode_utf8(c: char, out: mut [u8; 4]): usize {
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

fn valid_utf8_width(bytes: read [u8], start: usize): usize {
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

fn invalid_utf8_width(bytes: read [u8], start: usize): usize {
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

pub fn from_utf8_lossy(bytes: read [u8]): String {
    var result = new()
    var index = 0usize
    while index < bytes.len() {
        let width = valid_utf8_width(bytes, index)
        if width != 0usize {
            let part = match package.core.slice.subslice(bytes, index, index + width) {
                present(value) => value,
                none => { panic_precondition() }
            }
            let text = match package.core.text.from_utf8(part) {
                present(value) => value,
                none => { panic_precondition() }
            }
            result.push_str(text)
            index += width
        } else {
            result.push(match package.core.char.from_u32(0xfffdu32) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += invalid_utf8_width(bytes, index)
        }
    }
    result
}

pub fn from_utf16(units: read [u16]): String throws FromUtf16Error {
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
        result.push(match package.core.char.from_u32(scalar) {
            present(value) => value,
            none => { throw FromUtf16Error(index, units[index]) }
        })
        index += 1usize
    }
    result
}

pub fn from_utf16_lossy(units: read [u16]): String {
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
            result.push(match package.core.char.from_u32(scalar) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += 2usize
        } else if first >= 0xd800u32 && first <= 0xdfffu32 {
            result.push(match package.core.char.from_u32(0xfffdu32) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += 1usize
        } else {
            result.push(match package.core.char.from_u32(first) {
                present(value) => value,
                none => { panic_precondition() }
            })
            index += 1usize
        }
    }
    result
}

fn first_char(t: read Text): char {
    var it = t.chars()
    match it.next() { present(c) => c, none => panic_precondition() }
}

extend<A: Allocator> String<A> {
    pub fn len(): usize { self.v.len() }
    pub fn capacity(): usize { self.v.capacity() }
    pub fn is_empty(): bool { self.v.is_empty() }
    pub fn as_bytes(): read [u8] from self { self.v.as_slice() }
    // Borrowed text view; while it lives the string cannot change.
    pub fn as_text(): read Text from self { unsafe { from_utf8_unchecked(self.v.as_slice()) } }
    pub take fn into_bytes(): List<u8, A> {
        unsafe {
            let v = core.ptr.`read`(core.ptr.from_ref(self.v))
            core.mem.forget(take self)
            v
        }
    }
    // Safety: the bytes must be well-formed UTF-8 again before the string is
    // next observed as text (including on drop-free early exits such as errors).
    pub mut unsafe fn as_mut_vec(): mut List<u8, A> from self { mut self.v }
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

    pub mut fn try_push_str(t: read Text): Unit throws AllocError {
        let bytes = t.as_bytes()
        try self.v.try_reserve(bytes.len())
        var i = 0usize
        while i < bytes.len() {
            let b = bytes[i]
            self.v.push(b)
            i += 1usize
        }
    }
    pub mut fn push_str(t: read Text): Unit {
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
    pub mut fn insert_str(index: usize, t: read Text): Unit {
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
    pub mut fn replace_range(start: usize, end: usize, replacement: read Text): Unit {
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
}

extend<A: Allocator + Clone> String<A> implements Clone {
    fn clone(): String<A> { from_valid_bytes(self.v.clone()) }
}
extend<A: Allocator + Default> String<A> implements Default {
    static fn default(): String<A> { new_in<A>(A.(Default).default()) }
}

extend<A: Allocator> String<A> implements PartialEq {
    fn eq(other: read String<A>): bool { self.as_text() == other.as_text() }
}
extend<A: Allocator> String<A> implements Eq {}

extend<A: Allocator> String<A> implements PartialOrd {
    fn partial_cmp(other: read String<A>): Ordering? { self.as_text().partial_cmp(other.as_text()) }
}
extend<A: Allocator> String<A> implements Ord {
    fn cmp(other: read String<A>): Ordering { self.as_text().cmp(other.as_text()) }
}

// A String key can be searched by its Text; String hashes as Text does.
extend<A: Allocator> String<A> implements KeyView<Text> {
    fn key_view(): read Text from self { self.as_text() }
}
extend<A: Allocator> String<A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.as_text().hash(mut state) }
}

// Appends formatted output to the string; allocation failure aborts like push.
extend<A: Allocator> String<A> implements fmt.Write {
    mut fn write_str(s: read Text): Unit throws fmt.Error {
        self.push_str(s)
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
    fn deref(): read Text from self { self.as_text() }
}
extend<A: Allocator> String<A> implements IndexRange {
    type Output = Text
    fn index_range(start: usize, end: usize): read Text from self { self.as_text().index_range(start, end) }
}
extend<A: Allocator> String<A> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.pad(self.as_text()) }
}
extend<A: Allocator> String<A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try Text.(fmt.Debug).fmt(self.as_text(), mut f) }
}

// Concatenation: a new string holding `a` followed by `b`.
pub fn concat(a: read Text, b: read Text): String {
    var s = with_capacity(a.len() + b.len())
    s.push_str(a)
    s.push_str(b)
    s
}

fn replace_text(text: read Text, pattern: read Text, replacement: read Text, limit: usize): String {
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
        var result = new()
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

    pub fn replace(pattern: read Text, replacement: read Text): String {
        replace_text(read self, pattern, replacement, 0xffffffffffffffffusize)
    }

    pub fn replacen(pattern: read Text, replacement: read Text, count: usize): String {
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

extend<A: Allocator> List<u8, A> implements package.core.convert.From<String<A>> {
    static fn `from`(text: take String<A>): List<u8, A> { text.into_bytes() }
}
