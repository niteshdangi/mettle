import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.default.Default
import super.fmt
import super.hash.{Hash, Hasher}
import super.iter.{Iterator, RangeBounds}
import super.text.{Text, Utf8Error}
import super.slice

pub copy enum FromBytesWithNulError {
    InteriorNul { position: usize },
    NotNulTerminated
}
pub copy type FromBytesUntilNulError {}

pub type CStr { bytes: [u8] }
static EMPTY_C_STR_BYTES: [u8; 1] = [0u8]

// Safety: bytes contain exactly one NUL, at the end; the slice-tail cast preserves their extent.
unsafe const fn c_str_view(read bytes: [u8]): read CStr from bytes {
    let pointer = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read CStr>>(pointer) }
    unsafe { read *view }
}

extend CStr {
    pub static const fn from_bytes_with_nul(
        read bytes: [u8]
    ): read CStr from bytes throws FromBytesWithNulError {
        if bytes.len() == 0usize { throw FromBytesWithNulError.NotNulTerminated }
        let terminator = bytes.len() - 1usize
        var i = 0usize
        while i < terminator {
            if bytes[i] == 0u8 { throw FromBytesWithNulError.InteriorNul(i) }
            i += 1usize
        }
        if bytes[terminator] != 0u8 { throw FromBytesWithNulError.NotNulTerminated }
        unsafe { c_str_view(bytes) }
    }

    pub static const fn from_bytes_until_nul(
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

    // Safety: the bytes must end in one NUL and contain no earlier NUL.
    pub static unsafe const fn from_bytes_with_nul_unchecked(
        read bytes: [u8]
    ): read CStr from bytes { unsafe { c_str_view(bytes) } }

    // Safety: pointer stays readable through NUL and the result does not outlive that storage.
    pub static unsafe const fn from_ptr<region s>(
        pointer: ptr<read i8>
    ): read CStr from s {
        var length = 0usize
        while unsafe { *pointer.add(length) } != 0i8 { length += 1usize }
        let bytes = unsafe { slice.from_raw_parts<u8>(pointer.cast<u8>(), length + 1usize) }
        unsafe { c_str_view(bytes) }
    }

    pub const fn as_ptr(): ptr<read i8> { self.bytes.as_ptr().cast<i8>() }
    pub const fn count_bytes(): usize { self.bytes.len() - 1usize }
    pub const fn is_empty(): bool { self.bytes.len() == 1usize }
    pub const fn to_bytes_with_nul(): read [u8] from self { read self.bytes }
    pub const fn to_bytes(): read [u8] from self {
        match slice.subslice(read self.bytes, 0usize, self.bytes.len() - 1usize) {
            present(bytes) => bytes,
            none => super.panic.panic("invalid C string")
        }
    }
    pub const fn to_str(): Outcome<read Text from self, Utf8Error> {
        super.text.from_utf8(self.to_bytes())
    }
}

extend<region r> read CStr from r implements Default {
    static fn default(): read CStr from r { unsafe { c_str_view(EMPTY_C_STR_BYTES) } }
}

extend CStr implements super.ops.Index<super.iter.RangeFrom<usize>> {
    type Output = CStr
    fn index(read index: super.iter.RangeFrom<usize>): read CStr from self {
        let start = match take index.start_bound() {
            super.iter.Bound.Included(value) => *value,
            _ => super.panic.panic("invalid C string range")
        }
        if start >= self.bytes.len() { super.panic.panic("C string index out of bounds") }
        match slice.subslice(read self.bytes, start, self.bytes.len()) {
            present(bytes) => unsafe { c_str_view(bytes) },
            none => super.panic.panic("C string index out of bounds")
        }
    }
}

extend CStr implements PartialEq {
    fn eq(read other: CStr): bool {
        if self.bytes.len() != other.bytes.len() { return false }
        var i = 0usize
        while i < self.bytes.len() {
            if self.bytes[i] != other.bytes[i] { return false }
            i += 1usize
        }
        true
    }
}
extend CStr implements Eq {}
extend<region r> CStr implements PartialEq<read CStr from r> {
    fn eq(read other: read CStr from r): bool { CStr.(PartialEq).eq(read self, *other) }
}
extend CStr implements PartialOrd {
    fn partial_cmp(read other: CStr): Ordering? { present(self.cmp(other)) }
}
extend CStr implements Ord {
    fn cmp(read other: CStr): Ordering { self.to_bytes().cmp(other.to_bytes()) }
}
extend CStr implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.to_bytes().hash(mut state) }
}
type CStrDebug<region r> { value: read CStr from r }
extend<region r> CStrDebug<region r> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_char('"')
        var bytes = self.value.to_bytes()
        while bytes.len() != 0usize {
            let invalid = match super.text.from_utf8(bytes) {
                success(_) => none,
                failure(error) => present(error)
            }
            let valid = match invalid {
                present(error) => error.valid_up_to(),
                none => bytes.len()
            }
            let prefix = slice.subslice(bytes, 0usize, valid).unwrap()
            let text = unsafe { super.text.from_utf8_unchecked(prefix) }
            var chars = text.chars()
            while true {
                match chars.next() {
                    present(c) => {
                        var escaped = c.escape_debug_ext(false, true, true)
                        while true {
                            match escaped.next() {
                                present(part) => { try f.write_char(part) },
                                none => { break }
                            }
                        }
                    },
                    none => { break }
                }
            }
            let consumed = match invalid {
                present(error) => {
                    try f.write_char('\u{fffd}')
                    match error.error_len() {
                        present(length) => valid + length,
                        none => bytes.len()
                    }
                },
                none => bytes.len()
            }
            bytes = slice.subslice(bytes, consumed, bytes.len()).unwrap()
        }
        try f.write_char('"')
    }
}
extend CStr implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("CStr")
        try debug.field(CStrDebug(read self))
        try debug.finish()
    }
}
