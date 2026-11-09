import super.cmp.Eq
import super.cmp.Ord
import super.cmp.Ordering
import super.cmp.PartialEq
import super.cmp.PartialOrd
import super.char
import super.iter.{Iterator, BidirectionalIterator, Reversed}

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
pub interface Pattern {
    mut fn match_front(read text: Text): usize?;
    mut fn match_back(read text: Text): usize?;
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

pub fn from_utf8(read bytes: [u8]): (read Text from bytes)? {
    var i = 0usize
    while i < bytes.len() {
        let width = scalar_width(bytes, i)
        if width == 0usize { return none }
        i += width
    }
    present(unsafe { from_utf8_unchecked(bytes) })
}

pub fn from_utf8_mut(mut bytes: [u8]): (mut Text from bytes)? {
    var i = 0usize
    while i < bytes.len() {
        let width = scalar_width(read bytes, i)
        if width == 0usize { return none }
        i += width
    }
    present(unsafe { from_utf8_unchecked_mut(mut bytes) })
}

// Safety: `bytes` is well-formed UTF-8.
pub unsafe fn from_utf8_unchecked(read bytes: [u8]): read Text from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read Text>>(fat) }
    unsafe { read *view }
}

// Safety: `bytes` is well-formed UTF-8 and stays so while the view is live.
pub unsafe fn from_utf8_unchecked_mut(mut bytes: [u8]): mut Text from bytes {
    let fat = core.ptr.from_mut(bytes)
    let view = unsafe { core.mem.transmute<ptr<mut Text>>(fat) }
    unsafe { mut *view }
}

pub type Chars<region r> { bytes: read [u8] from r; front: usize; back: usize }
extend<region r> Chars<region r> {
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

pub type CharIndices<region r> { bytes: read [u8] from r; front: usize; back: usize }
extend<region r> CharIndices<region r> {
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
fn is_ascii_whitespace(byte: u8): bool {
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
    debug: bool
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
                        else if self.debug { c.escape_debug() }
                        else { c.escape_default() }
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
extend<region r> Split<region r> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? {
        if self.done { return none }
        if self.separator.is_empty() {
            self.done = true
            return present(self.rest)
        }
        match self.rest.rfind(read *self.separator) {
            present(at) => {
                let start = at + self.separator.len()
                let tail = match self.rest.get(start, self.rest.len()) {
                    present(part) => part,
                    none => { super.panic.panic("split boundary invariant failed") }
                }
                self.rest = match self.rest.get(0usize, at) {
                    present(part) => part,
                    none => { super.panic.panic("split boundary invariant failed") }
                }
                present(tail)
            },
            none => {
                self.done = true
                present(self.rest)
            }
        }
    }
}

pub type SplitN<region r> {
    rest: read Text from r;
    separator: read Text from r;
    remaining: usize
}
extend<region r> SplitN<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.remaining == 0usize || self.separator.is_empty() {
            let result = self.rest
            self.remaining = 0usize
            self.rest = match self.rest.get(self.rest.len(), self.rest.len()) {
                present(empty) => empty,
                none => { super.panic.panic("split boundary invariant failed") }
            }
            return present(result)
        }
        match self.rest.split_once(self.separator) {
            present(parts) => {
                self.rest = parts.1
                present(parts.0)
            },
            none => {
                let result = self.rest
                self.remaining = 0usize
                self.rest = match self.rest.get(self.rest.len(), self.rest.len()) {
                    present(empty) => empty,
                    none => { super.panic.panic("split boundary invariant failed") }
                }
                present(result)
            }
        }
    }
}

pub type RSplitN<region r> {
    rest: read Text from r;
    separator: read Text from r;
    remaining: usize
}
extend<region r> RSplitN<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.remaining == 0usize || self.separator.is_empty() {
            let result = self.rest
            self.remaining = 0usize
            self.rest = match self.rest.get(self.rest.len(), self.rest.len()) {
                present(empty) => empty,
                none => { super.panic.panic("split boundary invariant failed") }
            }
            return present(result)
        }
        match self.rest.rsplit_once(self.separator) {
            present(parts) => {
                self.rest = parts.0
                present(parts.1)
            },
            none => {
                let result = self.rest
                self.remaining = 0usize
                self.rest = match self.rest.get(self.rest.len(), self.rest.len()) {
                    present(empty) => empty,
                    none => { super.panic.panic("split boundary invariant failed") }
                }
                present(result)
            }
        }
    }
}

pub type SplitTerminator<region r> {
    rest: read Text from r;
    separator: read Text from r;
    done: bool
}
extend<region r> SplitTerminator<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        if self.separator.is_empty() {
            self.done = true
            return present(self.rest)
        }
        match self.rest.split_once(self.separator) {
            present(parts) => {
                self.rest = parts.1
                if self.rest.is_empty() { self.done = true }
                present(parts.0)
            },
            none => {
                self.done = true
                present(self.rest)
            }
        }
    }
}

