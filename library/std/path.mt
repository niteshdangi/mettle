// Paths over operating-system strings: `Path` is the unsized view and
// `PathBuf` the owner. Bytes are never reinterpreted, so non-Unicode names
// round-trip losslessly. Separator is `/`; repeated separators and interior
// `.` components are ignored, while a leading `.` in a relative path remains.
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.boxed.Box
import package.alloc.arc.Arc
import package.alloc.rc.Rc
import package.alloc.borrow.BorrowedOrOwned
import package.alloc.alloc.AllocError
import package.alloc.string.String
import package.alloc.string.FromUtf8Error
import package.core.iter.{BidirectionalIterator, Iterator}
import package.core.text.Text
import package.core.slice
import super.ffi
import super.ffi.{OsStr, OsString}
import package.core.clone.Clone
import package.core.borrow.{AsRef, Borrow, OwnedType, ToOwned}
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.convert.From
import package.core.default.Default
import package.core.hash.{Hash, Hasher}
import package.core.iter.{FromItems, ExtendItems, OwnedIterable}
import package.core.ops.{Deref, DerefMut}
import package.core.fmt.{Debug, Formatter, Error}

pub type Path { bytes: [u8] }

pub copy type StripPrefixError {}
extend StripPrefixError implements Clone {
    fn clone(): StripPrefixError { self }
}
extend StripPrefixError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("StripPrefixError") }
}
extend StripPrefixError implements package.core.fmt.Display {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("prefix not found") }
}
extend StripPrefixError implements package.core.error.Error {}

pub copy enum Component<region r> {
    RootDir,
    CurDir,
    ParentDir,
    Normal(read OsStr from r)
}

pub type Components<region r> {
    path: read Path from r
    front: usize
    back: usize
    root_pending: bool
    leading_cur_dir: bool
}

pub type Iter<region r> { components: Components<region r> }

pub type Ancestors<region r> { current: read Path from r; finished: bool }

pub fn path(read bytes: [u8]): read Path from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read Path>>(fat) }
    unsafe { read *view }
}

pub fn path_from_text(read text: Text): read Path from text { path(text.as_bytes()) }

pub fn path_from_os_str(read s: OsStr): read Path from s { path(s.as_bytes()) }

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
fn trimmed_end(read bytes: [u8]): usize {
    var end = bytes.len()
    while end > 1usize && is_sep(bytes[end - 1usize]) { end -= 1usize }
    end
}

// Start of the final component of bytes[..end].
fn last_start(read bytes: [u8], end: usize): usize {
    var start = end
    while start > 0usize && !is_sep(bytes[start - 1usize]) { start -= 1usize }
    start
}

fn is_dot(read bytes: [u8], start: usize, end: usize): bool {
    end - start == 1usize && bytes[start] == 46u8
}

fn is_dot_dot(read bytes: [u8], start: usize, end: usize): bool {
    end - start == 2usize && bytes[start] == 46u8 && bytes[start + 1usize] == 46u8
}

fn has_leading_cur_dir(read bytes: [u8]): bool {
    bytes.len() > 0usize && bytes[0usize] == 46u8 &&
        (bytes.len() == 1usize || is_sep(bytes[1usize]))
}

fn checked_part(read bytes: [u8], start: usize, end: usize): read [u8] {
    match slice.subslice(bytes, start, end) {
        present(part) => part,
        none => { package.core.panic.panic("path component bounds invariant failed") }
    }
}

fn component_tag(component: Component): u8 {
    match component {
        Component.RootDir => 0u8,
        Component.CurDir => 1u8,
        Component.ParentDir => 2u8,
        Component.Normal(_) => 3u8
    }
}

fn same_component(left: Component, right: Component): bool {
    if component_tag(left) != component_tag(right) { return false }
    match left {
        Component.Normal(a) => match right {
            Component.Normal(b) => a.same(b),
            _ => false
        },
        _ => true
    }
}

fn final_name_end(read bytes: [u8]): usize? {
    var end = trimmed_end(bytes)
    while end > 0usize {
        let start = last_start(bytes, end)
        if start == end || is_dot_dot(bytes, start, end) { return none }
        if !is_dot(bytes, start, end) { return present(end) }
        if start == 0usize { return none }
        end = trimmed_end(checked_part(bytes, 0usize, start))
    }
    none
}

fn validate_extension(read extension: OsStr): Unit {
    let bytes = extension.as_bytes()
    var index = 0usize
    while index < bytes.len() {
        if is_sep(bytes[index]) { package.core.panic.panic("path extension contains a separator") }
        index += 1usize
    }
}

fn compare_bytes(read left: [u8], read right: [u8]): Ordering {
    var index = 0usize
    while index < left.len() && index < right.len() {
        if left[index] != right[index] {
            return if left[index] < right[index] {
                Ordering.Less
            } else {
                Ordering.Greater
            }
        }
        index += 1usize
    }
    if left.len() < right.len() {
        Ordering.Less
    } else if left.len() > right.len() {
        Ordering.Greater
    } else {
        Ordering.Equal
    }
}

