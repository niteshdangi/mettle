import super.cmp.Eq
import super.cmp.Ord
import super.cmp.Ordering
import super.cmp.PartialEq
import super.cmp.PartialOrd
import super.char
import super.iter.{Iterator, BidirectionalIterator}
import super.fmt.{Debug, Formatter, Error}
import super.ops.RangeEnd
import super.borrow.AsRef

// Unsized, validated UTF-8 view; the view metadata is the byte count. Only
// the checked constructors below create views of Text, which keeps the
// validity invariant: the bytes are well-formed UTF-8.
pub type Text { bytes: [u8] }

pub interface FromStr: Sized {
    type Error;
    static fn from_str(read input: Text): Self throws Self.Error;
}

extend Text {
    pub fn parse<T: FromStr>(): T throws T.Error {
        try T.(FromStr).from_str(read self)
    }
}

// A successful match reports its byte length on a UTF-8 scalar boundary.
// Empty matches stop trimming; a predicate is called only on a present scalar.
interface Pattern {
    mut fn match_front(read text: Text): usize?;
    mut fn match_back(read text: Text): usize?;
}

interface DoubleEndedPattern: Pattern {}
extend char implements DoubleEndedPattern {}
extend<F: mut fn(char): bool> F implements DoubleEndedPattern {}
extend<region r> read [char] from r implements DoubleEndedPattern {}
extend<region r, const N: usize> read [char; N] from r implements DoubleEndedPattern {}
extend<const N: usize> [char; N] implements DoubleEndedPattern {}

interface ClonePattern: Pattern + Sized { fn clone_pattern(): Self; }
extend char implements ClonePattern { fn clone_pattern(): char { self } }
extend<region r> read Text from r implements ClonePattern {
    fn clone_pattern(): read Text from r { self }
}
extend<region r> read [char] from r implements ClonePattern {
    fn clone_pattern(): read [char] from r { self }
}
extend<region r, const N: usize> read [char; N] from r implements ClonePattern {
    fn clone_pattern(): read [char; N] from r { self }
}
extend<const N: usize> [char; N] implements ClonePattern {
    fn clone_pattern(): [char; N] { self }
}
extend<F: mut fn(char): bool + super.clone.Clone> F implements ClonePattern {
    fn clone_pattern(): F { self.clone() }
}

interface DebugPattern: Pattern { fn fmt_pattern(mut f: Formatter): Unit throws Error; }
extend char implements DebugPattern {
    fn fmt_pattern(mut f: Formatter): Unit throws Error { try char.(Debug).fmt(read self, mut f) }
}
extend<region r> read Text from r implements DebugPattern {
    fn fmt_pattern(mut f: Formatter): Unit throws Error { try Text.(Debug).fmt(self, mut f) }
}
extend<region r> read [char] from r implements DebugPattern {
    fn fmt_pattern(mut f: Formatter): Unit throws Error { try self.fmt(mut f) }
}
extend<region r, const N: usize> read [char; N] from r implements DebugPattern {
    fn fmt_pattern(mut f: Formatter): Unit throws Error { try self.fmt(mut f) }
}
extend<const N: usize> [char; N] implements DebugPattern {
    fn fmt_pattern(mut f: Formatter): Unit throws Error { try self.fmt(mut f) }
}
extend<F: mut fn(char): bool + Debug> F implements DebugPattern {
    fn fmt_pattern(mut f: Formatter): Unit throws Error { try F.(Debug).fmt(read self, mut f) }
}
type PatternDebugRef<region r, P> { pattern: read P from r }
extend<region r, P: DebugPattern> PatternDebugRef<region r, P> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try self.pattern.fmt_pattern(mut f) }
}

fn find_pattern<P: Pattern>(
    read text: Text, mut pattern: P, reverse: bool
): (usize, usize)? {
    var at = if reverse { text.len() } else { 0usize }
    while true {
        let part = if reverse { text.get(0usize, at).unwrap() } else { text.get(at, text.len()).unwrap() }
        let matched = if reverse { pattern.match_back(part) } else { pattern.match_front(part) }
        match matched {
            present(length) => {
                if length > part.len() { super.panic.panic("invalid text pattern length") }
                let start = if reverse { at - length } else { at }
                let end = start + length
                if !text.is_char_boundary(start) || !text.is_char_boundary(end) {
                    super.panic.panic("invalid text pattern boundary")
                }
                return present((start, end))
            },
            none => {}
        }
        if reverse {
            if at == 0usize { break }
            at -= 1usize
            while !text.is_char_boundary(at) { at -= 1usize }
        } else {
            if at == text.len() { break }
            at += scalar_width(text.bytes, at)
        }
    }
    none
}

fn match_text_edge(read text: Text, read pattern: Text, reverse: bool): usize? {
    if pattern.len() > text.len() { return none }
    let start = if reverse { text.len() - pattern.len() } else { 0usize }
    var index = 0usize
    while index < pattern.len() {
        if text.bytes[start + index] != pattern.bytes[index] { return none }
        index += 1usize
    }
    present(pattern.len())
}

extend<region r> read Text from r implements Pattern {
    mut fn match_front(read text: Text): usize? {
        match_text_edge(text, self, false)
    }
    mut fn match_back(read text: Text): usize? {
        match_text_edge(text, self, true)
    }
}

extend char implements Pattern {
    mut fn match_front(read text: Text): usize? {
        var chars = text.chars()
        match chars.next() {
            present(value) => if value == self { present(value.len_utf8()) } else { none },
            none => none
        }
    }
    mut fn match_back(read text: Text): usize? {
        var chars = text.chars()
        match chars.next_back() {
            present(value) => if value == self { present(value.len_utf8()) } else { none },
            none => none
        }
    }
}

extend<F: mut fn(char): bool> F implements Pattern {
    mut fn match_front(read text: Text): usize? {
        var chars = text.chars()
        match chars.next() {
            present(value) => if self(value) { present(value.len_utf8()) } else { none },
            none => none
        }
    }
    mut fn match_back(read text: Text): usize? {
        var chars = text.chars()
        match chars.next_back() {
            present(value) => if self(value) { present(value.len_utf8()) } else { none },
            none => none
        }
    }
}

