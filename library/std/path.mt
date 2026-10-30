// Paths over operating-system strings: `Path` is the unsized view and
// `PathBuf` the owner. Bytes are never reinterpreted, so non-Unicode names
// round-trip losslessly. Separator is `/`; repeated separators and `.`
// components are ignored when splitting.
import package.alloc.vec;
import package.alloc.vec.List;
import package.alloc.string.String;
import package.core.text.Text;
import package.core.slice;
import super.ffi;
import super.ffi.{OsStr, OsString};

pub type Path { bytes: [u8] }

pub fn path(bytes: read [u8]): read Path from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read Path>>(fat) }
    unsafe { read *view }
}

pub fn path_from_text(text: read Text): read Path from text { path(text.as_bytes()) }

pub fn path_from_os_str(s: read OsStr): read Path from s { path(s.as_bytes()) }

// Anything that views as a native path without allocation or conversion.
// Hosted path-taking functions accept `read PathInput`, so callers pass a
// `Path`, `PathBuf`, `OsStr` or `OsString` directly; the borrow never outlives
// the source. On POSIX the path is the unmodified OS-string bytes.
pub interface PathInput {
    fn as_path(): read Path from self;
}

fn is_sep(b: u8): bool { b == 47u8 }

// End (exclusive) of `bytes` once trailing separators are removed; a root
// path keeps its single separator.
fn trimmed_end(bytes: read [u8]): usize {
    var end = bytes.len()
    while end > 1usize && is_sep(bytes[end - 1usize]) { end -= 1usize }
    end
}

// Start of the final component of bytes[..end].
fn last_start(bytes: read [u8], end: usize): usize {
    var start = end
    while start > 0usize && !is_sep(bytes[start - 1usize]) { start -= 1usize }
    start
}

extend Path {
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn as_os_str(): read OsStr from self { ffi.os_str(read self.bytes) }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn to_str(): (read Text from self)? { package.core.text.from_utf8(read self.bytes) }
    pub fn to_string_lossy(): String { ffi.lossy(read self.bytes) }
    pub fn is_absolute(): bool { self.bytes.len() > 0usize && is_sep(self.bytes[0usize]) }
    pub fn same(other: read Path): bool { ffi.bytes_equal(read self.bytes, other.as_bytes()) }
    pub fn to_path_buf(): PathBuf { path_buf_from_bytes(read self.bytes) }

    // Last component; none for `/`, an empty path or one ending in `..`.
    pub fn file_name(): (read OsStr from self)? {
        let bytes: read [u8] = read self.bytes
        let end = trimmed_end(bytes)
        if end == 0usize { return none }
        let start = last_start(bytes, end)
        if start == end { return none }
        let name = unsafe { slice.subslice_unchecked(bytes, start, end) }
        if name.len() == 1usize && name[0usize] == 46u8 { return none }
        if name.len() == 2usize && name[0usize] == 46u8 && name[1usize] == 46u8 { return none }
        present(ffi.os_str(name))
    }

    // Everything before the final component, without its separator.
    pub fn parent(): (read Path from self)? {
        let bytes: read [u8] = read self.bytes
        let end = trimmed_end(bytes)
        if end == 0usize { return none }
        if end == 1usize && is_sep(bytes[0usize]) { return none }
        var start = last_start(bytes, end)
        while start > 1usize && is_sep(bytes[start - 1usize]) { start -= 1usize }
        present(path(unsafe { slice.subslice_unchecked(bytes, 0usize, start) }))
    }

    // Final component without the extension (a leading dot is not one).
    pub fn file_stem(): (read OsStr from self)? {
        match self.file_name() {
            present(name) => {
                let b = name.as_bytes()
                let dot = last_dot(b)
                match dot {
                    present(i) => present(ffi.os_str(unsafe { slice.subslice_unchecked(b, 0usize, i) })),
                    none => present(name)
                }
            },
            none => none
        }
    }

    pub fn extension(): (read OsStr from self)? {
        match self.file_name() {
            present(name) => {
                let b = name.as_bytes()
                match last_dot(b) {
                    present(i) => present(ffi.os_str(unsafe { slice.subslice_unchecked(b, i + 1usize, b.len()) })),
                    none => none
                }
            },
            none => none
        }
    }

    // `other` appended with a separator; an absolute `other` replaces `self`.
    pub fn join(other: read Path): PathBuf {
        var out = path_buf_from_bytes(read self.bytes)
        out.push(other)
        out
    }

    pub fn starts_with(prefix: read Path): bool {
        let a: read [u8] = read self.bytes
        let b = prefix.as_bytes()
        let bend = trimmed_end(b)
        if bend > a.len() { return false }
        var i = 0usize
        while i < bend {
            if a[i] != b[i] { return false }
            i += 1usize
        }
        bend == a.len() || is_sep(a[bend]) || (bend > 0usize && is_sep(b[bend - 1usize]))
    }
}

// Index of the extension dot in a file name; a dot at the start is ignored.
fn last_dot(name: read [u8]): usize? {
    var i = name.len()
    while i > 1usize {
        i -= 1usize
        if name[i] == 46u8 { return present(i) }
    }
    none
}

pub type PathBuf { v: List<u8> }

pub fn new_path_buf(): PathBuf { PathBuf(vec.new<u8>()) }

pub fn path_buf_from_bytes(bytes: read [u8]): PathBuf {
    var v = vec.with_capacity<u8>(bytes.len())
    v.extend_from_slice(bytes)
    PathBuf(v)
}

pub fn path_buf_from_text(text: read Text): PathBuf { path_buf_from_bytes(text.as_bytes()) }

extend PathBuf {
    pub fn as_path(): read Path from self { path(self.v.as_slice()) }
    pub fn as_bytes(): read [u8] from self { self.v.as_slice() }
    pub take fn into_os_string(): OsString { ffi.os_string_from_vec(self.v) }

    // Appends a component, adding a separator when needed; an absolute `p`
    // replaces the whole path.
    pub mut fn push(p: read Path): Unit {
        if p.is_absolute() {
            self.v.clear()
        } else if self.v.len() > 0usize && !is_sep(self.v[self.v.len() - 1usize]) {
            self.v.push(47u8)
        }
        self.v.extend_from_slice(p.as_bytes())
    }

    // Removes the final component; false when there was none to remove.
    pub mut fn pop(): bool {
        let keep = match self.as_path().parent() {
            present(p) => present(p.as_bytes().len()),
            none => none
        }
        match keep {
            present(n) => { self.v.truncate(n); true },
            none => false
        }
    }
    pub fn same(other: read PathBuf): bool { ffi.bytes_equal(self.v.as_slice(), other.as_bytes()) }
}

extend Path implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}
extend PathBuf implements PathInput {
    fn as_path(): read Path from self { path(self.v.as_slice()) }
}
extend OsStr implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}
extend OsString implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}