fn compare_components(read left: Path, read right: Path): Ordering {
    var a = left.components()
    var b = right.components()
    while true {
        match a.next() {
            present(left_component) => match b.next() {
                present(right_component) => {
                    let left_tag = component_tag(left_component)
                    let right_tag = component_tag(right_component)
                    if left_tag != right_tag {
                        return if left_tag < right_tag {
                            Ordering.Less
                        } else {
                            Ordering.Greater
                        }
                    }
                    match left_component {
                        Component.Normal(left_name) => match right_component {
                            Component.Normal(right_name) => {
                                let order = compare_bytes(
                                    left_name.as_bytes(),
                                    right_name.as_bytes()
                                )
                                if order != Ordering.Equal { return order }
                            },
                            _ => {}
                        },
                        _ => {}
                    }
                },
                none => { return Ordering.Greater }
            },
            none => {
                return if b.next().is_present() {
                    Ordering.Less
                } else {
                    Ordering.Equal
                }
            }
        }
    }
    Ordering.Equal
}

fn hash_path<H: Hasher>(read value: Path, mut state: H): Unit {
    var components = value.components()
    while true {
        match components.next() {
            present(component) => {
                state.write_u8(component_tag(component))
                match component {
                    Component.Normal(name) => {
                        let bytes = name.as_bytes()
                        state.write_usize(bytes.len())
                        state.write(bytes)
                    },
                    _ => {}
                }
            },
            none => { break }
        }
    }
    state.write_u8(255u8)
}

extend<region r> Component<region r> {
    pub fn as_os_str(receiver self: Component<region r>): read OsStr from r {
        match self {
            Component.RootDir => ffi.os_str("/".as_bytes()),
            Component.CurDir => ffi.os_str(".".as_bytes()),
            Component.ParentDir => ffi.os_str("..".as_bytes()),
            Component.Normal(name) => name
        }
    }
}

extend<region r> Component<region r> implements package.core.clone.Clone {
    fn clone(): Component<region r> {
        match self {
            Component.RootDir => Component<region r>.RootDir,
            Component.CurDir => Component<region r>.CurDir,
            Component.ParentDir => Component<region r>.ParentDir,
            Component.Normal(name) => Component.Normal(name)
        }
    }
}

extend<region r> Components<region r> {
    pub fn as_path(): read Path from r {
        let bytes = self.path.as_bytes()
        var start = self.front
        var end = self.back

        if self.front > 0usize {
            while start < end && is_sep(bytes[start]) { start += 1usize }
            var trimming = true
            while trimming && start < end {
                var part_end = start
                while part_end < end && !is_sep(bytes[part_end]) {
                    part_end += 1usize
                }
                if is_dot(bytes, start, part_end) &&
                    !(self.leading_cur_dir && start == 0usize) {
                    start = part_end
                    while start < end && is_sep(bytes[start]) {
                        start += 1usize
                    }
                } else {
                    trimming = false
                }
            }
        }

        if self.back < bytes.len() {
            while end > start && is_sep(bytes[end - 1usize]) { end -= 1usize }
            var trimming = true
            while trimming && end > start {
                var part_start = end
                while part_start > start && !is_sep(bytes[part_start - 1usize]) {
                    part_start -= 1usize
                }
                if is_dot(bytes, part_start, end) &&
                    !(self.leading_cur_dir && part_start == 0usize) {
                    end = part_start
                    while end > start && is_sep(bytes[end - 1usize]) {
                        end -= 1usize
                    }
                } else {
                    trimming = false
                }
            }
        }

        if self.root_pending && end == 0usize { end = 1usize }
        path(checked_part(bytes, start, end))
    }
}

extend<region r> Components<region r> implements package.core.clone.Clone {
    fn clone(): Components<region r> {
        Components(
            self.path,
            self.front,
            self.back,
            self.root_pending,
            self.leading_cur_dir
        )
    }
}

extend<region r> Iter<region r> {
    pub fn as_path(): read Path from r { self.components.as_path() }
}

extend<region r> Iter<region r> implements package.core.clone.Clone {
    fn clone(): Iter<region r> {
        Iter(Components(
            self.components.path,
            self.components.front,
            self.components.back,
            self.components.root_pending,
            self.components.leading_cur_dir
        ))
    }
}

extend<region r> Ancestors<region r> implements package.core.clone.Clone {
    fn clone(): Ancestors<region r> { Ancestors(self.current, self.finished) }
}