fn match_character_set(read text: Text, read values: [char], reverse: bool): usize? {
    var chars = text.chars()
    let next = if reverse { chars.next_back() } else { chars.next() }
    match next {
        present(value) => {
            var index = 0usize
            while index < values.len() {
                if values[index] == value { return present(value.len_utf8()) }
                index += 1usize
            }
            none
        },
        none => none
    }
}

extend<region r> read [char] from r implements Pattern {
    mut fn match_front(read text: Text): usize? { match_character_set(text, self, false) }
    mut fn match_back(read text: Text): usize? { match_character_set(text, self, true) }
}

extend<region r, const N: usize> read [char; N] from r implements Pattern {
    mut fn match_front(read text: Text): usize? { match_character_set(text, self, false) }
    mut fn match_back(read text: Text): usize? { match_character_set(text, self, true) }
}

extend<const N: usize> [char; N] implements Pattern {
    mut fn match_front(read text: Text): usize? { match_character_set(text, read self, false) }
    mut fn match_back(read text: Text): usize? { match_character_set(text, read self, true) }
}

fn trim_pattern_start<P: Pattern>(read text: Text, mut pattern: P): read Text from text {
    var start = 0usize
    while start < text.len() {
        let remaining = match text.get(start, text.len()) {
            present(part) => part,
            none => { super.panic.panic("trim pattern boundary invariant failed") }
        }
        match pattern.match_front(remaining) {
            present(length) => {
                if length == 0usize { break }
                if length > remaining.len() || !remaining.is_char_boundary(length) {
                    super.panic.panic("invalid trim pattern boundary")
                }
                start += length
            },
            none => { break }
        }
    }
    match text.get(start, text.len()) {
        present(part) => part,
        none => { super.panic.panic("trim pattern boundary invariant failed") }
    }
}

fn trim_pattern_end<P: Pattern>(read text: Text, mut pattern: P, keep: usize): read Text from text {
    var end = text.len()
    while end > keep {
        let remaining = match text.get(0usize, end) {
            present(part) => part,
            none => { super.panic.panic("trim pattern boundary invariant failed") }
        }
        match pattern.match_back(remaining) {
            present(length) => {
                if length == 0usize { break }
                if length > end || !remaining.is_char_boundary(end - length) {
                    super.panic.panic("invalid trim pattern boundary")
                }
                if length > end - keep { break }
                end -= length
            },
            none => { break }
        }
    }
    match text.get(0usize, end) {
        present(part) => part,
        none => { super.panic.panic("trim pattern boundary invariant failed") }
    }
}

// Byte width of the well-formed scalar starting at `i`, or 0 when the bytes
// there are not well-formed UTF-8 (overlong, surrogate, above U+10FFFF,
// truncated or a stray continuation byte).
fn scalar_width(read bytes: [u8], i: usize): usize {
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
fn scalar_at(read bytes: [u8], i: usize, width: usize): char {
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

pub copy type Utf8Error { valid: usize; length: usize? }
extend Utf8Error {
    pub const fn valid_up_to(): usize { self.valid }
    pub const fn error_len(): usize? { self.length }
}
extend Utf8Error implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Utf8Error")
        try debug.field("valid_up_to", self.valid)
        try debug.field("error_len", self.length)
        try debug.finish()
    }
}
extend Utf8Error implements super.fmt.Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("invalid UTF-8 sequence")
    }
}
extend Utf8Error implements super.error.Error {}

const fn validate_utf8(read bytes: [u8]): Utf8Error? {
    var i = 0usize
    while i < bytes.len() {
        let first = bytes[i]
        if first < 0x80u8 { i += 1usize; continue }
        if first < 0xc2u8 || first > 0xf4u8 { return present(Utf8Error(i, present(1usize))) }
        let needed = if first < 0xe0u8 { 2usize } else if first < 0xf0u8 { 3usize } else { 4usize }
        var offset = 1usize
        while offset < needed {
            if offset == bytes.len() - i { return present(Utf8Error(i, none)) }
            let byte = bytes[i + offset]
            var low = 0x80u8
            var high = 0xbfu8
            if offset == 1usize {
                if first == 0xe0u8 { low = 0xa0u8 }
                if first == 0xedu8 { high = 0x9fu8 }
                if first == 0xf0u8 { low = 0x90u8 }
                if first == 0xf4u8 { high = 0x8fu8 }
            }
            if byte < low || byte > high { return present(Utf8Error(i, present(offset))) }
            offset += 1usize
        }
        i += needed
    }
    none
}

pub const fn from_utf8(read bytes: [u8]): (Outcome<read Text from bytes, Utf8Error>) {
    match validate_utf8(bytes) {
        present(error) => failure(error),
        none => success(unsafe { from_utf8_unchecked(bytes) })
    }
}

pub const fn from_utf8_mut(mut bytes: [u8]): (Outcome<mut Text from bytes, Utf8Error>) {
    match validate_utf8(read bytes) {
        present(error) => failure(error),
        none => success(unsafe { from_utf8_unchecked_mut(mut bytes) })
    }
}

// Safety: `bytes` is well-formed UTF-8.
pub unsafe const fn from_utf8_unchecked(read bytes: [u8]): read Text from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read Text>>(fat) }
    unsafe { read *view }
}

// Safety: `bytes` is well-formed UTF-8 and stays so while the view is live.
pub unsafe const fn from_utf8_unchecked_mut(mut bytes: [u8]): mut Text from bytes {
    let fat = core.ptr.from_mut(bytes)
    let view = unsafe { core.mem.transmute<ptr<mut Text>>(fat) }
    unsafe { mut *view }
}