pub type RSplitTerminator<region r> {
    rest: read Text from r;
    separator: read Text from r;
    skip_trailing: bool;
    done: bool
}
extend<region r> RSplitTerminator<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        if self.separator.is_empty() {
            self.done = true
            return present(self.rest)
        }
        if self.skip_trailing {
            self.skip_trailing = false
            if self.rest.ends_with(read *self.separator) {
                let end = self.rest.len() - self.separator.len()
                self.rest = match self.rest.get(0usize, end) {
                    present(prefix) => prefix,
                    none => { super.panic.panic("split boundary invariant failed") }
                }
                if self.rest.is_empty() {
                    self.done = true
                    return none
                }
            }
        }
        match self.rest.rsplit_once(self.separator) {
            present(parts) => {
                self.rest = parts.0
                present(parts.1)
            },
            none => {
                self.done = true
                present(self.rest)
            }
        }
    }
}

pub type SplitInclusive<region r> {
    rest: read Text from r;
    separator: read Text from r;
    done: bool
}
extend<region r> SplitInclusive<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        if self.separator.is_empty() {
            self.done = true
            return present(self.rest)
        }
        match self.rest.split_once(self.separator) {
            present(parts) => {
                let original = self.rest
                let end = parts.0.len() + self.separator.len()
                let item = match original.get(0usize, end) {
                    present(value) => value,
                    none => { super.panic.panic("split boundary invariant failed") }
                }
                self.rest = parts.1
                if self.rest.is_empty() { self.done = true }
                present(item)
            },
            none => {
                self.done = true
                present(self.rest)
            }
        }
    }
}

fn find_match(read text: Text, read pattern: Text, start: usize, end: usize, reverse: bool): (usize, usize)? {
    let remaining = match text.get(start, end) {
        present(part) => part,
        none => { return none }
    }
    let found = if reverse { remaining.rfind(read pattern) } else { remaining.find(read pattern) }
    match found {
        present(at) => {
            let first = start + at
            present((first, first + pattern.len()))
        },
        none => none
    }
}

pub type Matches<region r> {
    text: read Text from r;
    pattern: read Text from r;
    front: usize;
    back: usize;
    done: bool
}
extend<region r> Matches<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        if self.pattern.is_empty() {
            let at = self.front
            if self.front == self.back {
                self.done = true
            } else {
                self.front += scalar_width(self.text.bytes, self.front)
            }
            return self.text.get(at, at)
        }
        match find_match(self.text, self.pattern, self.front, self.back, false) {
            present(bounds) => {
                self.front = bounds.1
                self.text.get(bounds.0, bounds.1)
            },
            none => {
                self.done = true
                none
            }
        }
    }
}
extend<region r> Matches<region r> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? {
        if self.done { return none }
        if self.pattern.is_empty() {
            let at = self.back
            if self.front == self.back {
                self.done = true
            } else {
                var previous = self.back - 1usize
                while previous > self.front && (self.text.bytes[previous] & 0xc0u8) == 0x80u8 {
                    previous -= 1usize
                }
                self.back = previous
            }
            return self.text.get(at, at)
        }
        match find_match(self.text, self.pattern, self.front, self.back, true) {
            present(bounds) => {
                self.back = bounds.0
                self.text.get(bounds.0, bounds.1)
            },
            none => {
                self.done = true
                none
            }
        }
    }
}

