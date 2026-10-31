import super.cmp.Eq
import super.cmp.Ord
import super.cmp.Ordering
import super.cmp.PartialEq
import super.cmp.PartialOrd
import super.char
import super.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, Reversed}
import super.clone.Clone
import super.fmt

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

pub fn from_utf8_mut(bytes: mut [u8]): (mut Text from bytes)? {
    var i = 0usize
    while i < bytes.len() {
        let width = scalar_width(read bytes, i)
        if width == 0usize { return none }
        i += width
    }
    present(unsafe { from_utf8_unchecked_mut(mut bytes) })
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

fn has_cased_after(text: read Text, byte_index: usize): bool {
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

fn is_ascii_whitespace(byte: u8): bool {
    (byte >= 0x09u8 && byte <= 0x0du8) || byte == 0x20u8
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

// Read-only byte search of a borrowed `needle`. A well-formed needle can only
// match at scalar boundaries; the empty needle matches at 0 (the end for `text_rfind`).
fn text_find(text: read Text, needle: read Text): usize? {
    let n = needle.bytes.len()
    if n > text.bytes.len() { return none }
    var start = 0usize
    while start + n <= text.bytes.len() {
        var k = 0usize
        while k < n && text.bytes[start + k] == needle.bytes[k] { k += 1usize }
        if k == n { return present(start) }
        start += 1usize
    }
    none
}

fn text_rfind(text: read Text, needle: read Text): usize? {
    let n = needle.bytes.len()
    if n > text.bytes.len() { return none }
    var start = text.bytes.len() - n
    while true {
        var k = 0usize
        while k < n && text.bytes[start + k] == needle.bytes[k] { k += 1usize }
        if k == n { return present(start) }
        if start == 0usize { break }
        start -= 1usize
    }
    none
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
        match text_rfind(self.rest, self.separator) {
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
            if self.rest.ends_with(self.separator) {
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

fn find_match(text: read Text, pattern: read Text, start: usize, end: usize, reverse: bool): (usize, usize)? {
    let remaining = match text.get(start, end) {
        present(part) => part,
        none => { return none }
    }
    let found = if reverse { text_rfind(remaining, pattern) } else { text_find(remaining, pattern) }
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

fn text_whitespace(text: read Text, index: usize, width: usize, ascii: bool): bool {
    if ascii {
        width == 1usize && is_ascii_whitespace(text.bytes[index])
    } else {
        scalar_at(text.bytes, index, width).is_whitespace()
    }
}

pub type SplitWhitespace<region r> {
    text: read Text from r;
    front: usize;
    back: usize;
    ascii: bool
}
extend<region r> SplitWhitespace<region r> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        var start = self.front
        while start < self.back {
            let width = scalar_width(self.text.bytes, start)
            if !text_whitespace(self.text, start, width, self.ascii) { break }
            start += width
        }
        if start >= self.back {
            self.front = self.back
            return none
        }
        var end = start
        while end < self.back {
            let width = scalar_width(self.text.bytes, end)
            if text_whitespace(self.text, end, width, self.ascii) { break }
            end += width
        }
        let item = match self.text.get(start, end) {
            present(value) => value,
            none => { super.panic.panic("split boundary invariant failed") }
        }
        self.front = end
        present(item)
    }
}
extend<region r> SplitWhitespace<region r> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? {
        var end = self.back
        while end > self.front {
            var start = end - 1usize
            while start > self.front && (self.text.bytes[start] & 0xc0u8) == 0x80u8 {
                start -= 1usize
            }
            let width = end - start
            if !text_whitespace(self.text, start, width, self.ascii) { break }
            end = start
        }
        if end <= self.front {
            self.back = self.front
            return none
        }
        var start = end
        while start > self.front {
            var previous = start - 1usize
            while previous > self.front && (self.text.bytes[previous] & 0xc0u8) == 0x80u8 {
                previous -= 1usize
            }
            let width = start - previous
            if text_whitespace(self.text, previous, width, self.ascii) { break }
            start = previous
        }
        let item = match self.text.get(start, end) {
            present(value) => value,
            none => { super.panic.panic("split boundary invariant failed") }
        }
        self.back = start
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
    front_extra: u16;
    front_ready: bool;
    back_extra: u16;
    back_ready: bool
}
extend<region r> TextUtf16<region r> implements Iterator {
    type Item = u16
    mut fn next(): u16? {
        if self.front_ready {
            self.front_ready = false
            return present(self.front_extra)
        }
        match self.chars.next() {
            present(c) => {
                let value = c as u32
                if value < 0x10000u32 { return present(value as u16) }
                let scalar = value - 0x10000u32
                self.front_extra = (0xdc00u32 + (scalar & 0x3ffu32)) as u16
                self.front_ready = true
                present((0xd800u32 + (scalar >> 10u32)) as u16)
            },
            none => {
                if self.back_ready {
                    self.back_ready = false
                    present(self.back_extra)
                } else {
                    none
                }
            }
        }
    }
}
extend<region r> TextUtf16<region r> implements BidirectionalIterator {
    mut fn next_back(): u16? {
        if self.back_ready {
            self.back_ready = false
            return present(self.back_extra)
        }
        match self.chars.next_back() {
            present(c) => {
                let value = c as u32
                if value < 0x10000u32 { return present(value as u16) }
                let scalar = value - 0x10000u32
                self.back_extra = (0xd800u32 + (scalar >> 10u32)) as u16
                self.back_ready = true
                present((0xdc00u32 + (scalar & 0x3ffu32)) as u16)
            },
            none => {
                if self.front_ready {
                    self.front_ready = false
                    present(self.front_extra)
                } else {
                    none
                }
            }
        }
    }
}

// Prefix/suffix matching for text, one scalar, or a mutable char predicate.
pub interface TextPattern {
    mut fn matched_prefix(text: read Text): usize?;
    mut fn matched_suffix(text: read Text): usize?;
    mut fn find_in(text: read Text): usize? {
        var start = 0usize
        while start <= text.len() {
            let suffix = match text.get(start, text.len()) {
                present(value) => value,
                none => { return none }
            }
            match self.matched_prefix(suffix) {
                present(_) => { return present(start) },
                none => {}
            }
            if start == text.len() { break }
            start += scalar_width(text.bytes, start)
        }
        none
    }
    mut fn rfind_in(text: read Text): usize? {
        var end = text.len()
        while true {
            let prefix = match text.get(0usize, end) {
                present(value) => value,
                none => { return none }
            }
            match self.matched_suffix(prefix) {
                present(width) => { return present(end - width) },
                none => {}
            }
            if end == 0usize { break }
            end -= 1usize
            while end > 0usize && !text.is_char_boundary(end) { end -= 1usize }
        }
        none
    }
}

// Borrowed sub-view; the callers' offsets are scalar boundaries by construction.
fn cut(text: read Text, start: usize, end: usize): read Text from text {
    match text.get(start, end) {
        present(part) => part,
        none => { super.panic.panic("split boundary invariant failed") }
    }
}

// First match of a stored pattern in `text[start..end]` as (offset, width).
fn pattern_find<P: TextPattern>(text: read Text, start: usize, end: usize, pattern: mut P): (usize, usize)? {
    var at = start
    while at < end {
        let window = match text.get(at, end) {
            present(value) => value,
            none => { return none }
        }
        match mut pattern.matched_prefix(window) {
            present(width) => { return present((at, width)) },
            none => {}
        }
        at += scalar_width(text.bytes, at)
    }
    none
}

// Last match of a stored pattern in `text[start..end]` as (offset, width).
fn pattern_rfind<P: TextPattern>(text: read Text, start: usize, end: usize, pattern: mut P): (usize, usize)? {
    var stop = end
    while stop > start {
        let window = match text.get(start, stop) {
            present(value) => value,
            none => { return none }
        }
        match mut pattern.matched_suffix(window) {
            present(width) => { return present((stop - width, width)) },
            none => {}
        }
        stop -= 1usize
        while stop > start && !text.is_char_boundary(stop) { stop -= 1usize }
    }
    none
}

// Pieces between scalars accepted by an owned `char` or `char` predicate.
pub type SplitBy<region r, P> { rest: read Text from r; pattern: P; done: bool }
extend<region r, P: TextPattern> SplitBy<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        match pattern_find(self.rest, 0usize, self.rest.len(), mut self.pattern) {
            present(found) => {
                let head = cut(self.rest, 0usize, found.0)
                self.rest = cut(self.rest, found.0 + found.1, self.rest.len())
                present(head)
            },
            none => {
                self.done = true
                present(self.rest)
            }
        }
    }
}
extend<region r, P: TextPattern> SplitBy<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? {
        if self.done { return none }
        match pattern_rfind(self.rest, 0usize, self.rest.len(), mut self.pattern) {
            present(found) => {
                let tail = cut(self.rest, found.0 + found.1, self.rest.len())
                self.rest = cut(self.rest, 0usize, found.0)
                present(tail)
            },
            none => {
                self.done = true
                present(self.rest)
            }
        }
    }
}

pub type SplitNBy<region r, P> { rest: read Text from r; pattern: P; remaining: usize }
extend<region r, P: TextPattern> SplitNBy<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.remaining == 0usize {
            let result = self.rest
            self.rest = cut(self.rest, self.rest.len(), self.rest.len())
            return present(result)
        }
        match pattern_find(self.rest, 0usize, self.rest.len(), mut self.pattern) {
            present(found) => {
                let head = cut(self.rest, 0usize, found.0)
                self.rest = cut(self.rest, found.0 + found.1, self.rest.len())
                present(head)
            },
            none => {
                let result = self.rest
                self.remaining = 0usize
                self.rest = cut(self.rest, self.rest.len(), self.rest.len())
                present(result)
            }
        }
    }
}