pub type Chars<region r> { bytes: read [u8] from r; front: usize; back: usize }
fn count_chars(read bytes: [u8]): usize {
    var count = 0usize
    var index = 0usize
    while index < bytes.len() {
        index += scalar_width(bytes, index)
        count += 1usize
    }
    count
}
extend<region r> Chars<region r> {
    pub fn len(): usize { count_chars(self.as_str().as_bytes()) }
    pub fn as_str(): read Text from r {
        let bytes = match super.slice.subslice(self.bytes, self.front, self.back) {
            present(part) => part,
            none => { super.panic.panic("character iterator boundary invariant failed") }
        }
        unsafe { from_utf8_unchecked(bytes) }
    }
}
extend<region r> Chars<region r> implements Iterator {
    type Item = char
    fn size_hint(): (usize, usize?) {
        let bytes = self.back - self.front
        (bytes / 4usize + if bytes % 4usize == 0usize { 0usize } else { 1usize }, present(bytes))
    }
    mut fn next(): char? {
        if self.front >= self.back { return none }
        let width = scalar_width(self.bytes, self.front)
        let value = scalar_at(self.bytes, self.front, width)
        self.front += width
        present(value)
    }
}
extend<region r> Chars<region r> implements BidirectionalIterator {
    mut fn next_back(): char? {
        if self.front >= self.back { return none }
        var start = self.back - 1usize
        while start > self.front && (self.bytes[start] & 0xc0u8) == 0x80u8 {
            start -= 1usize
        }
        let width = self.back - start
        let value = scalar_at(self.bytes, start, width)
        self.back = start
        present(value)
    }
}
extend<region r> Chars<region r> implements super.clone.Clone {
    fn clone(): Chars<region r> {
        Chars(self.bytes, self.front, self.back)
    }
}
extend<region r> Chars<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Chars")
        try debug.field("text", self.as_str())
        try debug.field("remaining", self.len())
        try debug.finish()
    }
}

pub type CharIndices<region r> { bytes: read [u8] from r; front: usize; back: usize }
extend<region r> CharIndices<region r> {
    pub fn len(): usize { count_chars(self.as_str().as_bytes()) }
    pub fn as_str(): read Text from r {
        let bytes = match super.slice.subslice(self.bytes, self.front, self.back) {
            present(part) => part,
            none => { super.panic.panic("character iterator boundary invariant failed") }
        }
        unsafe { from_utf8_unchecked(bytes) }
    }
    pub fn offset(): usize { self.front }
}
extend<region r> CharIndices<region r> implements Iterator {
    type Item = (usize, char)
    fn size_hint(): (usize, usize?) {
        let bytes = self.back - self.front
        (bytes / 4usize + if bytes % 4usize == 0usize { 0usize } else { 1usize }, present(bytes))
    }
    mut fn next(): (usize, char)? {
        if self.front >= self.back { return none }
        let start = self.front
        let width = scalar_width(self.bytes, start)
        let value = scalar_at(self.bytes, start, width)
        self.front += width
        present((start, value))
    }
}
extend<region r> CharIndices<region r> implements BidirectionalIterator {
    mut fn next_back(): (usize, char)? {
        if self.front >= self.back { return none }
        var start = self.back - 1usize
        while start > self.front && (self.bytes[start] & 0xc0u8) == 0x80u8 {
            start -= 1usize
        }
        let width = self.back - start
        let value = scalar_at(self.bytes, start, width)
        self.back = start
        present((start, value))
    }
}
extend<region r> CharIndices<region r> implements super.clone.Clone {
    fn clone(): CharIndices<region r> {
        CharIndices(self.bytes, self.front, self.back)
    }
}
extend<region r> CharIndices<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("CharIndices")
        try debug.field("text", self.as_str())
        try debug.field("remaining", self.len())
        try debug.finish()
    }
}

fn has_cased_after(read text: Text, byte_index: usize): bool {
    match text.get(byte_index, text.len()) {
        present(suffix) => {
            var chars = suffix.chars()
            match chars.next() { present(_) => {}, none => { return false } }
            while true {
                match chars.next() {
                    present(c) => {
                        if !c.is_case_ignorable() { return c.is_cased() }
                    },
                    none => { return false }
                }
            }
            false
        },
        none => false
    }
}

// Tab, line feed, form feed, carriage return and space: not vertical tab.
const fn is_ascii_whitespace(byte: u8): bool {
    byte == 0x09u8 || byte == 0x0au8 || byte == 0x0cu8 || byte == 0x0du8 || byte == 0x20u8
}

pub type LowercaseChars<region r> {
    text: read Text from r;
    source: CharIndices<region r>;
    pending: super.char.CaseMapping;
    pending_ready: bool;
    preceding_cased: bool
}
extend<region r> LowercaseChars<region r> implements Iterator {
    type Item = char
    mut fn next(): char? {
        while true {
            if self.pending_ready {
                match self.pending.next() {
                    present(c) => { return present(c) },
                    none => { self.pending_ready = false }
                }
            }
            match self.source.next() {
                present(item) => {
                    let c = item.1
                    var mapping = c.to_lowercase()
                    if c == '\u{03a3}' && self.preceding_cased &&
                        !has_cased_after(self.text, item.0) {
                        mapping = '\u{03c2}'.to_lowercase()
                    }
                    if !c.is_case_ignorable() {
                        self.preceding_cased = c.is_cased()
                    }
                    self.pending = mapping
                    self.pending_ready = true
                },
                none => { return none }
            }
        }
        none
    }
}

pub type UppercaseChars<region r> {
    source: CharIndices<region r>;
    pending: super.char.CaseMapping;
    pending_ready: bool
}
pub type TextEscape<region r> {
    chars: Chars<region r>;
    pending: super.char.Escape;
    pending_ready: bool;
    unicode: bool;
    debug: bool;
    first: bool
}
extend<region r> TextEscape<region r> implements Iterator {
    type Item = char
    mut fn next(): char? {
        while true {
            if self.pending_ready {
                match self.pending.next() {
                    present(c) => { return present(c) },
                    none => { self.pending_ready = false }
                }
            }
            match self.chars.next() {
                present(c) => {
                    self.pending = if self.unicode { c.escape_unicode() }
                        else if self.debug { c.escape_debug_ext(true, true, self.first) }
                        else { c.escape_default() }
                    self.first = false
                    self.pending_ready = true
                },
                none => { return none }
            }
        }
        none
    }
}
extend<region r> UppercaseChars<region r> implements Iterator {
    type Item = char
    mut fn next(): char? {
        while true {
            if self.pending_ready {
                match self.pending.next() {
                    present(c) => { return present(c) },
                    none => { self.pending_ready = false }
                }
            }
            match self.source.next() {
                present(item) => {
                    self.pending = item.1.to_uppercase()
                    self.pending_ready = true
                },
                none => { return none }
            }
        }
        none
    }
}