extend Path {
    pub static fn new(read bytes: [u8]): read Path from bytes { path(bytes) }
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn as_os_str(): read OsStr from self { ffi.os_str(read self.bytes) }
    pub mut fn as_mut_os_str(): mut OsStr from self { ffi.os_str_mut(self.bytes) }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn to_str(): (read Text from self)? {
        match package.core.text.from_utf8(read self.bytes) {
            success(text) => present(text),
            failure(_) => none
        }
    }
    pub fn to_string_lossy(): String { ffi.lossy(read self.bytes) }
    pub fn is_absolute(): bool { self.bytes.len() > 0usize && is_sep(self.bytes[0usize]) }
    pub fn has_root(): bool { self.is_absolute() }
    pub fn is_relative(): bool { !self.is_absolute() }
    pub fn same(read other: Path): bool { ffi.bytes_equal(read self.bytes, other.as_bytes()) }
    pub fn to_path_buf(): PathBuf { path_buf_from_bytes(read self.bytes) }
    pub fn into_path_buf(): PathBuf { self.to_path_buf() }
    pub fn display<region r>(receiver read self: Path from r): ffi.Display<region r> {
        self.as_os_str().display()
    }
    pub fn components<region r>(
        receiver read self: Path from r
    ): Components<region r> {
        let bytes = self.as_bytes()
        Components(
            read self,
            0usize,
            bytes.len(),
            self.is_absolute(),
            has_leading_cur_dir(bytes)
        )
    }

    pub fn iter<region r>(receiver read self: Path from r): Iter<region r> {
        Iter(self.components())
    }
    pub fn ancestors<region r>(
        receiver read self: Path from r
    ): Ancestors<region r> {
        Ancestors(read self, false)
    }

    // Last component; none for `/`, an empty path or one ending in `..`.
    pub fn file_name(): (read OsStr from self)? {
        var components = self.components()
        match components.next_back() {
            present(Component.Normal(name)) => present(name),
            _ => none
        }
    }

    // Everything before the final component, without its separator.
    pub fn parent(): (read Path from self)? {
        var components = self.components()
        match components.next_back() {
            present(Component.RootDir) => none,
            present(_) => present(components.as_path()),
            none => none
        }
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
    pub fn join(read other: PathInput): PathBuf {
        var out = path_buf_from_bytes(read self.bytes)
        out.push(other)
        out
    }

    pub fn starts_with(read prefix: Path): bool {
        match take capture self.strip_prefix(prefix) {
            success(_) => true,
            failure(_) => false
        }
    }

    pub fn ends_with(read suffix: Path): bool {
        var actual = self.components()
        var wanted = suffix.components()
        while true {
            match wanted.next_back() {
                present(component) => match actual.next_back() {
                    present(found) => { if !same_component(found, component) { return false } },
                    none => { return false }
                },
                none => { return true }
            }
        }
        false
    }

    pub fn strip_prefix(read prefix: Path): read Path from self throws StripPrefixError {
        var actual = self.components()
        var wanted = prefix.components()
        while true {
            match wanted.next() {
                present(component) => match actual.next() {
                    present(found) => { if !same_component(found, component) { throw StripPrefixError() } },
                    none => { throw StripPrefixError() }
                },
                none => { return actual.as_path() }
            }
        }
        throw StripPrefixError()
    }

    pub fn with_file_name(read name: PathInput): PathBuf {
        var result = self.to_path_buf()
        result.set_file_name(name)
        result
    }

    pub fn with_extension(read extension: OsStr): PathBuf {
        var result = self.to_path_buf()
        result.set_extension(extension)
        result
    }

    pub fn with_added_extension(read extension: OsStr): PathBuf {
        var result = self.to_path_buf()
        result.add_extension(extension)
        result
    }
}

extend Path implements PartialEq {
    fn eq(read other: Path): bool {
        self.cmp(other) == Ordering.Equal
    }
}
extend Path implements Eq {}
extend Path implements PartialOrd {
    fn partial_cmp(read other: Path): Ordering? { present(self.cmp(other)) }
}
extend Path implements Ord {
    fn cmp(read other: Path): Ordering { compare_components(self, other) }
}
extend Path implements PartialEq<OsStr> {
    fn eq(read other: OsStr): bool {
        self.cmp(path_from_os_str(other)) == Ordering.Equal
    }
}
extend Path implements PartialOrd<OsStr> {
    fn partial_cmp(read other: OsStr): Ordering? {
        present(self.cmp(path_from_os_str(other)))
    }
}
extend Path implements PartialEq<OsString> {
    fn eq(read other: OsString): bool {
        self.cmp(path_from_os_str(other.as_os_str())) == Ordering.Equal
    }
}
extend Path implements PartialOrd<OsString> {
    fn partial_cmp(read other: OsString): Ordering? {
        present(self.cmp(path_from_os_str(other.as_os_str())))
    }
}
extend Path implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool {
        self.cmp(other.as_path()) == Ordering.Equal
    }
}
extend Path implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        present(self.cmp(other.as_path()))
    }
}
extend Path implements PartialEq<String> {
    fn eq(read other: String): bool {
        self.cmp(path_from_text(other.as_text())) == Ordering.Equal
    }
}
extend Path implements PartialEq<Text> {
    fn eq(read other: Text): bool {
        self.cmp(path_from_text(other)) == Ordering.Equal
    }
}
extend Path implements PartialOrd<String> {
    fn partial_cmp(read other: String): Ordering? {
        present(self.cmp(path_from_text(other.as_text())))
    }
}
extend Path implements PartialOrd<Text> {
    fn partial_cmp(read other: Text): Ordering? {
        present(self.cmp(path_from_text(other)))
    }
}
extend Path implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { hash_path(self, mut state) }
}
extend Path implements OwnedType {
    type Owned = PathBuf
}
extend Path implements ToOwned {
    fn to_owned(): PathBuf { self.to_path_buf() }
}
extend Path implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.as_os_str() }
}
extend Path implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        let display = self.to_string_lossy()
        var debug = try f.debug_tuple("Path")
        try debug.field(display.as_text())
        try debug.finish()
    }
}

extend<region r> Components<region r> implements package.core.iter.Iterator {
    type Item = Component<region r>
    mut fn next(): Component<region r>? {
        let bytes = self.path.as_bytes()
        if self.root_pending {
            self.root_pending = false
            while self.front < self.back && is_sep(bytes[self.front]) {
                self.front += 1usize
            }
            return present(Component<region r>.RootDir)
        }

        while self.front < self.back {
            while self.front < self.back && is_sep(bytes[self.front]) {
                self.front += 1usize
            }
            if self.front >= self.back { return none }
            let start = self.front
            while self.front < self.back && !is_sep(bytes[self.front]) {
                self.front += 1usize
            }
            let end = self.front
            if is_dot(bytes, start, end) {
                if self.leading_cur_dir && start == 0usize {
                    self.leading_cur_dir = false
                    return present(Component<region r>.CurDir)
                }
                continue
            }
            if is_dot_dot(bytes, start, end) {
                return present(Component<region r>.ParentDir)
            }
            return present(Component.Normal(ffi.os_str(checked_part(bytes, start, end))))
        }
        none
    }
}