pub type RSplitNBy<region r, P> { rest: read Text from r; pattern: P; remaining: usize }
extend<region r, P: TextPattern> RSplitNBy<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.remaining == 0usize {
            let result = self.rest
            self.rest = cut(self.rest, self.rest.len(), self.rest.len())
            return present(result)
        }
        match pattern_rfind(self.rest, 0usize, self.rest.len(), mut self.pattern) {
            present(found) => {
                let tail = cut(self.rest, found.0 + found.1, self.rest.len())
                self.rest = cut(self.rest, 0usize, found.0)
                present(tail)
            },
            none => {
                let result = self.rest
                self.remaining = 0usize
                self.rest = cut(self.rest, self.rest.len(), self.rest.len())
                present(result)
            }
        }
    }
}

// Like `SplitBy`, but a final empty piece after a trailing match is dropped.
pub type SplitTerminatorBy<region r, P> { rest: read Text from r; pattern: P; done: bool }
extend<region r, P: TextPattern> SplitTerminatorBy<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        match pattern_find(self.rest, 0usize, self.rest.len(), mut self.pattern) {
            present(found) => {
                let head = cut(self.rest, 0usize, found.0)
                self.rest = cut(self.rest, found.0 + found.1, self.rest.len())
                if self.rest.is_empty() { self.done = true }
                present(head)
            },
            none => {
                self.done = true
                if self.rest.is_empty() { none } else { present(self.rest) }
            }
        }
    }
}