pub type Split<region r, P = read Text from r> {
    rest: read Text from r
    pattern: P
    done: bool
    front_empty: bool
    back_empty: bool
}
extend<region r, P: Pattern> Split<region r, P> {
    mut fn finish(): (read Text from r)? {
        if self.done { return none }
        self.done = true
        present(self.rest)
    }
    mut fn next_reverse(): (read Text from r)? {
        if self.done { return none }
        let end = self.rest.len()
        var search_end = end
        if !self.back_empty {
            if end == 0usize { return self.finish() }
            search_end = end - 1usize
            while !self.rest.is_char_boundary(search_end) { search_end -= 1usize }
        }
        let search = self.rest.get(0usize, search_end).unwrap()
        match find_pattern(search, mut self.pattern, true) {
            present((start, stop)) => {
                self.back_empty = stop != start
                let piece = self.rest.get(stop, end).unwrap()
                self.rest = self.rest.get(0usize, start).unwrap()
                present(piece)
            },
            none => self.finish()
        }
    }
}
extend<region r, P: Pattern> Split<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        var search_start = 0usize
        if !self.front_empty {
            if self.rest.is_empty() { return self.finish() }
            search_start = scalar_width(self.rest.bytes, 0usize)
        }
        let search = self.rest.get(search_start, self.rest.len()).unwrap()
        match find_pattern(search, mut self.pattern, false) {
            present((start, stop)) => {
                self.front_empty = stop != start
                let piece = self.rest.get(0usize, search_start + start).unwrap()
                self.rest = self.rest.get(search_start + stop, self.rest.len()).unwrap()
                present(piece)
            },
            none => self.finish()
        }
    }
}
extend<region r, P: DoubleEndedPattern> Split<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? { self.next_reverse() }
}
extend<region r, P: ClonePattern> Split<region r, P> implements super.clone.Clone {
    fn clone(): Split<region r, P> {
        Split(self.rest, self.pattern.clone_pattern(), self.done, self.front_empty, self.back_empty)
    }
}
extend<region r, P: DebugPattern> Split<region r, P> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Split")
        try debug.field("rest", self.rest)
        try debug.field("separator", PatternDebugRef(read self.pattern))
        try debug.field("done", self.done)
        try debug.finish()
    }
}
pub type RSplit<region r, P> { inner: Split<region r, P> }
extend<region r, P: Pattern> RSplit<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? { self.inner.next_reverse() }
}
extend<region r, P: DoubleEndedPattern> RSplit<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? { self.inner.next() }
}

pub type SplitN<region r> { inner: Split<region r, read Text from r>; remaining: usize }
extend<region r> SplitN<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.remaining == 0usize { self.inner.finish() } else { self.inner.next() }
    }
}
pub type RSplitN<region r> { inner: Split<region r, read Text from r>; remaining: usize }
extend<region r> RSplitN<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.remaining == 0usize { self.inner.finish() } else { self.inner.next_reverse() }
    }
}
pub type SplitTerminator<region r> { inner: Split<region r, read Text from r> }
extend<region r> SplitTerminator<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        match self.inner.next() {
            present(piece) => if piece.is_empty() && self.inner.done { none } else { present(piece) },
            none => none
        }
    }
}
pub type RSplitTerminator<region r> { inner: Split<region r, read Text from r>; first: bool }
extend<region r> RSplitTerminator<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.first {
            self.first = false
            match self.inner.next_reverse() {
                present(piece) => { if !piece.is_empty() { return present(piece) } },
                none => { return none }
            }
        }
        self.inner.next_reverse()
    }
}
pub type SplitInclusive<region r> {
    rest: read Text from r
    separator: read Text from r
    done: bool
    first: bool
}
extend<region r> SplitInclusive<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        if self.separator.is_empty() {
            if self.first {
                self.first = false
                if self.rest.is_empty() { self.done = true }
                return self.rest.get(0usize, 0usize)
            }
            if self.rest.is_empty() { self.done = true; return none }
            let end = scalar_width(self.rest.bytes, 0usize)
            let piece = self.rest.get(0usize, end).unwrap()
            self.rest = self.rest.get(end, self.rest.len()).unwrap()
            if self.rest.is_empty() { self.done = true }
            return present(piece)
        }
        if self.rest.is_empty() { self.done = true; return none }
        match self.rest.find(read *self.separator) {
            present(at) => {
                let end = at + self.separator.len()
                let piece = self.rest.get(0usize, end).unwrap()
                self.rest = self.rest.get(end, self.rest.len()).unwrap()
                if self.rest.is_empty() { self.done = true }
                present(piece)
            },
            none => { self.done = true; present(self.rest) }
        }
    }
}