extend<region r> Components<region r> implements package.core.iter.BidirectionalIterator {
    mut fn next_back(): Component<region r>? {
        let bytes = self.path.as_bytes()
        while true {
            while self.back > self.front && is_sep(bytes[self.back - 1usize]) {
                self.back -= 1usize
            }
            if self.back <= self.front {
                if self.root_pending {
                    self.root_pending = false
                    self.front = self.back
                    return present(Component<region r>.RootDir)
                }
                if self.leading_cur_dir {
                    self.leading_cur_dir = false
                    self.front = self.back
                    return present(Component<region r>.CurDir)
                }
                return none
            }

            let end = self.back
            var start = end
            while start > self.front && !is_sep(bytes[start - 1usize]) {
                start -= 1usize
            }
            self.back = start
            if is_dot(bytes, start, end) {
                if self.leading_cur_dir && start == 0usize {
                    self.leading_cur_dir = false
                    self.front = self.back
                    return present(Component<region r>.CurDir)
                }
                continue
            }
            if is_dot_dot(bytes, start, end) {
                return present(Component<region r>.ParentDir)
            }
            return present(Component.Normal(ffi.os_str(checked_part(bytes, start, end))))
        }
        none
    }
}

extend<region r> Iter<region r> implements package.core.iter.Iterator {
    type Item = read OsStr from r
    mut fn next(): (read OsStr from r)? {
        match take self.components.next() {
            present(component) => present(component.as_os_str()),
            none => none
        }
    }
}

extend<region r> Iter<region r> implements package.core.iter.BidirectionalIterator {
    mut fn next_back(): (read OsStr from r)? {
        match take self.components.next_back() {
            present(component) => present(component.as_os_str()),
            none => none
        }
    }
}

extend<region r> Ancestors<region r> implements package.core.iter.Iterator {
    type Item = read Path from r
    mut fn next(): (read Path from r)? {
        if self.finished { return none }
        let current = self.current
        match self.current.parent() {
            present(parent) => { self.current = parent },
            none => { self.finished = true }
        }
        present(current)
    }
}

fn last_dot(read name: [u8]): usize? {
    var i = name.len()
    while i > 1usize {
        i -= 1usize
        if name[i] == 46u8 { return present(i) }
    }
    none
}

pub type PathBuf { v: OsString }

pub const fn new_path_buf(): PathBuf { PathBuf(OsString(vec.new<u8>())) }
pub fn path_buf_with_capacity(capacity: usize): PathBuf {
    PathBuf(OsString(vec.with_capacity<u8>(capacity)))
}

pub fn path_buf_from_bytes(read bytes: [u8]): PathBuf {
    var v = vec.with_capacity<u8>(bytes.len())
    v.extend_from_slice(bytes)
    PathBuf(OsString(v))
}

pub fn path_buf_from_text(read text: Text): PathBuf { path_buf_from_bytes(text.as_bytes()) }

