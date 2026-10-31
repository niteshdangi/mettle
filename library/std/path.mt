// Paths over operating-system strings: `Path` is the unsized view and
// `PathBuf` the owner. Bytes are never reinterpreted, so non-Unicode names
// round-trip losslessly. Separator is `/`; repeated separators and `.`
// components are ignored when splitting.
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.alloc.AllocError
import package.alloc.string.String
import package.alloc.string.FromUtf8Error
import package.core.text.Text
import package.core.slice
import super.ffi
import super.ffi.{OsStr, OsString}

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
    pub static fn new(bytes: read [u8]): read Path from bytes { path(bytes) }
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn as_os_str(): read OsStr from self { ffi.os_str(read self.bytes) }
    pub mut fn as_mut_os_str(): mut OsStr from self { ffi.os_str_mut(self.bytes) }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn to_str(): (read Text from self)? { package.core.text.from_utf8(read self.bytes) }
    pub fn to_string_lossy(): String { ffi.lossy(read self.bytes) }
    pub fn is_absolute(): bool { self.bytes.len() > 0usize && is_sep(self.bytes[0usize]) }
    pub fn has_root(): bool { self.is_absolute() }
    pub fn is_relative(): bool { !self.is_absolute() }
    pub fn same(other: read Path): bool { ffi.bytes_equal(read self.bytes, other.as_bytes()) }
    pub fn to_path_buf(): PathBuf { path_buf_from_bytes(read self.bytes) }
    pub fn into_path_buf(): PathBuf { self.to_path_buf() }
    pub fn display(): String { self.to_string_lossy() }

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

    pub fn file_prefix(): (read OsStr from self)? {
        match self.file_name() {
            present(name) => {
                let bytes = name.as_bytes()
                var i = 1usize
                while i < bytes.len() {
                    if bytes[i] == 46u8 {
                        return present(ffi.os_str(unsafe {
                            slice.subslice_unchecked(bytes, 0usize, i)
                        }))
                    }
                    i += 1usize
                }
                present(name)
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
        if bend == 0usize { return true }
        if bend > a.len() { return false }
        var i = 0usize
        while i < bend {
            if a[i] != b[i] { return false }
            i += 1usize
        }
        bend == a.len() || is_sep(a[bend]) || (bend > 0usize && is_sep(b[bend - 1usize]))
    }

    pub fn ends_with(suffix: read Path): bool {
        let a: read [u8] = read self.bytes
        let b = suffix.as_bytes()
        let a_end = trimmed_end(a)
        let b_end = trimmed_end(b)
        if b_end > a_end { return false }
        let offset = a_end - b_end
        var i = 0usize
        while i < b_end {
            if a[offset + i] != b[i] { return false }
            i += 1usize
        }
        let component_start = last_start(a, trimmed_end(a))
        b_end == 0usize || offset == 0usize || is_sep(a[offset - 1usize]) ||
            component_start == offset
    }

    pub fn strip_prefix(prefix: read Path): (read Path from self)? {
        if !self.starts_with(prefix) { return none }
        let bytes: read [u8] = read self.bytes
        let prefix_len = trimmed_end(prefix.as_bytes())
        if prefix_len == 0usize { return present(read self) }
        var start = prefix_len
        while start < bytes.len() && is_sep(bytes[start]) { start += 1usize }
        present(path(unsafe { slice.subslice_unchecked(bytes, start, bytes.len()) }))
    }

    pub fn with_file_name(name: read OsStr): PathBuf {
        var result = self.to_path_buf()
        result.set_file_name(name)
        result
    }

    pub fn with_extension(extension: read OsStr): PathBuf {
        var result = self.to_path_buf()
        result.set_extension(extension)
        result
    }

    pub fn with_added_extension(extension: read OsStr): PathBuf {
        var result = self.to_path_buf()
        result.add_extension(extension)
        result
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
pub fn path_buf_with_capacity(capacity: usize): PathBuf {
    PathBuf(vec.with_capacity<u8>(capacity))
}

pub fn path_buf_from_bytes(bytes: read [u8]): PathBuf {
    var v = vec.with_capacity<u8>(bytes.len())
    v.extend_from_slice(bytes)
    PathBuf(v)
}

pub fn path_buf_from_text(text: read Text): PathBuf { path_buf_from_bytes(text.as_bytes()) }

extend PathBuf {
    pub static fn new(): PathBuf { new_path_buf() }
    pub static fn with_capacity(capacity: usize): PathBuf {
        path_buf_with_capacity(capacity)
    }
    pub fn as_path(): read Path from self { path(self.v.as_slice()) }
    pub fn as_os_str(): read OsStr from self { ffi.os_str(self.v.as_slice()) }
    pub mut fn as_mut_os_str(): mut OsStr from self { ffi.os_str_mut(self.v.as_mut_slice()) }
    pub fn as_bytes(): read [u8] from self { self.v.as_slice() }
    pub fn capacity(): usize { self.v.capacity() }
    pub fn is_empty(): bool { self.v.is_empty() }
    pub fn is_absolute(): bool { self.as_path().is_absolute() }
    pub fn has_root(): bool { self.as_path().has_root() }
    pub fn is_relative(): bool { self.as_path().is_relative() }
    pub fn to_str(): (read Text from self)? { self.as_path().to_str() }
    pub fn to_string_lossy(): String { self.as_path().to_string_lossy() }
    pub fn display(): String { self.as_path().display() }
    pub fn to_path_buf(): PathBuf { path_buf_from_bytes(self.v.as_slice()) }
    pub take fn into_os_string(): OsString { ffi.os_string_from_vec(self.v) }
    pub take fn into_string(): String throws FromUtf8Error {
        try package.alloc.string.from_utf8(self.v)
    }
    pub mut fn clear(): Unit { self.v.clear() }
    pub mut fn reserve(additional: usize): Unit { self.v.reserve(additional) }
    pub mut fn reserve_exact(additional: usize): Unit { self.v.reserve_exact(additional) }
    pub mut fn try_reserve(additional: usize): Unit throws AllocError {
        try self.v.try_reserve(additional)
    }
    pub mut fn try_reserve_exact(additional: usize): Unit throws AllocError {
        try self.v.try_reserve_exact(additional)
    }
    pub mut fn shrink_to_fit(): Unit { self.v.shrink_to_fit() }
    pub mut fn shrink_to(minimum: usize): Unit {
        if minimum > self.v.capacity() {
            self.v.reserve(minimum - self.v.len())
        } else if minimum <= self.v.len() {
            self.v.shrink_to_fit()
        }
    }

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

    pub mut fn set_file_name(name: read OsStr): bool {
        if self.as_path().file_name().is_none() { return false }
        let parent_len = match self.as_path().parent() {
            present(parent) => present(parent.as_bytes().len()),
            none => none
        }
        match parent_len {
            present(n) => {
                self.v.truncate(n)
                if self.v.len() > 0usize && !is_sep(self.v[self.v.len() - 1usize]) {
                    self.v.push(47u8)
                }
                self.v.extend_from_slice(name.as_bytes())
                true
            },
            none => {
                if self.v.is_empty() { return false }
                self.v.clear()
                self.v.extend_from_slice(name.as_bytes())
                true
            }
        }
    }

    pub mut fn set_extension(extension: read OsStr): bool {
        let bytes = self.v.as_slice()
        let end = trimmed_end(bytes)
        let name_start = last_start(bytes, end)
        let name = unsafe { slice.subslice_unchecked(bytes, name_start, end) }
        if name.len() == 0usize || (name.len() == 1usize && name[0usize] == 46u8) ||
           (name.len() == 2usize && name[0usize] == 46u8 && name[1usize] == 46u8) {
            return false
        }
        match last_dot(name) {
            present(dot) => self.v.truncate(name_start + dot),
            none => self.v.truncate(end)
        }
        let ext = extension.as_bytes()
        if ext.len() > 0usize {
            self.v.push(46u8)
            self.v.extend_from_slice(ext)
        }
        true
    }

    pub mut fn add_extension(extension: read OsStr): Unit {
        let ext = extension.as_bytes()
        if ext.len() > 0usize {
            let end = trimmed_end(self.v.as_slice())
            if end == 0usize { return }
            self.v.truncate(end)
            self.v.push(46u8)
            self.v.extend_from_slice(ext)
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