pub type Matches<region r, P = read Text from r> {
    text: read Text from r
    pattern: P
    front: usize
    back: usize
    done: bool
}
extend<region r, P: Pattern> Matches<region r, P> {
    mut fn next_range(reverse: bool): (usize, usize)? {
        if self.done { return none }
        let part = self.text.get(self.front, self.back).unwrap()
        match find_pattern(part, mut self.pattern, reverse) {
            present((start, end)) => {
                let first = self.front + start
                let last = self.front + end
                if first == last {
                    if self.front == self.back { self.done = true }
                    else if reverse {
                        self.back -= 1usize
                        while !self.text.is_char_boundary(self.back) { self.back -= 1usize }
                    } else { self.front += scalar_width(self.text.bytes, self.front) }
                } else if reverse { self.back = first }
                else { self.front = last }
                present((first, last))
            },
            none => { self.done = true; none }
        }
    }
}
extend<region r, P: Pattern> Matches<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        match self.next_range(false) {
            present((start, end)) => self.text.get(start, end),
            none => none
        }
    }
}
extend<region r, P: DoubleEndedPattern> Matches<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? {
        match self.next_range(true) {
            present((start, end)) => self.text.get(start, end),
            none => none
        }
    }
}
pub type RMatches<region r, P> { inner: Matches<region r, P> }
extend<region r, P: Pattern> RMatches<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        match self.inner.next_range(true) {
            present((start, end)) => self.inner.text.get(start, end),
            none => none
        }
    }
}
extend<region r, P: DoubleEndedPattern> RMatches<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? { self.inner.next() }
}
pub type MatchIndices<region r, P = read Text from r> { inner: Matches<region r, P> }
extend<region r, P: Pattern> MatchIndices<region r, P> implements Iterator {
    type Item = (usize, read Text from r)
    mut fn next(): (usize, read Text from r)? {
        match self.inner.next_range(false) {
            present((start, end)) => present((start, self.inner.text.get(start, end).unwrap())),
            none => none
        }
    }
}
extend<region r, P: DoubleEndedPattern> MatchIndices<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (usize, read Text from r)? {
        match self.inner.next_range(true) {
            present((start, end)) => present((start, self.inner.text.get(start, end).unwrap())),
            none => none
        }
    }
}
pub type RMatchIndices<region r, P> { inner: Matches<region r, P> }
extend<region r, P: Pattern> RMatchIndices<region r, P> implements Iterator {
    type Item = (usize, read Text from r)
    mut fn next(): (usize, read Text from r)? {
        match self.inner.next_range(true) {
            present((start, end)) => present((start, self.inner.text.get(start, end).unwrap())),
            none => none
        }
    }
}
extend<region r, P: DoubleEndedPattern> RMatchIndices<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (usize, read Text from r)? {
        match self.inner.next_range(false) {
            present((start, end)) => present((start, self.inner.text.get(start, end).unwrap())),
            none => none
        }
    }
}

pub type SplitWhitespace<region r> {
    rest: read Text from r;
    ascii: bool
}
extend<region r> SplitWhitespace<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        var start = 0usize
        while start < self.rest.len() {
            let width = scalar_width(self.rest.bytes, start)
            let whitespace = if self.ascii {
                width == 1usize && is_ascii_whitespace(self.rest.bytes[start])
            } else {
                scalar_at(self.rest.bytes, start, width).is_whitespace()
            }
            if !whitespace { break }
            start += width
        }
        if start == self.rest.len() {
            self.rest = match self.rest.get(start, start) {
                present(empty) => empty,
                none => { super.panic.panic("split boundary invariant failed") }
            }
            return none
        }
        var end = start
        while end < self.rest.len() {
            let width = scalar_width(self.rest.bytes, end)
            let whitespace = if self.ascii {
                width == 1usize && is_ascii_whitespace(self.rest.bytes[end])
            } else {
                scalar_at(self.rest.bytes, end, width).is_whitespace()
            }
            if whitespace { break }
            end += width
        }
        let item = match self.rest.get(start, end) {
            present(value) => value,
            none => { super.panic.panic("split boundary invariant failed") }
        }
        self.rest = match self.rest.get(end, self.rest.len()) {
            present(value) => value,
            none => { super.panic.panic("split boundary invariant failed") }
        }
        present(item)
    }
}
extend<region r> SplitWhitespace<region r> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? {
        var end = self.rest.len()
        while end > 0usize {
            var start = end - 1usize
            while start > 0usize && (self.rest.bytes[start] & 0xc0u8) == 0x80u8 {
                start -= 1usize
            }
            let width = end - start
            let whitespace = if self.ascii {
                width == 1usize && is_ascii_whitespace(self.rest.bytes[start])
            } else {
                scalar_at(self.rest.bytes, start, width).is_whitespace()
            }
            if !whitespace { break }
            end = start
        }
        if end == 0usize {
            self.rest = match self.rest.get(0usize, 0usize) {
                present(empty) => empty,
                none => { super.panic.panic("split boundary invariant failed") }
            }
            return none
        }

        var start = end
        while start > 0usize {
            var previous = start - 1usize
            while previous > 0usize &&
                (self.rest.bytes[previous] & 0xc0u8) == 0x80u8 {
                previous -= 1usize
            }
            let width = start - previous
            let whitespace = if self.ascii {
                width == 1usize && is_ascii_whitespace(self.rest.bytes[previous])
            } else {
                scalar_at(self.rest.bytes, previous, width).is_whitespace()
            }
            if whitespace { break }
            start = previous
        }
        let item = match self.rest.get(start, end) {
            present(value) => value,
            none => { super.panic.panic("split boundary invariant failed") }
        }
        self.rest = match self.rest.get(0usize, start) {
            present(value) => value,
            none => { super.panic.panic("split boundary invariant failed") }
        }
        present(item)
    }
}
extend<region r> SplitWhitespace<region r> implements super.clone.Clone {
    fn clone(): SplitWhitespace<region r> { SplitWhitespace(self.rest, self.ascii) }
}
extend<region r> SplitWhitespace<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("SplitWhitespace")
        try debug.field("rest", self.rest)
        try debug.field("ascii", self.ascii)
        try debug.finish()
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

pub type Bytes<region r> { bytes: read [u8] from r; front: usize; back: usize }
extend<region r> Bytes<region r> implements Iterator {
    type Item = u8
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
    mut fn next(): u8? {
        if self.front >= self.back { return none }
        let value = self.bytes[self.front]
        self.front += 1usize
        present(value)
    }
}
extend<region r> Bytes<region r> implements BidirectionalIterator {
    mut fn next_back(): u8? {
        if self.front >= self.back { return none }
        self.back -= 1usize
        present(self.bytes[self.back])
    }
}
extend<region r> Bytes<region r> implements super.iter.ExactSizeIterator {}
extend<region r> Bytes<region r> implements super.clone.Clone {
    fn clone(): Bytes<region r> { Bytes(self.bytes, self.front, self.back) }
}
extend<region r> Bytes<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Bytes")
        try debug.field("bytes", self.bytes)
        try debug.field("front", self.front)
        try debug.field("back", self.back)
        try debug.finish()
    }
}

