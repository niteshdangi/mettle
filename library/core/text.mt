import super.cmp.Eq
import super.cmp.Ord
import super.cmp.Ordering
import super.cmp.PartialEq
import super.cmp.PartialOrd
import super.iter.Iterator

// Unsized, validated UTF-8 view; the view metadata is the byte count. Only
// the checked constructors below create views of Text, which keeps the
// validity invariant: the bytes are well-formed UTF-8.
pub type Text { bytes: [u8] }

// Byte width of the well-formed scalar starting at `i`, or 0 when the bytes
// there are not well-formed UTF-8 (overlong, surrogate, above U+10FFFF,
// truncated or a stray continuation byte).
fn scalar_width(bytes: read [u8], i: usize): usize {
    let size = bytes.len()
    let first = bytes[i]
    if first < 0x80u8 { return 1usize }
    if first < 0xc2u8 || first > 0xf4u8 { return 0usize }
    let width = if first < 0xe0u8 { 2usize } else if first < 0xf0u8 { 3usize } else { 4usize }
    if size - i < width { return 0usize }
    let second = bytes[i + 1usize]
    var low = 0x80u8
    var high = 0xbfu8
    if first == 0xe0u8 { low = 0xa0u8 }
    if first == 0xedu8 { high = 0x9fu8 }
    if first == 0xf0u8 { low = 0x90u8 }
    if first == 0xf4u8 { high = 0x8fu8 }
    if second < low || second > high { return 0usize }
    var offset = 2usize
    while offset < width {
        if (bytes[i + offset] & 0xc0u8) != 0x80u8 { return 0usize }
        offset += 1usize
    }
    width
}

// Safety: a well-formed scalar of `width` bytes starts at `i`.
fn scalar_at(bytes: read [u8], i: usize, width: usize): char {
    let first = bytes[i] as u32
    var value = first
    if width == 2usize { value = first & 0x1fu32 }
    if width == 3usize { value = first & 0x0fu32 }
    if width == 4usize { value = first & 0x07u32 }
    var offset = 1usize
    while offset < width {
        value = (value << 6u32) | ((bytes[i + offset] as u32) & 0x3fu32)
        offset += 1usize
    }
    unsafe { core.mem.transmute<char>(value) }
}

pub fn from_utf8(bytes: read [u8]): (read Text from bytes)? {
    var i = 0usize
    while i < bytes.len() {
        let width = scalar_width(bytes, i)
        if width == 0usize { return none }
        i += width
    }
    present(unsafe { from_utf8_unchecked(bytes) })
}

// Safety: `bytes` is well-formed UTF-8.
pub unsafe fn from_utf8_unchecked(bytes: read [u8]): read Text from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read Text>>(fat) }
    unsafe { read *view }
}

// Safety: `bytes` is well-formed UTF-8 and stays so while the view is live.
pub unsafe fn from_utf8_unchecked_mut(bytes: mut [u8]): mut Text from bytes {
    let fat = core.ptr.from_mut(bytes)
    let view = unsafe { core.mem.transmute<ptr<mut Text>>(fat) }
    unsafe { mut *view }
}

pub type Chars<region r> { bytes: read [u8] from r; position: usize }
extend<region r> Chars<region r> implements Iterator {
    type Item = char
    mut fn next(): char? {
        if self.position >= self.bytes.len() { return none }
        let width = scalar_width(self.bytes, self.position)
        let value = scalar_at(self.bytes, self.position, width)
        self.position += width
        present(value)
    }
}

pub type CharIndices<region r> { bytes: read [u8] from r; position: usize }
extend<region r> CharIndices<region r> implements Iterator {
    type Item = (usize, char)
    mut fn next(): (usize, char)? {
        if self.position >= self.bytes.len() { return none }
        let start = self.position
        let width = scalar_width(self.bytes, start)
        let value = scalar_at(self.bytes, start, width)
        self.position += width
        present((start, value))
    }
}

// Pieces between occurrences of `separator`; an empty separator yields the whole text.
pub type Split<region r> { rest: read Text from r; separator: read Text from r; done: bool }
extend<region r> Split<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        if self.separator.is_empty() {
            self.done = true
            return present(self.rest)
        }
        match self.rest.split_once(self.separator) {
            present(p) => { self.rest = p.1; present(p.0) },
            none => { self.done = true; present(self.rest) }
        }
    }
}

// Lines ended by `\n` or `\r\n`; a final line without a terminator is kept and
// a trailing terminator does not produce an empty line.
pub type Lines<region r> { rest: read Text from r; newline: read Text from r }
extend<region r> Lines<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.rest.is_empty() { return none }
        match self.rest.split_once(self.newline) {
            present(p) => {
                self.rest = p.1
                if p.0.ends_with("\r") {
                    match p.0.get(0usize, p.0.len() - 1usize) { present(line) => present(line), none => present(p.0) }
                } else {
                    present(p.0)
                }
            },
            none => {
                let line = self.rest
                match line.get(line.len(), line.len()) { present(empty) => { self.rest = empty }, none => {} }
                present(line)
            }
        }
    }
}

fn is_ascii_space(byte: u8): bool {
    byte == 0x20u8 || (byte >= 0x09u8 && byte <= 0x0du8)
}

pub type Bytes<region r> { bytes: read [u8] from r; position: usize }
extend<region r> Bytes<region r> implements Iterator {
    type Item = u8
    mut fn next(): u8? {
        if self.position >= self.bytes.len() { return none }
        let value = self.bytes[self.position]
        self.position += 1usize
        present(value)
    }
}