extend PathBuf {
    pub static const fn new(): PathBuf { new_path_buf() }
    pub static fn with_capacity(capacity: usize): PathBuf {
        path_buf_with_capacity(capacity)
    }
    pub fn as_path(): read Path from self { path(self.v.as_bytes()) }
    pub mut fn as_mut_path(): mut Path from self {
        let fat = core.ptr.from_mut(self.v.v.as_mut_slice())
        let view = unsafe { core.mem.transmute<ptr<mut Path>>(fat) }
        unsafe { mut *view }
    }
    pub fn as_os_str(): read OsStr from self { self.v.as_os_str() }
    pub mut fn as_mut_os_str(): mut OsStr from self { self.v.as_mut_os_str() }
    pub mut fn as_mut_os_string(): mut OsString from self { mut self.v }
    pub fn as_bytes(): read [u8] from self { self.v.as_bytes() }
    pub fn capacity(): usize { self.v.capacity() }
    pub fn is_empty(): bool { self.v.is_empty() }
    pub fn is_absolute(): bool { self.as_path().is_absolute() }
    pub fn has_root(): bool { self.as_path().has_root() }
    pub fn is_relative(): bool { self.as_path().is_relative() }
    pub fn components<region r>(
        receiver read self: PathBuf from r
    ): Components<region r> {
        self.as_path().components()
    }
    pub fn iter<region r>(receiver read self: PathBuf from r): Iter<region r> {
        self.as_path().iter()
    }
    pub fn ancestors<region r>(
        receiver read self: PathBuf from r
    ): Ancestors<region r> {
        self.as_path().ancestors()
    }
    pub fn to_str(): (read Text from self)? { self.as_path().to_str() }
    pub fn to_string_lossy(): String { self.as_path().to_string_lossy() }
    pub fn display<region r>(receiver read self: PathBuf from r): ffi.Display<region r> {
        self.as_path().display()
    }
    pub fn to_path_buf(): PathBuf { path_buf_from_bytes(self.v.as_bytes()) }
    pub take fn into_boxed_path(): Box<Path> {
        let bytes = self.v.into_encoded_bytes().into_boxed_slice()
        let raw = bytes.into_raw()
        // Path is a single unsized byte-slice field, preserving the allocation
        // and length metadata used by Box<[u8]>.
        let path_pointer = unsafe {
            core.mem.transmute<ptr<mut Path>>(raw.0)
        }
        unsafe { package.alloc.boxed.from_raw_in(path_pointer, raw.1) }
    }
    pub take fn leak(): mut Path from static {
        let bytes = self.v.into_encoded_bytes().leak()
        let fat = core.ptr.from_mut(bytes)
        let view = unsafe { core.mem.transmute<ptr<mut Path>>(fat) }
        unsafe { mut *view }
    }
    pub take fn into_os_string(): OsString { self.v }
    pub take fn into_string(): String throws FromUtf8Error {
        try self.v.into_string()
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
        self.v.shrink_to(minimum)
    }

    // Appends a component, adding a separator when needed; an absolute `p`
    // replaces the whole path.
    pub mut fn push(read input: PathInput): Unit {
        let p = input.as_path()
        if p.is_absolute() {
            self.v.clear()
        } else if self.v.len() > 0usize && !is_sep(self.v.v[self.v.len() - 1usize]) {
            self.v.v.push(47u8)
        }
        self.v.v.extend_from_slice(p.as_bytes())
    }

    // Removes the final component; false when there was none to remove.
    pub mut fn pop(): bool {
        let keep = match self.as_path().parent() {
            present(p) => present(p.as_bytes().len()),
            none => none
        }
        match keep {
            present(n) => { self.v.v.truncate(n); true },
            none => false
        }
    }

    pub mut fn set_file_name(read name: PathInput): bool {
        if self.as_path().file_name().is_present() { let _ = self.pop() }
        self.push(name)
        true
    }

    pub mut fn set_extension(read extension: OsStr): bool {
        validate_extension(extension)
        let bytes = self.v.as_bytes()
        let end = match final_name_end(bytes) {
            present(end) => end,
            none => { return false }
        }
        let name_start = last_start(bytes, end)
        let name = unsafe { slice.subslice_unchecked(bytes, name_start, end) }
        match last_dot(name) {
            present(dot) => self.v.v.truncate(name_start + dot),
            none => self.v.v.truncate(end)
        }
        let ext = extension.as_bytes()
        if ext.len() > 0usize {
            self.v.v.push(46u8)
            self.v.v.extend_from_slice(ext)
        }
        true
    }

    pub mut fn add_extension(read extension: OsStr): Unit {
        validate_extension(extension)
        let ext = extension.as_bytes()
        if ext.len() > 0usize {
            let end = match final_name_end(self.v.as_bytes()) {
                present(end) => end,
                none => { return }
            }
            self.v.v.truncate(end)
            self.v.v.push(46u8)
            self.v.v.extend_from_slice(ext)
        }
    }

    pub fn same(read other: PathBuf): bool { ffi.bytes_equal(self.v.as_bytes(), other.as_bytes()) }
    pub fn file_name(): (read OsStr from self)? { self.as_path().file_name() }
    pub fn file_stem(): (read OsStr from self)? { self.as_path().file_stem() }
    pub fn file_prefix(): (read OsStr from self)? { self.as_path().file_prefix() }
    pub fn extension(): (read OsStr from self)? { self.as_path().extension() }
    pub fn parent(): (read Path from self)? { self.as_path().parent() }
    pub fn join(read other: PathInput): PathBuf { self.as_path().join(other) }
    pub fn starts_with(read prefix: Path): bool { self.as_path().starts_with(prefix) }
    pub fn ends_with(read suffix: Path): bool { self.as_path().ends_with(suffix) }
    pub fn strip_prefix(read prefix: Path): read Path from self throws StripPrefixError {
        try self.as_path().strip_prefix(prefix)
    }
    pub fn with_file_name(read name: PathInput): PathBuf { self.as_path().with_file_name(name) }
    pub fn with_extension(read extension: OsStr): PathBuf { self.as_path().with_extension(extension) }
    pub fn with_added_extension(read extension: OsStr): PathBuf { self.as_path().with_added_extension(extension) }
}

extend Path implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}
extend Text implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}
extend PathBuf implements PathInput {
    fn as_path(): read Path from self { path(self.v.as_bytes()) }
}
extend OsStr implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}
extend OsString implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}
extend String implements PathInput {
    fn as_path(): read Path from self { path(self.as_bytes()) }
}

// Value types duplicate by copy; owners clone their buffers.
extend PathBuf implements Clone {
    fn clone(): PathBuf { PathBuf(self.v.clone()) }
}