pub type TextUtf16<region r> {
    chars: Chars<region r>;
    front_pending: u16;
    front_pending_ready: bool;
    back_pending: u16;
    back_pending_ready: bool
}
extend<region r> TextUtf16<region r> implements Iterator {
    type Item = u16
    mut fn next(): u16? {
        if self.front_pending_ready {
            self.front_pending_ready = false
            return present(self.front_pending)
        }
        match self.chars.next() {
            present(c) => {
                let value = c as u32
                if value < 0x10000u32 { return present(value as u16) }
                let scalar = value - 0x10000u32
                self.front_pending = (0xdc00u32 + (scalar & 0x3ffu32)) as u16
                self.front_pending_ready = true
                present((0xd800u32 + (scalar >> 10u32)) as u16)
            },
            none => {
                if self.back_pending_ready {
                    self.back_pending_ready = false
                    present(self.back_pending)
                } else {
                    none
                }
            }
        }
    }
}
extend<region r> TextUtf16<region r> implements BidirectionalIterator {
    mut fn next_back(): u16? {
        if self.back_pending_ready {
            self.back_pending_ready = false
            return present(self.back_pending)
        }
        match self.chars.next_back() {
            present(c) => {
                let value = c as u32
                if value < 0x10000u32 { return present(value as u16) }
                let scalar = value - 0x10000u32
                self.back_pending = (0xd800u32 + (scalar >> 10u32)) as u16
                self.back_pending_ready = true
                present((0xdc00u32 + (scalar & 0x3ffu32)) as u16)
            },
            none => {
                if self.front_pending_ready {
                    self.front_pending_ready = false
                    present(self.front_pending)
                } else {
                    none
                }
            }
        }
    }
}