pub type RSplitTerminatorBy<region r, P> {
    rest: read Text from r;
    pattern: P;
    skip_trailing: bool;
    done: bool
}
extend<region r, P: TextPattern> RSplitTerminatorBy<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        if self.skip_trailing {
            self.skip_trailing = false
            if self.rest.is_empty() {
                self.done = true
                return none
            }
            match pattern_rfind(self.rest, 0usize, self.rest.len(), mut self.pattern) {
                present(found) => {
                    if found.0 + found.1 == self.rest.len() {
                        self.rest = cut(self.rest, 0usize, found.0)
                    }
                },
                none => {}
            }
        }
        match pattern_rfind(self.rest, 0usize, self.rest.len(), mut self.pattern) {
            present(found) => {
                let tail = cut(self.rest, found.0 + found.1, self.rest.len())
                self.rest = cut(self.rest, 0usize, found.0)
                present(tail)
            },
            none => {
                self.done = true
                present(self.rest)
            }
        }
    }
}

// Pieces end with their matching scalar; a trailing match adds no empty piece.
pub type SplitInclusiveBy<region r, P> { rest: read Text from r; pattern: P; done: bool }
extend<region r, P: TextPattern> SplitInclusiveBy<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        if self.done { return none }
        match pattern_find(self.rest, 0usize, self.rest.len(), mut self.pattern) {
            present(found) => {
                let end = found.0 + found.1
                let item = cut(self.rest, 0usize, end)
                self.rest = cut(self.rest, end, self.rest.len())
                if self.rest.is_empty() { self.done = true }
                present(item)
            },
            none => {
                self.done = true
                if self.rest.is_empty() { none } else { present(self.rest) }
            }
        }
    }
}

pub type MatchesBy<region r, P> {
    text: read Text from r;
    pattern: P;
    front: usize;
    back: usize
}
extend<region r, P: TextPattern> MatchesBy<region r, P> implements Iterator {
    type Item = read Text from r
    mut fn next(): (read Text from r)? {
        match pattern_find(self.text, self.front, self.back, mut self.pattern) {
            present(found) => {
                self.front = found.0 + found.1
                present(cut(self.text, found.0, found.0 + found.1))
            },
            none => {
                self.front = self.back
                none
            }
        }
    }
}
extend<region r, P: TextPattern> MatchesBy<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (read Text from r)? {
        match pattern_rfind(self.text, self.front, self.back, mut self.pattern) {
            present(found) => {
                self.back = found.0
                present(cut(self.text, found.0, found.0 + found.1))
            },
            none => {
                self.back = self.front
                none
            }
        }
    }
}

