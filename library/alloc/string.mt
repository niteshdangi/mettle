import package.core.iter.Iterator;
import super.alloc.{Allocator, Global, AllocError, panic_precondition};
import package.core.clone.Clone;
import package.core.default.Default;
import package.core.fmt;
import package.core.ops.{Deref, IndexRange};
import package.core.hash.{Hash, Hasher};
import package.core.borrow.KeyView;
import super.vec.{Vec, slice_ptr};
import package.core.cmp.{Ordering, PartialEq, Eq, PartialOrd, Ord};
import package.core.text.{Text, from_utf8_unchecked};

// Owned, growable UTF-8 text: a `Vec<u8>` whose bytes are always well formed.
pub type String<A: Allocator = Global> {
    v: Vec<u8, A>
}

// Invalid input handed back to the caller together with the failing offset.
pub type FromUtf8Error<A: Allocator = Global> {
    pub bytes: Vec<u8, A>
    pub valid_up_to: usize
}

pub fn new_in<A: Allocator>(a: take A): String<A> { String(super.vec.new_in<u8, A>(a)) }
pub fn new(): String { new_in(Global()) }
pub fn with_capacity(n: usize): String { String(super.vec.with_capacity<u8>(n)) }
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
pub fn from_utf8<A: Allocator>(bytes: take Vec<u8, A>): String<A> throws FromUtf8Error<A> {
    let ok = match package.core.text.from_utf8(bytes.as_slice()) {
        present(_) => true,
        none => false
    }
    if !ok {
        let n = valid_prefix(bytes.as_slice())
        throw FromUtf8Error(bytes, n)
    }
    String(bytes)
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
    pub take fn into_bytes(): Vec<u8, A> {
        unsafe {
            let v = core.ptr.`read`(core.ptr.from_ref(self.v))
            core.mem.forget(take self)
            v
        }
    }
    // Safety: the bytes must be well-formed UTF-8 again before the string is
    // next observed as text (including on drop-free early exits such as errors).
    pub mut unsafe fn as_mut_vec(): mut Vec<u8, A> from self { mut self.v }
    pub mut fn try_reserve(extra: usize): Unit throws AllocError { try self.v.try_reserve(extra) }
    pub mut fn reserve(extra: usize): Unit { self.v.reserve(extra) }

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
    pub mut fn clear(): Unit { self.v.clear() }
}

extend<A: Allocator + Clone> String<A> implements Clone {
    fn clone(): String<A> { String(self.v.clone()) }
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
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error { try f.pad(self.as_text()) }
}
extend<A: Allocator> String<A> implements fmt.Debug {
    fn fmt<W: fmt.Write>(f: mut fmt.Formatter<W>): Unit throws fmt.Error { try Text.(fmt.Debug).fmt(self.as_text(), mut f) }
}

// Concatenation: a new string holding `a` followed by `b`.
pub fn concat(a: read Text, b: read Text): String {
    var s = with_capacity(a.len() + b.len())
    s.push_str(a)
    s.push_str(b)
    s
}