extend Text {
    pub const fn len(): usize { self.bytes.len() }
    pub const fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn is_ascii(): bool {
        var i = 0usize
        while i < self.bytes.len() {
            if self.bytes[i] > 0x7fu8 { return false }
            i += 1usize
        }
        true
    }
    pub const fn as_bytes(): read [u8] from self { read self.bytes }
    pub const fn is_char_boundary(index: usize): bool {
        if index == 0usize || index == self.bytes.len() { return true }
        if index > self.bytes.len() { return false }
        (self.bytes[index] & 0xc0u8) != 0x80u8
    }
    pub fn floor_char_boundary(index: usize): usize {
        var boundary = if index > self.len() { self.len() } else { index }
        while !self.is_char_boundary(boundary) { boundary -= 1usize }
        boundary
    }
    pub fn ceil_char_boundary(index: usize): usize {
        var boundary = if index > self.len() { self.len() } else { index }
        while !self.is_char_boundary(boundary) { boundary += 1usize }
        boundary
    }
    pub const fn get(start: usize, end: usize): (read Text from self)? {
        if start > end || !self.is_char_boundary(start) || !self.is_char_boundary(end) {
            return none
        }
        match super.slice.subslice(read self.bytes, start, end) {
            present(part) => present(unsafe { from_utf8_unchecked(part) }),
            none => none
        }
    }
    pub mut fn get_mut(start: usize, end: usize): (mut Text from self)? {
        if start > end || end > self.len() ||
            !self.is_char_boundary(start) || !self.is_char_boundary(end) {
            return none
        }
        let (_, tail) = match take self.bytes.split_at_mut_checked(start) {
            present(parts) => parts,
            none => { return none }
        }
        let (middle, _) = match take tail.split_at_mut_checked(end - start) {
            present(parts) => parts,
            none => { return none }
        }
        match take from_utf8_mut(middle) {
            success(value) => present(value),
            failure(_) => none
        }
    }
    // Safety: the range is in bounds and both endpoints are UTF-8 boundaries.
    pub unsafe fn get_unchecked(
        start: usize,
        end: usize
    ): read Text from self {
        unsafe {
            from_utf8_unchecked(
                super.slice.subslice_unchecked(read self.bytes, start, end)
            )
        }
    }
    // Safety: the range is in bounds and both endpoints are UTF-8 boundaries.
    pub mut unsafe fn get_unchecked_mut(
        start: usize,
        end: usize
    ): mut Text from self {
        match take self.get_mut(start, end) {
            present(value) => value,
            none => { super.panic.panic("unchecked text range precondition failed") }
        }
    }
    pub fn starts_with<P: Pattern>(take pattern: P): bool {
        var matcher = pattern
        match matcher.match_front(read self) { present(_) => true, none => false }
    }
    pub fn strip_prefix<P: Pattern>(take pattern: P): (read Text from self)? {
        var matcher = pattern
        match matcher.match_front(read self) {
            present(length) => self.get(length, self.len()),
            none => none
        }
    }
    pub fn strip_circumfix<P: Pattern, S: Pattern>(
        take prefix: P,
        take suffix: S
    ): (read Text from self)? {
        var front = prefix
        var back = suffix
        let start = match front.match_front(read self) {
            present(length) => length,
            none => { return none }
        }
        let end = match back.match_back(read self) {
            present(length) => length,
            none => { return none }
        }
        if start > self.len() || end > self.len() - start ||
            !self.is_char_boundary(start) || !self.is_char_boundary(self.len() - end) {
            return none
        }
        self.get(start, self.len() - end)
    }
    pub fn trim_start_matches<P: Pattern>(take pattern: P): read Text from self {
        var matcher = pattern
        trim_pattern_start(read self, mut matcher)
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
    pub fn find<P: Pattern>(take pattern: P): usize? {
        var matcher = pattern
        var start = 0usize
        while true {
            let remaining = match self.get(start, self.len()) {
                present(part) => part,
                none => { super.panic.panic("text search boundary invariant failed") }
            }
            match matcher.match_front(remaining) {
                present(_) => { return present(start) },
                none => {}
            }
            if start == self.len() { break }
            start += scalar_width(self.bytes, start)
        }
        none
    }
    // Byte offset of the last occurrence of `pattern`; the empty pattern is at the end.
    pub fn rfind<P: Pattern>(take pattern: P): usize? {
        var matcher = pattern
        var end = self.len()
        while true {
            let remaining = match self.get(0usize, end) {
                present(part) => part,
                none => { super.panic.panic("text search boundary invariant failed") }
            }
            match matcher.match_back(remaining) {
                present(length) => {
                    if length > end || !self.is_char_boundary(end - length) {
                        super.panic.panic("invalid text pattern boundary")
                    }
                    return present(end - length)
                },
                none => {}
            }
            if end == 0usize { break }
            end -= 1usize
            while !self.is_char_boundary(end) { end -= 1usize }
        }
        none
    }
    pub fn contains<P: Pattern>(take pattern: P): bool {
        match self.find(pattern) { present(_) => true, none => false }
    }
    pub fn matches<P: Pattern>(take pattern: P): Matches<region self, P> {
        Matches(read self, pattern, 0usize, self.len(), false)
    }
    pub fn rmatches<P: Pattern>(take pattern: P): RMatches<region self, P> {
        RMatches(self.matches(pattern))
    }
    pub fn match_indices<P: Pattern>(take pattern: P): MatchIndices<region self, P> {
        MatchIndices(self.matches(pattern))
    }
    pub fn rmatch_indices<P: Pattern>(take pattern: P): RMatchIndices<region self, P> {
        RMatchIndices(self.matches(pattern))
    }
    pub const fn eq_ignore_ascii_case(read other: Text): bool {
        if self.len() != other.len() { return false }
        var i = 0usize
        while i < self.len() {
            let left = self.bytes[i]
            let right = other.bytes[i]
            let lower_left = if left >= 0x41u8 && left <= 0x5au8 { left + 0x20u8 } else { left }
            let lower_right = if right >= 0x41u8 && right <= 0x5au8 { right + 0x20u8 } else { right }
            if lower_left != lower_right { return false }
            i += 1usize
        }
        true
    }
    pub fn ends_with<P: Pattern>(take pattern: P): bool {
        var matcher = pattern
        match matcher.match_back(read self) { present(_) => true, none => false }
    }
    pub fn strip_suffix<P: Pattern>(take pattern: P): (read Text from self)? {
        var matcher = pattern
        match matcher.match_back(read self) {
            present(length) => {
                if length > self.len() { return none }
                self.get(0usize, self.len() - length)
            },
            none => none
        }
    }
    pub fn trim_end_matches<P: Pattern>(take pattern: P): read Text from self {
        var matcher = pattern
        trim_pattern_end(read self, mut matcher, 0usize)
    }
    pub fn trim_matches<P: DoubleEndedPattern>(take pattern: P): read Text from self {
        var matcher = pattern
        let remaining = trim_pattern_start(read self, mut matcher)
        // The first rejected scalar has already been tested by this matcher.
        let keep = if remaining.is_empty() { 0usize } else { scalar_width(remaining.bytes, 0usize) }
        trim_pattern_end(remaining, mut matcher, keep)
    }
    pub fn trim_start(): read Text from self {
        var i = 0usize
        while i < self.bytes.len() {
            let width = scalar_width(self.bytes, i)
            if !scalar_at(self.bytes, i, width).is_whitespace() { break }
            i += width
        }
        match self.get(i, self.bytes.len()) { present(part) => part, none => read self }
    }
    pub fn trim_end(): read Text from self {
        var end = self.bytes.len()
        while end > 0usize {
            var start = end - 1usize
            while start > 0usize && !self.is_char_boundary(start) {
                start -= 1usize
            }
            let width = end - start
            if !scalar_at(self.bytes, start, width).is_whitespace() { break }
            end = start
        }
        match self.get(0usize, end) { present(part) => part, none => read self }
    }
    pub fn trim(): read Text from self {
        var i = 0usize
        while i < self.bytes.len() {
            let width = scalar_width(self.bytes, i)
            if !scalar_at(self.bytes, i, width).is_whitespace() { break }
            i += width
        }
        var end = self.bytes.len()
        while end > i {
            var start = end - 1usize
            while start > i && !self.is_char_boundary(start) {
                start -= 1usize
            }
            let width = end - start
            if !scalar_at(self.bytes, start, width).is_whitespace() { break }
            end = start
        }
        match self.get(i, end) { present(part) => part, none => read self }
    }
    pub mut fn make_ascii_lowercase(): Unit { self.bytes.make_ascii_lowercase() }
    pub mut fn make_ascii_uppercase(): Unit { self.bytes.make_ascii_uppercase() }
    pub const fn trim_ascii_start(): read Text from self {
        var start = 0usize
        while start < self.bytes.len() && is_ascii_whitespace(self.bytes[start]) {
            start += 1usize
        }
        match self.get(start, self.bytes.len()) { present(part) => part, none => read self }
    }
    pub const fn trim_ascii_end(): read Text from self {
        var end = self.bytes.len()
        while end > 0usize && is_ascii_whitespace(self.bytes[end - 1usize]) {
            end -= 1usize
        }
        match self.get(0usize, end) { present(part) => part, none => read self }
    }
    pub const fn trim_ascii(): read Text from self {
        var start = 0usize
        while start < self.bytes.len() && is_ascii_whitespace(self.bytes[start]) {
            start += 1usize
        }
        var end = self.bytes.len()
        while end > start && is_ascii_whitespace(self.bytes[end - 1usize]) {
            end -= 1usize
        }
        match self.get(start, end) { present(part) => part, none => read self }
    }
    // Splits at the first `separator` into the text before and after it.
    pub fn split_once(read separator: Text): (read Text from self, read Text from self)? {
        match self.find(read separator) {
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
    // Splits at byte `mid`; panics unless `mid` is a scalar boundary within the text.
    pub fn split_at(mid: usize): (read Text from self, read Text from self) {
        match self.split_at_checked(mid) {
            present(parts) => parts,
            none => { super.panic.panic("failed to slice string") }
        }
    }
    pub const fn split_at_checked(mid: usize): (read Text from self, read Text from self)? {
        match self.get(0usize, mid) {
            present(head) => match self.get(mid, self.len()) {
                present(tail) => present((head, tail)),
                none => none
            },
            none => none
        }
    }
    pub mut const fn split_at_mut(mid: usize): (mut Text from self, mut Text from self) {
        match take self.split_at_mut_checked(mid) {
            present(parts) => parts,
            none => { super.panic.panic("failed to slice string") }
        }
    }
    pub mut const fn split_at_mut_checked(
        mid: usize
    ): (mut Text from self, mut Text from self)? {
        if mid > self.len() || !self.is_char_boundary(mid) { return none }
        let parts = match take self.bytes.split_at_mut_checked(mid) {
            present(value) => value,
            none => { return none }
        }
        let first = match take from_utf8_mut(parts.0) {
            success(value) => value,
            failure(_) => { return none }
        }
        let second = match take from_utf8_mut(parts.1) {
            success(value) => value,
            failure(_) => { return none }
        }
        present((first, second))
    }
    pub fn substr_range(read substring: Text): super.iter.Range<usize>? {
        let base = super.slice.data(self.as_bytes()).addr()
        let address = super.slice.data(substring.as_bytes()).addr()
        if address < base { return none }
        let start = address - base
        if start > self.len() || substring.len() > self.len() - start { return none }
        present(super.iter.Range(start, start + substring.len()))
    }
    pub fn rsplit_once(read separator: Text): (read Text from self, read Text from self)? {
        match self.rfind(read separator) {
            present(at) => {
                let end = at + separator.len()
                match self.get(0usize, at) {
                    present(head) => match self.get(end, self.len()) {
                        present(tail) => present((head, tail)),
                        none => none
                    },
                    none => none
                }
            },
            none => none
        }
    }
    pub fn split<P: Pattern>(take separator: P): Split<region self, P> {
        Split(read self, separator, false, true, true)
    }
    pub fn rsplit<P: Pattern>(take separator: P): RSplit<region self, P> {
        RSplit(self.split(separator))
    }
    pub fn splitn(count: usize, read separator: Text from self): SplitN<region self> {
        SplitN(self.split(read separator), count)
    }
    pub fn rsplitn(count: usize, read separator: Text from self): RSplitN<region self> {
        RSplitN(self.split(read separator), count)
    }
    pub fn split_terminator(read separator: Text from self): SplitTerminator<region self> {
        SplitTerminator(self.split(read separator))
    }
    pub fn rsplit_terminator(read separator: Text from self): RSplitTerminator<region self> {
        RSplitTerminator(self.split(read separator), true)
    }
    pub fn split_inclusive(read separator: Text from self): SplitInclusive<region self> {
        SplitInclusive(read self, read separator, false, true)
    }
    pub fn split_whitespace(): SplitWhitespace<region self> {
        SplitWhitespace(read self, false)
    }
    pub fn split_ascii_whitespace(): SplitWhitespace<region self> {
        SplitWhitespace(read self, true)
    }
    pub fn lines(): Lines<region self> { Lines(read self, "\n") }
    pub fn chars(): Chars<region self> {
        Chars(read self.bytes, 0usize, self.bytes.len())
    }
    pub fn char_indices(): CharIndices<region self> {
        CharIndices(read self.bytes, 0usize, self.bytes.len())
    }
    pub fn encode_utf16(): TextUtf16<region self> {
        TextUtf16(self.chars(), 0u16, false, 0u16, false)
    }
    pub fn escape_debug(): TextEscape<region self> {
        TextEscape(self.chars(), '\0'.escape_debug(), false, false, true, true)
    }
    pub fn escape_default(): TextEscape<region self> {
        TextEscape(self.chars(), '\0'.escape_default(), false, false, false, true)
    }
    pub fn escape_unicode(): TextEscape<region self> {
        TextEscape(self.chars(), '\0'.escape_unicode(), false, true, false, true)
    }
    pub fn lowercase_chars(): LowercaseChars<region self> {
        LowercaseChars(read self, self.char_indices(), '\0'.to_lowercase(), false, false)
    }
    pub fn uppercase_chars(): UppercaseChars<region self> {
        UppercaseChars(self.char_indices(), '\0'.to_uppercase(), false)
    }
    pub fn bytes(): Bytes<region self> { Bytes(read self.bytes, 0usize, self.bytes.len()) }
}

extend<region r, region s> (read Text from r)? implements PartialEq<(read Text from s)?> {
    fn eq(read other: (read Text from s)?): bool {
        match self {
            present(left) => match other { present(right) => left == right, none => false },
            none => match other { present(_) => false, none => true }
        }
    }
}
extend Text implements PartialEq {
    fn eq(read other: Text): bool {
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
    fn index_range(start: usize, end: RangeEnd): read Text from self {
        let stop = match end {
            RangeEnd.Unbounded => self.bytes.len(),
            RangeEnd.Exclusive(value) => value,
            RangeEnd.Inclusive(value) => {
                if value >= self.bytes.len() {
                    super.panic.panic("text slice is out of bounds or not on a character boundary")
                }
                value + 1usize
            }
        }
        match self.get(start, stop) {
            present(part) => part,
            none => super.panic.panic("text slice is out of bounds or not on a character boundary")
        }
    }
}

extend Text implements super.ops.IndexRangeMut {
    type Output = Text
    mut fn index_range_mut(start: usize, end: RangeEnd): mut Text from self {
        let length = Text.(super.ops.IndexRange).index_range(read self, start, end).len()
        self.get_mut(start, start + length).unwrap()
    }
}

extend Text implements Eq {}
extend Text implements PartialOrd {
    fn partial_cmp(read other: Text): Ordering? { present(self.cmp(other)) }
}
// UTF-8 byte order equals scalar value order.
extend Text implements Ord {
    fn cmp(read other: Text): Ordering {
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

extend Text implements AsRef<[u8]> {
    fn as_ref(): read [u8] from self { self.as_bytes() }
}