extend Text {
    pub fn len(): usize { self.bytes.len() }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn is_char_boundary(index: usize): bool {
        if index == 0usize || index == self.bytes.len() { return true }
        if index > self.bytes.len() { return false }
        (self.bytes[index] & 0xc0u8) != 0x80u8
    }
    pub fn get(start: usize, end: usize): (read Text from self)? {
        if start > end || !self.is_char_boundary(start) || !self.is_char_boundary(end) {
            return none
        }
        match super.slice.subslice(read self.bytes, start, end) {
            present(part) => present(unsafe { from_utf8_unchecked(part) }),
            none => none
        }
    }
    pub fn starts_with(prefix: read Text): bool {
        let count = prefix.bytes.len()
        if count > self.bytes.len() { return false }
        var i = 0usize
        while i < count {
            if self.bytes[i] != prefix.bytes[i] { return false }
            i += 1usize
        }
        true
    }
    pub fn find_byte(byte: u8): usize? {
        var i = 0usize
        while i < self.bytes.len() {
            if self.bytes[i] == byte { return present(i) }
            i += 1usize
        }
        none
    }
    // Byte offset of the first occurrence of `pattern`; the empty pattern is at 0.
    pub fn find(pattern: read Text): usize? {
        let n = pattern.bytes.len()
        if n > self.bytes.len() { return none }
        var i = 0usize
        while i + n <= self.bytes.len() {
            var j = 0usize
            while j < n && self.bytes[i + j] == pattern.bytes[j] { j += 1usize }
            if j == n { return present(i) }
            i += 1usize
        }
        none
    }
    pub fn contains(pattern: read Text): bool { match self.find(pattern) { present(at) => true, none => false } }
    pub fn ends_with(suffix: read Text): bool {
        let n = suffix.bytes.len()
        if n > self.bytes.len() { return false }
        let offset = self.bytes.len() - n
        var i = 0usize
        while i < n {
            if self.bytes[offset + i] != suffix.bytes[i] { return false }
            i += 1usize
        }
        true
    }
    // ASCII whitespace: space, \t, \n, \v (0x0b), \f (0x0c), \r.
    pub fn trim_start(): read Text from self {
        var i = 0usize
        while i < self.bytes.len() && is_ascii_space(self.bytes[i]) { i += 1usize }
        match self.get(i, self.bytes.len()) { present(part) => part, none => read self }
    }
    pub fn trim_end(): read Text from self {
        var j = self.bytes.len()
        while j > 0usize && is_ascii_space(self.bytes[j - 1usize]) { j -= 1usize }
        match self.get(0usize, j) { present(part) => part, none => read self }
    }
    pub fn trim(): read Text from self {
        var i = 0usize
        while i < self.bytes.len() && is_ascii_space(self.bytes[i]) { i += 1usize }
        var j = self.bytes.len()
        while j > i && is_ascii_space(self.bytes[j - 1usize]) { j -= 1usize }
        match self.get(i, j) { present(part) => part, none => read self }
    }
    // Splits at the first `separator` into the text before and after it.
    pub fn split_once(separator: read Text): (read Text from self, read Text from self)? {
        match self.find(separator) {
            present(at) => {
                let end = at + separator.bytes.len()
                match self.get(0usize, at) {
                    present(head) => match self.get(end, self.bytes.len()) {
                        present(tail) => present((head, tail)),
                        none => none
                    },
                    none => none
                }
            },
            none => none
        }
    }
    pub fn split(separator: read Text from self): Split<region self> { Split(read self, read separator, false) }
    pub fn lines(): Lines<region self> { Lines(read self, "\n") }
    pub fn chars(): Chars<region self> { Chars(read self.bytes, 0usize) }
    pub fn char_indices(): CharIndices<region self> { CharIndices(read self.bytes, 0usize) }
    pub fn bytes(): Bytes<region self> { Bytes(read self.bytes, 0usize) }
}

extend Text implements PartialEq {
    fn eq(other: read Text): bool {
        if self.bytes.len() != other.bytes.len() { return false }
        var i = 0usize
        while i < self.bytes.len() {
            if self.bytes[i] != other.bytes[i] { return false }
            i += 1usize
        }
        true
    }
}

// Checked slicing: panics when the range is reversed, out of bounds or does
// not start and end on a UTF-8 scalar boundary.
extend Text implements super.ops.IndexRange {
    type Output = Text
    fn index_range(start: usize, end: usize): read Text from self {
        let stop = if end == 0xffffffffffffffffusize { self.bytes.len() } else { end }
        match self.get(start, stop) {
            present(part) => part,
            none => super.panic.panic("text slice is out of bounds or not on a character boundary")
        }
    }
}

extend Text implements Eq {}
extend Text implements PartialOrd {
    fn partial_cmp(other: read Text): Ordering? { present(self.cmp(other)) }
}
// UTF-8 byte order equals scalar value order.
extend Text implements Ord {
    fn cmp(other: read Text): Ordering {
        var i = 0usize
        while i < self.bytes.len() && i < other.bytes.len() {
            if self.bytes[i] != other.bytes[i] {
                return if self.bytes[i] < other.bytes[i] { Ordering.Less } else { Ordering.Greater }
            }
            i += 1usize
        }
        self.bytes.len().cmp(other.bytes.len())
    }
}