extend PathBuf implements Borrow<Path> {
    fn borrow(): read Path from self { self.as_path() }
}
extend PathBuf implements Deref {
    type Target = Path
    fn deref(): read Path from self { self.as_path() }
}
extend PathBuf implements DerefMut {
    mut fn deref_mut(): mut Path from self { self.as_mut_path() }
}
extend PathBuf implements AsRef<Path> {
    fn as_ref(): read Path from self { self.as_path() }
}
extend PathBuf implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.as_os_str() }
}
extend OsStr implements AsRef<Path> {
    fn as_ref(): read Path from self { path(self.as_bytes()) }
}
extend OsString implements AsRef<Path> {
    fn as_ref(): read Path from self { path(self.as_bytes()) }
}
extend PathBuf implements package.core.borrow.AsMut<Path> {
    mut fn as_mut(): mut Path from self { self.as_mut_path() }
}
extend PathBuf implements PartialEq {
    fn eq(read other: PathBuf): bool { self.as_path() == other.as_path() }
}
extend PathBuf implements PartialEq<Path> {
    fn eq(read other: Path): bool { self.as_path() == other }
}
extend<region r> PathBuf implements PartialEq<read Path from r> {
    fn eq(read other: read Path from r): bool { self.as_path() == other }
}
extend PathBuf implements PartialEq<OsString> {
    fn eq(read other: OsString): bool {
        self.as_path() == path_from_os_str(other.as_os_str())
    }
}
extend PathBuf implements PartialEq<OsStr> {
    fn eq(read other: OsStr): bool {
        self.as_path() == path_from_os_str(other)
    }
}
extend PathBuf implements Eq {}
extend PathBuf implements PartialOrd {
    fn partial_cmp(read other: PathBuf): Ordering? {
        present(self.as_path().cmp(other.as_path()))
    }
}
extend PathBuf implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        present(self.as_path().cmp(other))
    }
}
extend<region r> PathBuf implements PartialOrd<read Path from r> {
    fn partial_cmp(read other: read Path from r): Ordering? {
        present(self.as_path().cmp(other))
    }
}
extend PathBuf implements PartialOrd<OsString> {
    fn partial_cmp(read other: OsString): Ordering? {
        present(self.as_path().cmp(path_from_os_str(other.as_os_str())))
    }
}
extend PathBuf implements PartialOrd<OsStr> {
    fn partial_cmp(read other: OsStr): Ordering? {
        present(self.as_path().cmp(path_from_os_str(other)))
    }
}
extend PathBuf implements PartialEq<String> {
    fn eq(read other: String): bool {
        self.as_path() == path_from_text(other.as_text())
    }
}
extend PathBuf implements PartialOrd<String> {
    fn partial_cmp(read other: String): Ordering? {
        present(self.as_path().cmp(path_from_text(other.as_text())))
    }
}
extend PathBuf implements PartialEq<Text> {
    fn eq(read other: Text): bool {
        self.as_path() == path_from_text(other)
    }
}
extend PathBuf implements PartialOrd<Text> {
    fn partial_cmp(read other: Text): Ordering? {
        present(self.as_path().cmp(path_from_text(other)))
    }
}
extend OsStr implements PartialEq<Path> {
    fn eq(read other: Path): bool {
        path_from_os_str(self) == other
    }
}
extend OsStr implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        present(path_from_os_str(self).cmp(other))
    }
}
extend OsStr implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool {
        path_from_os_str(self) == other.as_path()
    }
}
extend OsStr implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        present(path_from_os_str(self).cmp(other.as_path()))
    }
}
extend OsString implements PartialEq<Path> {
    fn eq(read other: Path): bool {
        path_from_os_str(self.as_os_str()) == other
    }
}
extend OsString implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        present(path_from_os_str(self.as_os_str()).cmp(other))
    }
}
extend OsString implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool {
        path_from_os_str(self.as_os_str()) == other.as_path()
    }
}
extend OsString implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        present(path_from_os_str(self.as_os_str()).cmp(other.as_path()))
    }
}
extend PathBuf implements Ord {
    fn cmp(read other: PathBuf): Ordering { self.as_path().cmp(other.as_path()) }
}
extend PathBuf implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { hash_path(self.as_path(), mut state) }
}
extend PathBuf implements Default {
    static fn default(): PathBuf { new_path_buf() }
}
extend PathBuf implements From<OsString> {
    static fn from(take value: OsString): PathBuf {
        PathBuf(value)
    }
}
extend PathBuf implements From<String> {
    static fn from(take value: String): PathBuf {
        PathBuf(ffi.os_string_from_vec(value.into_bytes()))
    }
}
extend PathBuf implements From<Box<Path>> {
    static fn from(take value: Box<Path>): PathBuf {
        let raw = value.into_raw()
        // The inverse cast preserves the same byte-slice layout and metadata.
        let bytes_pointer = unsafe {
            core.mem.transmute<ptr<mut [u8]>>(raw.0)
        }
        let byte_box: Box<[u8]> = unsafe {
            package.alloc.boxed.from_raw_in(bytes_pointer, raw.1)
        }
        PathBuf(ffi.os_string_from_vec(List<u8>.(From<Box<[u8]>>).from(take byte_box)))
    }
}
extend<region r> read Path from r implements OwnedIterable {
    type Item = read OsStr from r
    type IntoIter = Iter<region r>
    take fn into_iter(): Iter<region r> { self.iter() }
}
extend<region r> read PathBuf from r implements OwnedIterable {
    type Item = read OsStr from r
    type IntoIter = Iter<region r>
    take fn into_iter(): Iter<region r> { self.iter() }
}
extend<region r> PathBuf implements From<BorrowedOrOwned<region r, Path>> {
    static fn from(take value: BorrowedOrOwned<region r, Path>): PathBuf {
        value.into_owned()
    }
}
extend<region r> Path implements PartialEq<BorrowedOrOwned<region r, Path>> {
    fn eq(read other: BorrowedOrOwned<region r, Path>): bool {
        Path.(PartialEq<Path>).eq(self, other.as_ref())
    }
}
extend<region r> Path implements PartialOrd<BorrowedOrOwned<region r, Path>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, Path>): Ordering? {
        present(self.cmp(other.as_ref()))
    }
}
extend<region r> PathBuf implements PartialEq<BorrowedOrOwned<region r, Path>> {
    fn eq(read other: BorrowedOrOwned<region r, Path>): bool {
        self.as_path() == other.as_ref()
    }
}
extend<region r> PathBuf implements PartialOrd<BorrowedOrOwned<region r, Path>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, Path>): Ordering? {
        present(self.as_path().cmp(other.as_ref()))
    }
}
extend<region r> Path implements PartialEq<BorrowedOrOwned<region r, OsStr>> {
    fn eq(read other: BorrowedOrOwned<region r, OsStr>): bool {
        Path.(PartialEq<Path>).eq(self, path_from_os_str(other.as_ref()))
    }
}
extend<region r> Path implements PartialOrd<BorrowedOrOwned<region r, OsStr>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, OsStr>): Ordering? {
        present(self.cmp(path_from_os_str(other.as_ref())))
    }
}
extend<region r> PathBuf implements PartialEq<BorrowedOrOwned<region r, OsStr>> {
    fn eq(read other: BorrowedOrOwned<region r, OsStr>): bool {
        self.as_path() == path_from_os_str(other.as_ref())
    }
}
extend<region r> PathBuf implements PartialOrd<BorrowedOrOwned<region r, OsStr>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, OsStr>): Ordering? {
        present(self.as_path().cmp(path_from_os_str(other.as_ref())))
    }
}
extend<region r> OsStr implements PartialEq<BorrowedOrOwned<region r, Path>> {
    fn eq(read other: BorrowedOrOwned<region r, Path>): bool {
        path_from_os_str(self) == other.as_ref()
    }
}
extend<region r> OsStr implements PartialOrd<BorrowedOrOwned<region r, Path>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, Path>): Ordering? {
        present(path_from_os_str(self).cmp(other.as_ref()))
    }
}
extend<region r> OsString implements PartialEq<BorrowedOrOwned<region r, Path>> {
    fn eq(read other: BorrowedOrOwned<region r, Path>): bool {
        path_from_os_str(self.as_os_str()) == other.as_ref()
    }
}
extend<region r> OsString implements PartialOrd<BorrowedOrOwned<region r, Path>> {
    fn partial_cmp(read other: BorrowedOrOwned<region r, Path>): Ordering? {
        present(path_from_os_str(self.as_os_str()).cmp(other.as_ref()))
    }
}
extend Box<Path> implements From<PathBuf> {
    static fn from(take value: PathBuf): Box<Path> {
        value.into_boxed_path()
    }
}
extend<region r> Box<Path> implements From<read Path from r> {
    static fn from(take value: read Path from r): Box<Path> {
        value.to_path_buf().into_boxed_path()
    }
}
extend<region r> Box<Path> implements From<mut Path from r> {
    static fn from(take value: mut Path from r): Box<Path> {
        value.to_path_buf().into_boxed_path()
    }
}
extend<region r> Box<Path> implements From<BorrowedOrOwned<region r, Path>> {
    static fn from(take value: BorrowedOrOwned<region r, Path>): Box<Path> {
        value.into_owned().into_boxed_path()
    }
}
extend Rc<Path> implements From<PathBuf> {
    static fn from(take value: PathBuf): Rc<Path> {
        Rc<Path>.(From<Box<Path>>).from(value.into_boxed_path())
    }
}
extend<region r> Rc<Path> implements From<read Path from r> {
    static fn from(take value: read Path from r): Rc<Path> {
        Rc<Path>.(From<PathBuf>).from(value.to_path_buf())
    }
}
extend<region r> Rc<Path> implements From<mut Path from r> {
    static fn from(take value: mut Path from r): Rc<Path> {
        Rc<Path>.(From<PathBuf>).from(value.to_path_buf())
    }
}
extend Arc<Path> implements From<PathBuf> {
    static fn from(take value: PathBuf): Arc<Path> {
        Arc<Path>.(From<Box<Path>>).from(value.into_boxed_path())
    }
}
extend<region r> Arc<Path> implements From<read Path from r> {
    static fn from(take value: read Path from r): Arc<Path> {
        Arc<Path>.(From<PathBuf>).from(value.to_path_buf())
    }
}
extend<region r> Arc<Path> implements From<mut Path from r> {
    static fn from(take value: mut Path from r): Arc<Path> {
        Arc<Path>.(From<PathBuf>).from(value.to_path_buf())
    }
}
extend<region r, T: PathInput + unsized> PathBuf implements From<read T from r> {
    static fn from(take value: read T from r): PathBuf {
        path_buf_from_bytes(value.as_path().as_bytes())
    }
}
extend OsString implements From<PathBuf> {
    static fn from(take value: PathBuf): OsString {
        value.into_os_string()
    }
}
extend PathBuf implements package.core.text.FromStr {
    type Error = Never
    static fn from_str(read input: Text): PathBuf throws Never { path_buf_from_text(input) }
}
extend<P: PathInput> PathBuf implements ExtendItems<P> {
    mut fn extend<I: OwnedIterable<Item = P>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(item) => self.push(item.as_path()),
                none => { break }
            }
        }
    }
}
extend<P: PathInput> PathBuf implements FromItems<P> {
    static fn from_iter<I: OwnedIterable<Item = P>>(take items: I): PathBuf {
        var result = new_path_buf()
        PathBuf.(ExtendItems<P>).extend(mut result, items)
        result
    }
}
extend PathBuf implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        let display = self.to_string_lossy()
        var debug = try f.debug_tuple("PathBuf")
        try debug.field(display.as_text())
        try debug.finish()
    }
}
extend package.alloc.string.String implements AsRef<Path> {
    fn as_ref(): read Path from self { path(self.as_bytes()) }
}
extend package.alloc.string.String implements PartialEq<Path> {
    fn eq(read other: Path): bool {
        path_from_text(self.as_text()) == other
    }
}
extend package.alloc.string.String implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool {
        path_from_text(self.as_text()) == other.as_path()
    }
}
extend package.alloc.string.String implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        present(path_from_text(self.as_text()).cmp(other))
    }
}
extend package.alloc.string.String implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        present(path_from_text(self.as_text()).cmp(other.as_path()))
    }
}