pub type MatchIndicesBy<region r, P> {
    text: read Text from r;
    pattern: P;
    front: usize;
    back: usize
}
extend<region r, P: TextPattern> MatchIndicesBy<region r, P> implements Iterator {
    type Item = (usize, read Text from r)
    mut fn next(): (usize, read Text from r)? {
        match pattern_find(self.text, self.front, self.back, mut self.pattern) {
            present(found) => {
                self.front = found.0 + found.1
                present((found.0, cut(self.text, found.0, found.0 + found.1)))
            },
            none => {
                self.front = self.back
                none
            }
        }
    }
}
extend<region r, P: TextPattern> MatchIndicesBy<region r, P> implements BidirectionalIterator {
    mut fn next_back(): (usize, read Text from r)? {
        match pattern_rfind(self.text, self.front, self.back, mut self.pattern) {
            present(found) => {
                self.back = found.0
                present((found.0, cut(self.text, found.0, found.0 + found.1)))
            },
            none => {
                self.back = self.front
                none
            }
        }
    }
}

extend Text {
    // Safety: `start <= end <= len` and both are scalar boundaries.
    pub unsafe fn get_unchecked(start: usize, end: usize): read Text from self {
        unsafe { from_utf8_unchecked(super.slice.subslice_unchecked(read self.bytes, start, end)) }
    }
    // Safety: as `get_unchecked`; the bytes stay well-formed while the view is live.
    pub mut unsafe fn get_unchecked_mut(start: usize, end: usize): mut Text from self {
        let (_, rest) = self.bytes.split_at_mut(start)
        let (part, _) = rest.split_at_mut(end - start)
        unsafe { from_utf8_unchecked_mut(part) }
    }
    pub fn split_by<P: TextPattern>(pattern: take P): SplitBy<region self, P> {
        SplitBy(read self, pattern, false)
    }
    pub fn rsplit_by<P: TextPattern>(pattern: take P): Reversed<SplitBy<region self, P>> {
        self.split_by(pattern).rev()
    }
    pub fn splitn_by<P: TextPattern>(count: usize, pattern: take P): SplitNBy<region self, P> {
        SplitNBy(read self, pattern, count)
    }
    pub fn rsplitn_by<P: TextPattern>(count: usize, pattern: take P): RSplitNBy<region self, P> {
        RSplitNBy(read self, pattern, count)
    }
    pub fn split_terminator_by<P: TextPattern>(pattern: take P): SplitTerminatorBy<region self, P> {
        SplitTerminatorBy(read self, pattern, false)
    }
    pub fn rsplit_terminator_by<P: TextPattern>(pattern: take P): RSplitTerminatorBy<region self, P> {
        RSplitTerminatorBy(read self, pattern, true, false)
    }
    pub fn split_inclusive_by<P: TextPattern>(pattern: take P): SplitInclusiveBy<region self, P> {
        SplitInclusiveBy(read self, pattern, false)
    }
    pub fn matches_by<P: TextPattern>(pattern: take P): MatchesBy<region self, P> {
        MatchesBy(read self, pattern, 0usize, self.len())
    }
    pub fn rmatches_by<P: TextPattern>(pattern: take P): Reversed<MatchesBy<region self, P>> {
        self.matches_by(pattern).rev()
    }
    pub fn match_indices_by<P: TextPattern>(pattern: take P): MatchIndicesBy<region self, P> {
        MatchIndicesBy(read self, pattern, 0usize, self.len())
    }
    pub fn rmatch_indices_by<P: TextPattern>(pattern: take P): Reversed<MatchIndicesBy<region self, P>> {
        self.match_indices_by(pattern).rev()
    }
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
    pub fn as_ptr(): ptr<read u8> { self.bytes.as_ptr() }
    pub mut fn as_mut_ptr(): ptr<mut u8> { self.bytes.as_mut_ptr() }
    // Safety: the bytes must remain valid UTF-8 while they are observed as Text.
    pub mut unsafe fn as_bytes_mut(): mut [u8] from self { mut self.bytes }
    pub mut fn make_ascii_lowercase(): Unit {
        var index = 0usize
        while index < self.bytes.len() {
            let byte = self.bytes[index]
            if byte >= 0x41u8 && byte <= 0x5au8 { self.bytes[index] = byte + 0x20u8 }
            index += 1usize
        }
    }
    pub mut fn make_ascii_uppercase(): Unit {
        var index = 0usize
        while index < self.bytes.len() {
            let byte = self.bytes[index]
            if byte >= 0x61u8 && byte <= 0x7au8 { self.bytes[index] = byte - 0x20u8 }
            index += 1usize
        }
    }
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
    pub mut fn get_mut(start: usize, end: usize): (mut Text from self)? {
        if start > end || !self.is_char_boundary(start) || !self.is_char_boundary(end) {
            return none
        }
        let (_, rest) = self.bytes.split_at_mut(start)
        let (part, _) = rest.split_at_mut(end - start)
        // Valid UTF-8 remains valid when cut only at scalar boundaries.
        present(unsafe { from_utf8_unchecked_mut(part) })
    }
    pub fn split_at(mid: usize): (read Text from self, read Text from self) {
        if mid > self.len() || !self.is_char_boundary(mid) {
            super.panic.panic("split_at index is not a character boundary")
        }
        let left = match self.get(0usize, mid) {
            present(value) => value,
            none => super.panic.panic("validated text boundary became unavailable")
        }
        let right = match self.get(mid, self.len()) {
            present(value) => value,
            none => super.panic.panic("validated text boundary became unavailable")
        }
        (left, right)
    }
    pub fn split_at_checked(mid: usize): (read Text from self, read Text from self)? {
        if mid > self.len() || !self.is_char_boundary(mid) { return none }
        let left = match self.get(0usize, mid) { present(value) => value, none => { return none } }
        let right = match self.get(mid, self.len()) { present(value) => value, none => { return none } }
        present((left, right))
    }
    pub mut fn split_at_mut(mid: usize): (mut Text from self, mut Text from self) {
        if mid > self.len() || !self.is_char_boundary(mid) {
            super.panic.panic("split_at_mut index is not a character boundary")
        }
        let (left, right) = self.bytes.split_at_mut(mid)
        // Both halves end at the checked scalar boundary.
        (unsafe { from_utf8_unchecked_mut(left) }, unsafe { from_utf8_unchecked_mut(right) })
    }
    pub mut fn split_at_mut_checked(mid: usize): (mut Text from self, mut Text from self)? {
        if mid > self.len() || !self.is_char_boundary(mid) { return none }
        let (left, right) = self.bytes.split_at_mut(mid)
        // Both halves end at the checked scalar boundary.
        present((unsafe { from_utf8_unchecked_mut(left) }, unsafe { from_utf8_unchecked_mut(right) }))
    }
    pub fn starts_with<P: TextPattern + unsized>(pattern: mut P): bool {
        match mut pattern.matched_prefix(read self) { present(_) => true, none => false }
    }
    pub fn strip_prefix<P: TextPattern + unsized>(pattern: mut P): (read Text from self)? {
        let width = match mut pattern.matched_prefix(read self) {
            present(value) => value,
            none => { return none }
        }
        match self.get(width, self.len()) {
            present(suffix) => present(suffix),
            none => none
        }
    }
    pub fn trim_start_matches<P: TextPattern + unsized>(pattern: mut P): read Text from self {
        var start = 0usize
        while start < self.len() {
            let remaining = match self.get(start, self.len()) {
                present(part) => part,
                none => { break }
            }
            match mut pattern.matched_prefix(remaining) {
                present(n) => {
                    if n == 0usize { break }
                    start += n
                },
                none => { break }
            }
        }
        match self.get(start, self.len()) { present(part) => part, none => read self }
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
    pub fn find<P: TextPattern + unsized>(pattern: mut P): usize? {
        mut pattern.find_in(read self)
    }
    pub fn rfind<P: TextPattern + unsized>(pattern: mut P): usize? {
        mut pattern.rfind_in(read self)
    }
    pub fn contains<P: TextPattern + unsized>(pattern: mut P): bool {
        match self.find(mut pattern) { present(_) => true, none => false }
    }
    pub fn matches(pattern: read Text from self): Matches<region self> {
        Matches(read self, read pattern, 0usize, self.len(), false)
    }
    pub fn rmatches(pattern: read Text from self): Reversed<Matches<region self>> {
        self.matches(pattern).rev()
    }
    pub fn match_indices(pattern: read Text from self): MatchIndices<region self> {
        MatchIndices(read self, read pattern, 0usize, self.len(), false)
    }
    pub fn rmatch_indices(pattern: read Text from self): Reversed<MatchIndices<region self>> {
        self.match_indices(pattern).rev()
    }
    pub fn eq_ignore_ascii_case(other: read Text): bool {
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
    pub fn ends_with<P: TextPattern + unsized>(pattern: mut P): bool {
        match mut pattern.matched_suffix(read self) { present(_) => true, none => false }
    }
    pub fn strip_circumfix<P: TextPattern + unsized, S: TextPattern + unsized>(
        prefix: mut P, suffix: mut S
    ): (read Text from self)? {
        let width = match mut prefix.matched_prefix(read self) {
            present(width) => width,
            none => { return none }
        }
        let rest = match self.get(width, self.len()) {
            present(part) => part,
            none => { return none }
        }
        let suffix_width = match mut suffix.matched_suffix(rest) {
            present(width) => width,
            none => { return none }
        }
        rest.get(0usize, rest.len() - suffix_width)
    }
    pub fn substr_range(part: read Text): super.iter.Range<usize>? {
        self.bytes.subslice_range(part.bytes)
    }
    pub fn strip_suffix<P: TextPattern + unsized>(pattern: mut P): (read Text from self)? {
        let width = match mut pattern.matched_suffix(read self) {
            present(value) => value,
            none => { return none }
        }
        match self.get(0usize, self.len() - width) {
            present(prefix) => present(prefix),
            none => none
        }
    }
    pub fn trim_end_matches<P: TextPattern + unsized>(pattern: mut P): read Text from self {
        var end = self.len()
        while end > 0usize {
            let remaining = match self.get(0usize, end) {
                present(part) => part,
                none => { break }
            }
            match mut pattern.matched_suffix(remaining) {
                present(n) => {
                    if n == 0usize { break }
                    end -= n
                },
                none => { break }
            }
        }
        match self.get(0usize, end) { present(part) => part, none => read self }
    }
    pub fn trim_matches<P: TextPattern + unsized>(pattern: mut P): read Text from self {
        let trimmed = self.trim_start_matches(mut pattern)
        trimmed.trim_end_matches(mut pattern)
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
    pub fn split_once(separator: read Text): (read Text from self, read Text from self)? {
        match text_find(self, separator) {
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
    pub fn rsplit_once(separator: read Text): (read Text from self, read Text from self)? {
        match text_rfind(self, separator) {
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
    pub fn split(separator: read Text from self): Split<region self> { Split(read self, read separator, false) }
    pub fn rsplit(separator: read Text from self): Reversed<Split<region self>> {
        self.split(separator).rev()
    }
    pub fn splitn(count: usize, separator: read Text from self): SplitN<region self> {
        SplitN(read self, read separator, count)
    }
    pub fn rsplitn(count: usize, separator: read Text from self): RSplitN<region self> {
        RSplitN(read self, read separator, count)
    }
    pub fn split_terminator(separator: read Text from self): SplitTerminator<region self> {
        SplitTerminator(read self, read separator, false)
    }
    pub fn rsplit_terminator(separator: read Text from self): RSplitTerminator<region self> {
        RSplitTerminator(read self, read separator, true, false)
    }
    pub fn split_inclusive(separator: read Text from self): SplitInclusive<region self> {
        SplitInclusive(read self, read separator, false)
    }
    pub fn split_whitespace(): SplitWhitespace<region self> {
        SplitWhitespace(read self, 0usize, self.len(), false)
    }
    pub fn split_ascii_whitespace(): SplitWhitespace<region self> {
        SplitWhitespace(read self, 0usize, self.len(), true)
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

extend Text implements TextPattern {
    mut fn matched_prefix(text: read Text): usize? {
        if self.is_empty() { return present(0usize) }
        if self.len() > text.len() { return none }
        var index = 0usize
        while index < self.len() {
            if self.bytes[index] != text.bytes[index] { return none }
            index += 1usize
        }
        present(self.len())
    }
    mut fn matched_suffix(text: read Text): usize? {
        if self.is_empty() { return present(0usize) }
        if self.len() > text.len() { return none }
        let offset = text.len() - self.len()
        var index = 0usize
        while index < self.len() {
            if self.bytes[index] != text.bytes[offset + index] { return none }
            index += 1usize
        }
        present(self.len())
    }
}

extend char implements TextPattern {
    mut fn matched_prefix(text: read Text): usize? {
        if text.is_empty() { return none }
        let width = scalar_width(text.bytes, 0usize)
        if scalar_at(text.bytes, 0usize, width) == self { present(width) } else { none }
    }
    mut fn matched_suffix(text: read Text): usize? {
        if text.is_empty() { return none }
        var start = text.len() - 1usize
        while start > 0usize && (text.bytes[start] & 0xc0u8) == 0x80u8 {
            start -= 1usize
        }
        let width = text.len() - start
        if scalar_at(text.bytes, start, width) == self { present(width) } else { none }
    }
}

extend<F: mut fn(char): bool> F implements TextPattern {
    mut fn matched_prefix(text: read Text): usize? {
        if text.is_empty() { return none }
        let width = scalar_width(text.bytes, 0usize)
        let value = scalar_at(text.bytes, 0usize, width)
        if self(value) { present(width) } else { none }
    }
    mut fn matched_suffix(text: read Text): usize? {
        if text.is_empty() { return none }
        var start = text.len() - 1usize
        while start > 0usize && (text.bytes[start] & 0xc0u8) == 0x80u8 {
            start -= 1usize
        }
        let width = text.len() - start
        let value = scalar_at(text.bytes, start, width)
        if self(value) { present(width) } else { none }
    }
}

copy type ByteWindow { data: ptr<read u8>; len: usize }

fn window(bytes: read [u8], start: usize, end: usize): read [u8] from bytes {
    let fat = core.ptr.from_ref(bytes)
    let raw = unsafe { core.mem.transmute<ByteWindow>(fat) }
    let part = unsafe {
        core.mem.transmute<ptr<read [u8]>>(ByteWindow(raw.data.add(start), end - start))
    }
    unsafe { read *part }
}

fn hex_digit(nibble: u8): u8 {
    if nibble < 10u8 { 48u8 + nibble } else { 87u8 + nibble }
}

fn fill_escape(byte: u8, buf: mut [u8; 4]): u8 {
    if byte == 0x09u8 { buf[0] = 0x5cu8; buf[1] = 0x74u8; return 2u8 }
    if byte == 0x0du8 { buf[0] = 0x5cu8; buf[1] = 0x72u8; return 2u8 }
    if byte == 0x0au8 { buf[0] = 0x5cu8; buf[1] = 0x6eu8; return 2u8 }
    if byte == 0x5cu8 { buf[0] = 0x5cu8; buf[1] = 0x5cu8; return 2u8 }
    if byte == 0x27u8 { buf[0] = 0x5cu8; buf[1] = 0x27u8; return 2u8 }
    if byte >= 0x20u8 && byte < 0x7fu8 { buf[0] = byte; return 1u8 }
    buf[0] = 0x5cu8
    buf[1] = 0x78u8
    buf[2] = hex_digit(byte >> 4u8)
    buf[3] = hex_digit(byte & 0x0fu8)
    4u8
}

// Escaped ASCII bytes of one `u8`. Printable bytes pass through; tab, CR, LF,
// backslash and quote are escaped, and every other byte is `\xNN`.
pub copy type ByteEscape { buf: [u8; 4]; len: u8; at: u8 }

extend ByteEscape implements Iterator {
    type Item = u8
    mut fn next(): u8? {
        if self.at >= self.len { return none }
        let byte = self.buf[(self.at as usize)]
        self.at += 1u8
        present(byte)
    }
}

extend u8 {
    pub fn escape_ascii(): ByteEscape {
        var buf = [0u8, 0u8, 0u8, 0u8]
        let len = fill_escape(self, mut buf)
        ByteEscape(buf, len, 0u8)
    }
}

pub type EscapeAscii<region r> {
    bytes: read [u8] from r
    index: usize
    pending: ByteEscape
}

extend<region r> EscapeAscii<region r> implements Iterator {
    type Item = u8
    mut fn next(): u8? {
        if self.pending.at < self.pending.len {
            let byte = self.pending.buf[(self.pending.at as usize)]
            self.pending.at += 1u8
            return present(byte)
        }
        if self.index >= self.bytes.len() { return none }
        let source = self.bytes[self.index]
        self.index += 1usize
        var buf = [0u8, 0u8, 0u8, 0u8]
        let len = fill_escape(source, mut buf)
        self.pending = ByteEscape(buf, len, 1u8)
        present(buf[0])
    }
}

// Bytes of one maximal subpart that `scalar_width` rejected at `index`.
fn invalid_span(bytes: read [u8], index: usize): usize {
    let first = bytes[index]
    let remaining = bytes.len() - index
    if first < 0xc2u8 || first > 0xf4u8 { return 1usize }
    let width = if first < 0xe0u8 { 2usize } else if first < 0xf0u8 { 3usize } else { 4usize }
    if remaining < width { return remaining }
    var low = 0x80u8
    var high = 0xbfu8
    if first == 0xe0u8 { low = 0xa0u8 }
    if first == 0xedu8 { high = 0x9fu8 }
    if first == 0xf0u8 { low = 0x90u8 }
    if first == 0xf4u8 { high = 0x8fu8 }
    if bytes[index + 1usize] < low || bytes[index + 1usize] > high { return 1usize }
    var offset = 2usize
    while offset < width {
        if (bytes[index + offset] & 0xc0u8) != 0x80u8 { return offset }
        offset += 1usize
    }
    1usize
}

pub type Utf8Chunk<region r> {
    valid_bytes: read [u8] from r
    invalid_bytes: read [u8] from r
}

extend<region r> Utf8Chunk<region r> {
    pub fn valid(): read Text from self { unsafe { from_utf8_unchecked(self.valid_bytes) } }
    pub fn invalid(): read [u8] from self { self.invalid_bytes }
}

pub type Utf8Chunks<region r> { bytes: read [u8] from r; index: usize }

extend<region r> Utf8Chunks<region r> implements Iterator {
    type Item = Utf8Chunk<region r>
    mut fn next(): Utf8Chunk<region r>? {
        if self.index >= self.bytes.len() { return none }
        let start = self.index
        var valid_end = start
        while valid_end < self.bytes.len() {
            let width = scalar_width(self.bytes, valid_end)
            if width == 0usize { break }
            valid_end += width
        }
        var invalid_end = valid_end
        if valid_end < self.bytes.len() {
            invalid_end = valid_end + invalid_span(self.bytes, valid_end)
        }
        self.index = invalid_end
        present(Utf8Chunk(
            window(self.bytes, start, valid_end),
            window(self.bytes, valid_end, invalid_end)
        ))
    }
}

extend [u8] {
    pub fn escape_ascii(): EscapeAscii<region self> {
        EscapeAscii(read self, 0usize, ByteEscape([0u8, 0u8, 0u8, 0u8], 0u8, 0u8))
    }
    pub fn utf8_chunks(): Utf8Chunks<region self> { Utf8Chunks(read self, 0usize) }
}

// Iterator copies: the cloned iterator continues independently from the same
// position over the same borrowed text.
extend<region r> Chars<region r> implements Clone {
    fn clone(): Chars<region r> { Chars(self.bytes, self.front, self.back) }
}
extend<region r> CharIndices<region r> implements Clone {
    fn clone(): CharIndices<region r> { CharIndices(self.bytes, self.front, self.back) }
}
extend<region r> Bytes<region r> implements Clone {
    fn clone(): Bytes<region r> { Bytes(self.bytes, self.front, self.back) }
}
extend<region r> Split<region r> implements Clone {
    fn clone(): Split<region r> { Split(self.rest, self.separator, self.done) }
}
extend<region r> SplitWhitespace<region r> implements Clone {
    fn clone(): SplitWhitespace<region r> {
        SplitWhitespace(self.text, self.front, self.back, self.ascii)
    }
}
extend<region r> Lines<region r> implements Clone {
    fn clone(): Lines<region r> { Lines(self.rest, self.newline) }
}

extend<region r> Bytes<region r> implements ExactSizeIterator {
    fn len(): usize { self.back - self.front }
}

// Debug shows the unconsumed input, not the iterator's private offsets.
extend<region r> Chars<region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Chars")
        try fields.field("remaining", self.as_str())
        try fields.finish()
    }
}
extend<region r> CharIndices<region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("CharIndices")
        try fields.field("remaining", self.as_str())
        try fields.finish()
    }
}
extend<region r> Bytes<region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        let remaining = match super.slice.subslice(self.bytes, self.front, self.back) {
            present(part) => part,
            none => { super.panic.panic("byte iterator boundary invariant failed") }
        }
        var fields = try f.debug_struct("Bytes")
        try fields.field("remaining", remaining)
        try fields.finish()
    }
}
extend<region r> Split<region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Split")
        try fields.field("rest", self.rest)
        try fields.field("separator", self.separator)
        try fields.field("done", self.done)
        try fields.finish()
    }
}
extend<region r> SplitWhitespace<region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("SplitWhitespace")
        try fields.field("remaining", cut(self.text, self.front, self.back))
        try fields.field("ascii", self.ascii)
        try fields.finish()
    }
}
extend<region r> Lines<region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Lines")
        try fields.field("remaining", self.rest)
        try fields.finish()
    }
}

extend Text implements super.ops.IndexRangeMut {
    type Output = Text
    mut fn index_range_mut(start: usize, end: usize): mut Text from self {
        let stop = if end == 0xffffffffffffffffusize { self.bytes.len() } else { end }
        match self.get_mut(start, stop) {
            present(part) => part,
            none => super.panic.panic("text slice is out of bounds or not on a character boundary")
        }
    }
}