pub type MatchIndices<region r> {
    text: read Text from r;
    pattern: read Text from r;
    front: usize;
    back: usize;
    done: bool
}
extend<region r> MatchIndices<region r> implements Iterator {
    type Item = (usize, read Text from r)
    mut fn next(): (usize, read Text from r)? {
        if self.done { return none }
        if self.pattern.is_empty() {
            let at = self.front
            if self.front == self.back {
                self.done = true
            } else {
                self.front += scalar_width(self.text.bytes, self.front)
            }
            return match self.text.get(at, at) {
                present(empty) => present((at, empty)),
                none => none
            }
        }
        match find_match(self.text, self.pattern, self.front, self.back, false) {
            present(bounds) => match self.text.get(bounds.0, bounds.1) {
                present(item) => {
                    self.front = bounds.1
                    present((bounds.0, item))
                },
                none => none
            },
            none => {
                self.done = true
                none
            }
        }
    }
}
extend<region r> MatchIndices<region r> implements BidirectionalIterator {
    mut fn next_back(): (usize, read Text from r)? {
        if self.done { return none }
        if self.pattern.is_empty() {
            let at = self.back
            if self.front == self.back {
                self.done = true
            } else {
                var previous = self.back - 1usize
                while previous > self.front && (self.text.bytes[previous] & 0xc0u8) == 0x80u8 {
                    previous -= 1usize
                }
                self.back = previous
            }
            return match self.text.get(at, at) {
                present(empty) => present((at, empty)),
                none => none
            }
        }
        match find_match(self.text, self.pattern, self.front, self.back, true) {
            present(bounds) => match self.text.get(bounds.0, bounds.1) {
                present(item) => {
                    self.back = bounds.0
                    present((bounds.0, item))
                },
                none => none
            },
            none => {
                self.done = true
                none
            }
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
    pub fn len(): usize { self.bytes.len() }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn is_ascii(): bool {
        var i = 0usize
        while i < self.bytes.len() {
            if self.bytes[i] > 0x7fu8 { return false }
            i += 1usize
        }
        true
    }
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn is_char_boundary(index: usize): bool {
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
    pub fn get(start: usize, end: usize): (read Text from self)? {
        if start > end || !self.is_char_boundary(start) || !self.is_char_boundary(end) {
            return none
        }
        match super.slice.subslice(read self.bytes, start, end) {
            present(part) => present(unsafe { from_utf8_unchecked(part) }),
            none => none
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
    pub fn matches(read pattern: Text from self): Matches<region self> {
        Matches(read self, read pattern, 0usize, self.len(), false)
    }
    pub fn rmatches(read pattern: Text from self): Reversed<Matches<region self>> {
        self.matches(pattern).rev()
    }
    pub fn match_indices(read pattern: Text from self): MatchIndices<region self> {
        MatchIndices(read self, read pattern, 0usize, self.len(), false)
    }
    pub fn rmatch_indices(read pattern: Text from self): Reversed<MatchIndices<region self>> {
        self.match_indices(pattern).rev()
    }
    pub fn eq_ignore_ascii_case(read other: Text): bool {
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
    pub fn trim_matches<P: Pattern>(take pattern: P): read Text from self {
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
    pub fn trim_ascii_start(): read Text from self {
        var start = 0usize
        while start < self.bytes.len() && is_ascii_whitespace(self.bytes[start]) {
            start += 1usize
        }
        match self.get(start, self.bytes.len()) { present(part) => part, none => read self }
    }
    pub fn trim_ascii_end(): read Text from self {
        var end = self.bytes.len()
        while end > 0usize && is_ascii_whitespace(self.bytes[end - 1usize]) {
            end -= 1usize
        }
        match self.get(0usize, end) { present(part) => part, none => read self }
    }
    pub fn trim_ascii(): read Text from self {
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
    pub fn split_at_checked(mid: usize): (read Text from self, read Text from self)? {
        match self.get(0usize, mid) {
            present(head) => match self.get(mid, self.len()) {
                present(tail) => present((head, tail)),
                none => none
            },
            none => none
        }
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
    pub fn split(read separator: Text from self): Split<region self> { Split(read self, read separator, false) }
    pub fn rsplit(read separator: Text from self): Reversed<Split<region self>> {
        self.split(separator).rev()
    }
    pub fn splitn(count: usize, read separator: Text from self): SplitN<region self> {
        SplitN(read self, read separator, count)
    }
    pub fn rsplitn(count: usize, read separator: Text from self): RSplitN<region self> {
        RSplitN(read self, read separator, count)
    }
    pub fn split_terminator(read separator: Text from self): SplitTerminator<region self> {
        SplitTerminator(read self, read separator, false)
    }
    pub fn rsplit_terminator(read separator: Text from self): RSplitTerminator<region self> {
        RSplitTerminator(read self, read separator, true, false)
    }
    pub fn split_inclusive(read separator: Text from self): SplitInclusive<region self> {
        SplitInclusive(read self, read separator, false)
    }
    pub fn split_whitespace(): SplitWhitespace<region self> {
        SplitWhitespace(read self, false)
    }
    pub fn split_ascii_whitespace(): SplitWhitespace<region self> {
        SplitWhitespace(read self, true)
    }
    pub fn lines(): Lines<region self> { Lines(read self, "\n") }
    pub fn chars(): Chars<region self> { Chars(read self.bytes, 0usize, self.bytes.len()) }
    pub fn char_indices(): CharIndices<region self> { CharIndices(read self.bytes, 0usize, self.bytes.len()) }
    pub fn encode_utf16(): TextUtf16<region self> {
        TextUtf16(self.chars(), 0u16, false, 0u16, false)
    }
    pub fn escape_debug(): TextEscape<region self> {
        TextEscape(self.chars(), '\0'.escape_debug(), false, false, true)
    }
    pub fn escape_default(): TextEscape<region self> {
        TextEscape(self.chars(), '\0'.escape_default(), false, false, false)
    }
    pub fn escape_unicode(): TextEscape<region self> {
        TextEscape(self.chars(), '\0'.escape_unicode(), false, true, false)
    }
    pub fn lowercase_chars(): LowercaseChars<region self> {
        LowercaseChars(read self, self.char_indices(), '\0'.to_lowercase(), false, false)
    }
    pub fn uppercase_chars(): UppercaseChars<region self> {
        UppercaseChars(self.char_indices(), '\0'.to_uppercase(), false)
    }
    pub fn bytes(): Bytes<region self> { Bytes(read self.bytes, 0usize, self.bytes.len()) }
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