extend<region r> Path implements PartialEq<read OsStr from r> {
    fn eq(read other: read OsStr from r): bool {
        Path.(PartialEq<OsStr>).eq(read self, *other)
    }
}
extend<region r> Path implements PartialOrd<read OsStr from r> {
    fn partial_cmp(read other: read OsStr from r): Ordering? {
        Path.(PartialOrd<OsStr>).partial_cmp(read self, *other)
    }
}
extend<region r> PathBuf implements PartialEq<read OsStr from r> {
    fn eq(read other: read OsStr from r): bool {
        Path.(PartialEq<OsStr>).eq(self.as_path(), *other)
    }
}
extend<region r> PathBuf implements PartialOrd<read OsStr from r> {
    fn partial_cmp(read other: read OsStr from r): Ordering? {
        Path.(PartialOrd<OsStr>).partial_cmp(self.as_path(), *other)
    }
}
extend<region r> OsStr implements PartialEq<read Path from r> {
    fn eq(read other: read Path from r): bool {
        Path.(PartialEq).eq(path_from_os_str(read self), *other)
    }
}
extend<region r> OsStr implements PartialOrd<read Path from r> {
    fn partial_cmp(read other: read Path from r): Ordering? {
        Path.(PartialOrd).partial_cmp(path_from_os_str(read self), *other)
    }
}
extend<region r> OsString implements PartialEq<read Path from r> {
    fn eq(read other: read Path from r): bool {
        Path.(PartialEq).eq(path_from_os_str(self.as_os_str()), *other)
    }
}
extend<region r> OsString implements PartialOrd<read Path from r> {
    fn partial_cmp(read other: read Path from r): Ordering? {
        Path.(PartialOrd).partial_cmp(path_from_os_str(self.as_os_str()), *other)
    }
}
extend<region r> read Path from r implements PartialEq<OsStr> {
    fn eq(read other: OsStr): bool { Path.(PartialEq<OsStr>).eq(*self, other) }
}
extend<region r> read Path from r implements PartialOrd<OsStr> {
    fn partial_cmp(read other: OsStr): Ordering? {
        Path.(PartialOrd<OsStr>).partial_cmp(*self, other)
    }
}
extend<region r> read Path from r implements PartialEq<OsString> {
    fn eq(read other: OsString): bool { Path.(PartialEq<OsString>).eq(*self, other) }
}
extend<region r> read Path from r implements PartialOrd<OsString> {
    fn partial_cmp(read other: OsString): Ordering? {
        Path.(PartialOrd<OsString>).partial_cmp(*self, other)
    }
}
extend<region r> read Path from r implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool { Path.(PartialEq<PathBuf>).eq(*self, other) }
}
extend<region r> read Path from r implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        Path.(PartialOrd<PathBuf>).partial_cmp(*self, other)
    }
}
extend<region r> read OsStr from r implements PartialEq<Path> {
    fn eq(read other: Path): bool { OsStr.(PartialEq<Path>).eq(*self, other) }
}
extend<region r> read OsStr from r implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        OsStr.(PartialOrd<Path>).partial_cmp(*self, other)
    }
}
extend<region r> read OsStr from r implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool { OsStr.(PartialEq<PathBuf>).eq(*self, other) }
}
extend<region r> read OsStr from r implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        OsStr.(PartialOrd<PathBuf>).partial_cmp(*self, other)
    }
}
extend<region r, region s> read Path from r implements PartialEq<BorrowedOrOwned<region s, Path>> {
    fn eq(read other: BorrowedOrOwned<region s, Path>): bool {
        Path.(PartialEq).eq(*self, other.as_ref())
    }
}
extend<region r, region s> read Path from r implements PartialOrd<BorrowedOrOwned<region s, Path>> {
    fn partial_cmp(read other: BorrowedOrOwned<region s, Path>): Ordering? {
        Path.(PartialOrd).partial_cmp(*self, other.as_ref())
    }
}
extend<region r, region s> read Path from r implements PartialEq<BorrowedOrOwned<region s, OsStr>> {
    fn eq(read other: BorrowedOrOwned<region s, OsStr>): bool {
        Path.(PartialEq<OsStr>).eq(*self, other.as_ref())
    }
}
extend<region r, region s> read Path from r implements PartialOrd<BorrowedOrOwned<region s, OsStr>> {
    fn partial_cmp(read other: BorrowedOrOwned<region s, OsStr>): Ordering? {
        Path.(PartialOrd<OsStr>).partial_cmp(*self, other.as_ref())
    }
}
extend<region r, region s> read OsStr from r implements PartialEq<BorrowedOrOwned<region s, Path>> {
    fn eq(read other: BorrowedOrOwned<region s, Path>): bool {
        Path.(PartialEq).eq(path_from_os_str(*self), other.as_ref())
    }
}
extend<region r, region s> read OsStr from r implements PartialOrd<BorrowedOrOwned<region s, Path>> {
    fn partial_cmp(read other: BorrowedOrOwned<region s, Path>): Ordering? {
        Path.(PartialOrd).partial_cmp(path_from_os_str(*self), other.as_ref())
    }
}
