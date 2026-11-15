// Paths over operating-system strings: `Path` is the unsized view and
// `PathBuf` the owner. Native bytes round-trip losslessly; Windows components
// also recognize drive, UNC, device and verbatim prefixes.
import alloc.vec
import alloc.vec.List
import alloc.boxed.Heap
import alloc.arc.Shared
import alloc.rc.LocalShared
import alloc.borrow.BorrowedOrOwned
import alloc.collections.TryReserveError
import alloc.string.String
import alloc.string.FromUtf8Error
import core.iter.{BidirectionalIterator, Iterator}
import core.text.Text
import core.slice
import super.ffi
import super.ffi.{OsStr, OsString}
import core.clone.Clone
import core.borrow.{AsRef, Borrow, OwnedType, ToOwned}
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.From
import core.default.Default
import core.hash.{Hash, Hasher}
import core.iter.{FromItems, ExtendItems, OwnedIterable}
import core.ops.{Deref, DerefMut}
import core.fmt.{Debug, Formatter, Error}

pub type Path { bytes: [u8] }

pub copy type StripPrefixError {}
extend StripPrefixError implements Clone {
    fn clone(): StripPrefixError { self }
}

extend StripPrefixError implements core.cmp.PartialEq {
    fn eq(read other: StripPrefixError): bool { true }
}
extend StripPrefixError implements core.cmp.Eq {}

extend StripPrefixError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("StripPrefixError") }
}
extend StripPrefixError implements core.fmt.Display {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("prefix not found") }
}
extend StripPrefixError implements core.error.Error {}

@cfg(target_os = "windows")
pub copy enum Component<region r> {
    Prefix(PrefixComponent<region r>),
    RootDir,
    CurDir,
    ParentDir,
    Normal(read OsStr from r)
}

@cfg(not(target_os = "windows"))
pub copy enum Component<region r> {
    RootDir,
    CurDir,
    ParentDir,
    Normal(read OsStr from r)
}

@cfg(target_os = "windows")
pub copy enum Prefix<region r> {
    Verbatim(read OsStr from r),
    VerbatimUNC(read OsStr from r, read OsStr from r),
    VerbatimDisk(u8),
    DeviceNS(read OsStr from r),
    UNC(read OsStr from r, read OsStr from r),
    Disk(u8)
}

@cfg(target_os = "windows")
pub copy type PrefixComponent<region r> {
    raw: read OsStr from r
    parsed: Prefix<r>
}

pub type Components<region r> {
    path: read Path from r
    front: usize
    back: usize
    prefix_end: usize
    prefix_pending: bool
    root_pending: bool
    leading_cur_dir: bool
    verbatim_body: bool
}

pub type Iter<region r> { components: Components<region r> }

pub copy type Ancestors<region r> { current: read Path from r; finished: bool }
extend<region r> Ancestors<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Ancestors")
        try debug.field("current", self.current)
        try debug.field("finished", self.finished)
        try debug.finish()
    }
}
@cfg(not(target_os = "windows"))
extend<region r> Component<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            Component.RootDir => { try f.write_str("RootDir") },
            Component.CurDir => { try f.write_str("CurDir") },
            Component.ParentDir => { try f.write_str("ParentDir") },
            Component.Normal(name) => {
                var tuple = try f.debug_tuple("Normal")
                try tuple.field(name)
                try tuple.finish()
            }
        }
    }
}

@cfg(target_os = "windows")
extend<region r> Component<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            Component.Prefix(prefix) => {
                var tuple = try f.debug_tuple("Prefix")
                try tuple.field(prefix)
                try tuple.finish()
            },
            Component.RootDir => { try f.write_str("RootDir") },
            Component.CurDir => { try f.write_str("CurDir") },
            Component.ParentDir => { try f.write_str("ParentDir") },
            Component.Normal(name) => {
                var tuple = try f.debug_tuple("Normal")
                try tuple.field(name)
                try tuple.finish()
            }
        }
    }
}

@cfg(target_os = "windows")
extend<region r> Prefix<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            Prefix.Verbatim(prefix) => {
                var tuple = try f.debug_tuple("Verbatim")
                try tuple.field(prefix)
                try tuple.finish()
            },
            Prefix.VerbatimUNC(server, share) => {
                var tuple = try f.debug_tuple("VerbatimUNC")
                try tuple.field(server)
                try tuple.field(share)
                try tuple.finish()
            },
            Prefix.VerbatimDisk(drive) => {
                var tuple = try f.debug_tuple("VerbatimDisk")
                try tuple.field(drive)
                try tuple.finish()
            },
            Prefix.DeviceNS(name) => {
                var tuple = try f.debug_tuple("DeviceNS")
                try tuple.field(name)
                try tuple.finish()
            },
            Prefix.UNC(server, share) => {
                var tuple = try f.debug_tuple("UNC")
                try tuple.field(server)
                try tuple.field(share)
                try tuple.finish()
            },
            Prefix.Disk(drive) => {
                var tuple = try f.debug_tuple("Disk")
                try tuple.field(drive)
                try tuple.finish()
            }
        }
    }
}

@cfg(target_os = "windows")
extend<region r> PrefixComponent<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("PrefixComponent")
        try debug.field("raw", self.as_os_str())
        try debug.field("kind", self.kind())
        try debug.finish()
    }
}

extend<region r> Components<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Components")
        try debug.field("path", self.as_path())
        try debug.finish()
    }
}
extend<region r> Iter<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Iter")
        try debug.field("components", read self.components)
        try debug.finish()
    }
}

fn path_unchecked(read bytes: [u8]): read Path from bytes {
    let fat = core.ptr.from_ref(bytes)
    let view = unsafe { core.mem.transmute<ptr<read Path>>(fat) }
    unsafe { read *view }
}

pub fn path(read bytes: [u8]): read Path from bytes {
    ffi.validate_os_bytes(bytes)
    path_unchecked(bytes)
}

pub fn path_from_text(read text: Text): read Path from text { path_unchecked(text.as_bytes()) }

pub fn path_from_os_str(read s: OsStr): read Path from s { path_unchecked(s.as_bytes()) }

// Anything that views as a native path without allocation or conversion.
// Hosted path-taking functions accept `read PathInput`, so callers pass a
// `Path`, `PathBuf`, `OsStr` or `OsString` directly; the borrow never outlives
// the source. On POSIX the path is the unmodified OS-string bytes.
pub interface PathInput {
    fn as_path(): read Path from self;
}

@cfg(target_os = "windows")
fn is_sep(b: u8): bool { b == 47u8 || b == 92u8 }

@cfg(not(target_os = "windows"))
fn is_sep(b: u8): bool { b == 47u8 }

fn is_component_sep(b: u8, verbatim: bool): bool {
    if verbatim { b == 92u8 } else { is_sep(b) }
}

@cfg(target_os = "windows")
fn main_separator(): u8 { 92u8 }

@cfg(not(target_os = "windows"))
fn main_separator(): u8 { 47u8 }

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

fn has_leading_cur_dir(read bytes: [u8], start: usize): bool {
    bytes.len() > start && bytes[start] == 46u8 &&
        (bytes.len() == start + 1usize || is_sep(bytes[start + 1usize]))
}

fn checked_part(read bytes: [u8], start: usize, end: usize): read [u8] {
    match slice.subslice(bytes, start, end) {
        present(part) => part,
        none => { core.panic.panic("path component bounds invariant failed") }
    }
}

@cfg(target_os = "windows")
fn component_tag<region r>(component: Component<region r>): u8 {
    match component {
        Component.Prefix(_) => 0u8,
        Component.RootDir => 1u8,
        Component.CurDir => 2u8,
        Component.ParentDir => 3u8,
        Component.Normal(_) => 4u8
    }
}

@cfg(not(target_os = "windows"))
fn component_tag<region r>(component: Component<region r>): u8 {
    match component {
        Component.RootDir => 0u8,
        Component.CurDir => 1u8,
        Component.ParentDir => 2u8,
        Component.Normal(_) => 3u8
    }
}

fn compare_component(left: Component, right: Component): Ordering {
    let left_tag = component_tag(left)
    let right_tag = component_tag(right)
    if left_tag != right_tag {
        return if left_tag < right_tag { Ordering.Less } else { Ordering.Greater }
    }
    compare_component_values(left, right)
}

fn same_component(left: Component, right: Component): bool {
    compare_component(left, right) == Ordering.Equal
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
        if is_sep(bytes[index]) { core.panic.panic("path extension contains a separator") }
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

@cfg(target_os = "windows")
fn ascii_letter(b: u8): bool {
    (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8)
}

@cfg(target_os = "windows")
fn uppercase_ascii(b: u8): u8 {
    if b >= 97u8 && b <= 122u8 { b - 32u8 } else { b }
}

@cfg(target_os = "windows")
fn starts_with(read bytes: [u8], read prefix: [u8]): bool {
    if bytes.len() < prefix.len() { return false }
    var index = 0usize
    while index < prefix.len() {
        if bytes[index] != prefix[index] { return false }
        index += 1usize
    }
    true
}

@cfg(target_os = "windows")
fn prefix_component<region r>(
    read bytes: [u8] from r,
    start: usize,
    end: usize,
    parsed: Prefix<r>
): PrefixComponent<region r> {
    PrefixComponent(ffi.os_str(checked_part(bytes, start, end)), parsed)
}

@cfg(target_os = "windows")
fn parse_prefix<region r>(read bytes: [u8] from r): PrefixComponent<region r>? {
    let len = bytes.len()
    let verbatim_start: [u8; 4] = [92u8, 92u8, 63u8, 92u8]
    let verbatim_unc_start: [u8; 8] = [92u8, 92u8, 63u8, 92u8, 85u8, 78u8, 67u8, 92u8]

    if starts_with(bytes, verbatim_unc_start.as_slice()) {
        let server_start = 8usize
        var server_end = server_start
        while server_end < len && bytes[server_end] != 92u8 { server_end += 1usize }
        let share_start = if server_end < len { server_end + 1usize } else { len }
        var share_end = share_start
        while share_end < len && bytes[share_end] != 92u8 { share_end += 1usize }
        let server = ffi.os_str(checked_part(bytes, server_start, server_end))
        let share = ffi.os_str(checked_part(bytes, share_start, share_end))
        let raw_end = share_end
        return present(prefix_component(
            bytes,
            0usize,
            raw_end,
            Prefix.VerbatimUNC(server, share)
        ))
    }

    if starts_with(bytes, verbatim_start.as_slice()) {
        if len >= 6usize && ascii_letter(bytes[4usize]) &&
            bytes[5usize] == 58u8 &&
            (len == 6usize || is_sep(bytes[6usize])) {
            return present(prefix_component(
                bytes,
                0usize,
                6usize,
                Prefix.VerbatimDisk(uppercase_ascii(bytes[4usize]))
            ))
        }

        var end = 4usize
        while end < len && bytes[end] != 92u8 { end += 1usize }
        let name = ffi.os_str(checked_part(bytes, 4usize, end))
        return present(prefix_component(bytes, 0usize, end, Prefix.Verbatim(name)))
    }

    if len >= 4usize && is_sep(bytes[0usize]) && is_sep(bytes[1usize]) &&
        bytes[2usize] == 46u8 && is_sep(bytes[3usize]) && len > 4usize &&
        !is_sep(bytes[4usize]) {
        var end = 4usize
        while end < len && !is_sep(bytes[end]) { end += 1usize }
        let device = ffi.os_str(checked_part(bytes, 4usize, end))
        return present(prefix_component(bytes, 0usize, end, Prefix.DeviceNS(device)))
    }

    if len >= 2usize && is_sep(bytes[0usize]) && is_sep(bytes[1usize]) {
        let server_start = 2usize
        var server_end = server_start
        while server_end < len && !is_sep(bytes[server_end]) { server_end += 1usize }
        if server_end > server_start && server_end < len {
            let share_start = server_end + 1usize
            if share_start < len && !is_sep(bytes[share_start]) {
                var share_end = share_start
                while share_end < len && !is_sep(bytes[share_end]) {
                    share_end += 1usize
                }
                let server = ffi.os_str(checked_part(bytes, server_start, server_end))
                let share = ffi.os_str(checked_part(bytes, share_start, share_end))
                return present(prefix_component(
                    bytes,
                    0usize,
                    share_end,
                    Prefix.UNC(server, share)
                ))
            }
        }
    }

    if len >= 2usize && ascii_letter(bytes[0usize]) && bytes[1usize] == 58u8 {
        return present(prefix_component(
            bytes,
            0usize,
            2usize,
            Prefix.Disk(uppercase_ascii(bytes[0usize]))
        ))
    }
    none
}

type ComponentPathInfo {
    prefix_end: usize
    prefix_pending: bool
    root_pending: bool
    leading_cur_dir: bool
    verbatim_body: bool
    has_prefix: bool
    has_root: bool
}

@cfg(target_os = "windows")
fn component_path_info(read bytes: [u8]): ComponentPathInfo {
    let parsed = parse_prefix(bytes)
    let prefix_end = match parsed {
        present(prefix) => prefix.raw.as_bytes().len(),
        none => 0usize
    }
    let has_prefix = parsed.is_present()
    let verbatim_body = match parsed {
        present(prefix) => prefix.parsed.is_verbatim(),
        none => false
    }
    let physical_root = prefix_end < bytes.len() && is_sep(bytes[prefix_end])
    let implied_root = match parsed {
        present(prefix) => match prefix.parsed {
            Prefix.Disk(_) => false,
            _ => true
        },
        none => false
    }
    let has_root = physical_root || implied_root
    ComponentPathInfo(
        prefix_end,
        has_prefix,
        physical_root || (implied_root && !verbatim_body),
        !has_root && has_leading_cur_dir(bytes, prefix_end),
        verbatim_body,
        has_prefix,
        has_root
    )
}

@cfg(not(target_os = "windows"))
fn component_path_info(read bytes: [u8]): ComponentPathInfo {
    let root = bytes.len() > 0usize && is_sep(bytes[0usize])
    ComponentPathInfo(0usize, false, root, !root && has_leading_cur_dir(bytes, 0usize),
        false, false, root)
}

@cfg(target_os = "windows")
fn path_prefix_component<region r>(read bytes: [u8] from r): Component<region r>? {
    match parse_prefix(bytes) {
        present(prefix) => present(Component.Prefix(prefix)),
        none => none
    }
}

@cfg(not(target_os = "windows"))
fn path_prefix_component<region r>(read bytes: [u8] from r): Component<region r>? { none }

@cfg(target_os = "windows")
fn path_is_absolute(read bytes: [u8]): bool {
    let info = component_path_info(bytes)
    info.has_prefix && info.has_root
}

@cfg(not(target_os = "windows"))
fn path_is_absolute(read bytes: [u8]): bool { component_path_info(bytes).has_root }

fn path_has_root(read bytes: [u8]): bool { component_path_info(bytes).has_root }

@cfg(target_os = "windows")
fn component_is_root_or_prefix(component: Component): bool {
    match component {
        Component.RootDir | Component.Prefix(_) => true,
        _ => false
    }
}

@cfg(not(target_os = "windows"))
fn component_is_root_or_prefix(component: Component): bool {
    match component {
        Component.RootDir => true,
        _ => false
    }
}

@cfg(target_os = "windows")
fn prefix_tag<region r>(prefix: Prefix<r>): u8 {
    match prefix {
        Prefix.Verbatim(_) => 0u8,
        Prefix.VerbatimUNC(_, _) => 1u8,
        Prefix.VerbatimDisk(_) => 2u8,
        Prefix.DeviceNS(_) => 3u8,
        Prefix.UNC(_, _) => 4u8,
        Prefix.Disk(_) => 5u8
    }
}

@cfg(target_os = "windows")
fn compare_prefix<region r>(left: Prefix<r>, right: Prefix<r>): Ordering {
    let left_tag = prefix_tag(left)
    let right_tag = prefix_tag(right)
    if left_tag != right_tag {
        return if left_tag < right_tag { Ordering.Less } else { Ordering.Greater }
    }
    match left {
        Prefix.Verbatim(a) => match right {
            Prefix.Verbatim(b) => compare_bytes(a.as_bytes(), b.as_bytes()),
            _ => Ordering.Equal
        },
        Prefix.VerbatimUNC(a_server, a_share) => match right {
            Prefix.VerbatimUNC(b_server, b_share) => {
                let server_order = compare_bytes(a_server.as_bytes(), b_server.as_bytes())
                if server_order != Ordering.Equal {
                    server_order
                } else {
                    compare_bytes(a_share.as_bytes(), b_share.as_bytes())
                }
            },
            _ => Ordering.Equal
        },
        Prefix.VerbatimDisk(a) => match right {
            Prefix.VerbatimDisk(b) => {
                if a < b { Ordering.Less } else if a > b { Ordering.Greater } else { Ordering.Equal }
            },
            _ => Ordering.Equal
        },
        Prefix.DeviceNS(a) => match right {
            Prefix.DeviceNS(b) => compare_bytes(a.as_bytes(), b.as_bytes()),
            _ => Ordering.Equal
        },
        Prefix.UNC(a_server, a_share) => match right {
            Prefix.UNC(b_server, b_share) => {
                let server_order = compare_bytes(a_server.as_bytes(), b_server.as_bytes())
                if server_order != Ordering.Equal {
                    server_order
                } else {
                    compare_bytes(a_share.as_bytes(), b_share.as_bytes())
                }
            },
            _ => Ordering.Equal
        },
        Prefix.Disk(a) => match right {
            Prefix.Disk(b) => {
                if a < b { Ordering.Less } else if a > b { Ordering.Greater } else { Ordering.Equal }
            },
            _ => Ordering.Equal
        }
    }
}

@cfg(target_os = "windows")
fn hash_prefix<H: Hasher, region r>(prefix: Prefix<r>, mut state: H): Unit {
    state.write_u8(prefix_tag(prefix))
    match prefix {
        Prefix.Verbatim(name) | Prefix.DeviceNS(name) => {
            state.write_usize(name.len())
            state.write(name.as_bytes())
        },
        Prefix.VerbatimUNC(server, share) | Prefix.UNC(server, share) => {
            state.write_usize(server.len())
            state.write(server.as_bytes())
            state.write_usize(share.len())
            state.write(share.as_bytes())
        },
        Prefix.VerbatimDisk(letter) | Prefix.Disk(letter) => state.write_u8(letter)
    }
}

@cfg(target_os = "windows")
fn compare_component_values(left: Component, right: Component): Ordering {
    match left {
        Component.Prefix(a) => match right {
            Component.Prefix(b) => compare_prefix(a.parsed, b.parsed),
            _ => Ordering.Equal
        },
        Component.Normal(a) => match right {
            Component.Normal(b) => compare_bytes(a.as_bytes(), b.as_bytes()),
            _ => Ordering.Equal
        },
        _ => Ordering.Equal
    }
}

@cfg(not(target_os = "windows"))
fn compare_component_values(left: Component, right: Component): Ordering {
    match left {
        Component.Normal(a) => match right {
            Component.Normal(b) => compare_bytes(a.as_bytes(), b.as_bytes()),
            _ => Ordering.Equal
        },
        _ => Ordering.Equal
    }
}

@cfg(target_os = "windows")
fn hash_component<H: Hasher>(component: Component, mut state: H): Unit {
    state.write_u8(component_tag(component))
    match component {
        Component.Prefix(prefix) => hash_prefix(prefix.parsed, mut state),
        Component.Normal(name) => {
            state.write_usize(name.len())
            state.write(name.as_bytes())
        },
        _ => {}
    }
}

@cfg(not(target_os = "windows"))
fn hash_component<H: Hasher>(component: Component, mut state: H): Unit {
    state.write_u8(component_tag(component))
    match component {
        Component.Normal(name) => {
            state.write_usize(name.len())
            state.write(name.as_bytes())
        },
        _ => {}
    }
}

@cfg(target_os = "windows")
extend<region r> Prefix<region r> {
    pub fn is_verbatim(): bool {
        match self {
            Prefix.Verbatim(_) | Prefix.VerbatimUNC(_, _) | Prefix.VerbatimDisk(_) => true,
            _ => false
        }
    }
}

@cfg(target_os = "windows")
extend<region r> Prefix<region r> implements Clone {
    fn clone(): Prefix<region r> { self }
}

@cfg(target_os = "windows")
extend<region r> Prefix<region r> implements PartialEq {
    fn eq(read other: Prefix<region r>): bool {
        compare_prefix(self, other) == Ordering.Equal
    }
}

@cfg(target_os = "windows")
extend<region r> Prefix<region r> implements Eq {}

@cfg(target_os = "windows")
extend<region r> Prefix<region r> implements PartialOrd {
    fn partial_cmp(read other: Prefix<region r>): Ordering? {
        present(compare_prefix(self, other))
    }
}

@cfg(target_os = "windows")
extend<region r> Prefix<region r> implements Ord {
    fn cmp(read other: Prefix<region r>): Ordering { compare_prefix(self, other) }
}

@cfg(target_os = "windows")
extend<region r> PrefixComponent<region r> {
    pub fn as_os_str(): read OsStr from r { self.raw }
    pub fn kind(): Prefix<region r> { self.parsed }
}

@cfg(target_os = "windows")
extend<region r> PrefixComponent<region r> implements Clone {
    fn clone(): PrefixComponent<region r> { self }
}

@cfg(target_os = "windows")
extend<region r> PrefixComponent<region r> implements PartialEq {
    fn eq(read other: PrefixComponent<region r>): bool {
        self.parsed == other.parsed
    }
}

@cfg(target_os = "windows")
extend<region r> PrefixComponent<region r> implements Eq {}

@cfg(target_os = "windows")
extend<region r> PrefixComponent<region r> implements PartialOrd {
    fn partial_cmp(read other: PrefixComponent<region r>): Ordering? {
        present(self.parsed.cmp(other.parsed))
    }
}

fn compare_components(read left: Path, read right: Path): Ordering {
    var a = left.components()
    var b = right.components()
    while true {
        match a.next() {
            present(left_component) => match b.next() {
                present(right_component) => {
                    let order = compare_component(left_component, right_component)
                    if order != Ordering.Equal { return order }
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
                hash_component(component, mut state)
            },
            none => { break }
        }
    }
    state.write_u8(255u8)
}

@cfg(target_os = "windows")
fn component_as_os_str<region r>(component: Component<region r>): read OsStr from r {
    match component {
        Component.Prefix(prefix) => prefix.as_os_str(),
        Component.RootDir => ffi.os_str("\\".as_bytes()),
        Component.CurDir => ffi.os_str(".".as_bytes()),
        Component.ParentDir => ffi.os_str("..".as_bytes()),
        Component.Normal(name) => name
    }
}

@cfg(not(target_os = "windows"))
fn component_as_os_str<region r>(component: Component<region r>): read OsStr from r {
    match component {
        Component.RootDir => ffi.os_str("/".as_bytes()),
        Component.CurDir => ffi.os_str(".".as_bytes()),
        Component.ParentDir => ffi.os_str("..".as_bytes()),
        Component.Normal(name) => name
    }
}

extend<region r> Component<region r> {
    pub fn as_os_str(receiver self: Component<region r>): read OsStr from r {
        component_as_os_str(self)
    }
}

@cfg(target_os = "windows")
fn clone_component<region r>(component: Component<region r>): Component<region r> {
    match component {
        Component.Prefix(prefix) => Component.Prefix(prefix.clone()),
        Component.RootDir => Component<region r>.RootDir,
        Component.CurDir => Component<region r>.CurDir,
        Component.ParentDir => Component<region r>.ParentDir,
        Component.Normal(name) => Component.Normal(name)
    }
}

@cfg(not(target_os = "windows"))
fn clone_component<region r>(component: Component<region r>): Component<region r> {
    match component {
        Component.RootDir => Component<region r>.RootDir,
        Component.CurDir => Component<region r>.CurDir,
        Component.ParentDir => Component<region r>.ParentDir,
        Component.Normal(name) => Component.Normal(name)
    }
}
extend<region r> Component<region r> implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.as_os_str() }
}
extend<region r> Component<region r> implements AsRef<Path> {
    fn as_ref(): read Path from self { path_from_os_str(self.as_os_str()) }
}

extend<region r> Component<region r> implements core.clone.Clone {
    fn clone(): Component<region r> { clone_component(self) }
}

extend<region r> Component<region r> implements PartialEq {
    fn eq(read other: Component<region r>): bool {
        same_component(self, other)
    }
}
extend<region r> Component<region r> implements Eq {}
extend<region r> Component<region r> implements PartialOrd {
    fn partial_cmp(read other: Component<region r>): Ordering? {
        present(compare_component(self, other))
    }
}
extend<region r> Component<region r> implements Ord {
    fn cmp(read other: Component<region r>): Ordering {
        compare_component(self, other)
    }
}

extend<region r> Components<region r> {
    pub fn as_path(): read Path from r {
        let bytes = self.path.as_bytes()
        var start = if self.prefix_pending { 0usize } else { self.front }
        var end = self.back
        let body_start = if start > self.prefix_end { start } else { self.prefix_end }

        if self.front > self.prefix_end && !self.root_pending {
            while start < end && is_component_sep(bytes[start], self.verbatim_body) {
                start += 1usize
            }
            var trimming = !self.verbatim_body
            while trimming && start < end {
                var part_end = start
                while part_end < end && !is_component_sep(bytes[part_end], false) {
                    part_end += 1usize
                }
                if is_dot(bytes, start, part_end) &&
                    !(self.leading_cur_dir && start == self.prefix_end) {
                    start = part_end
                    while start < end && is_component_sep(bytes[start], false) {
                        start += 1usize
                    }
                } else {
                    trimming = false
                }
            }
        }

        if self.back < bytes.len() {
            while end > body_start && is_component_sep(bytes[end - 1usize], self.verbatim_body) {
                end -= 1usize
            }
            var trimming = !self.verbatim_body
            while trimming && end > body_start {
                var part_start = end
                while part_start > body_start && !is_component_sep(bytes[part_start - 1usize], false) {
                    part_start -= 1usize
                }
                if is_dot(bytes, part_start, end) &&
                    !(self.leading_cur_dir && part_start == self.prefix_end) {
                    end = part_start
                    while end > body_start && is_component_sep(bytes[end - 1usize], false) {
                        end -= 1usize
                    }
                } else {
                    trimming = false
                }
            }
        }

        if self.root_pending && end <= self.prefix_end &&
            self.prefix_end < bytes.len() && is_sep(bytes[self.prefix_end]) {
            end = self.prefix_end + 1usize
        }
        // Dot components consumed from both ends may cross: nothing remains.
        if end < start { end = start }
        path_unchecked(checked_part(bytes, start, end))
    }
}

extend<region r> Components<region r> implements core.clone.Clone {
    fn clone(): Components<region r> {
        Components(
            self.path,
            self.front,
            self.back,
            self.prefix_end,
            self.prefix_pending,
            self.root_pending,
            self.leading_cur_dir,
            self.verbatim_body
        )
    }
}

extend<region r> Components<region r> implements PartialEq {
    fn eq(read other: Components<region r>): bool {
        self.as_path() == other.as_path()
    }
}
extend<region r> Components<region r> implements Eq {}
extend<region r> Components<region r> implements PartialOrd {
    fn partial_cmp(read other: Components<region r>): Ordering? {
        present(self.as_path().cmp(other.as_path()))
    }
}
extend<region r> Components<region r> implements Ord {
    fn cmp(read other: Components<region r>): Ordering {
        self.as_path().cmp(other.as_path())
    }
}
extend<region r> Components<region r> implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.as_path().as_os_str() }
}
extend<region r> Components<region r> implements AsRef<Path> {
    fn as_ref(): read Path from self { self.as_path() }
}

extend<region r> Iter<region r> {
    pub fn as_path(): read Path from r { self.components.as_path() }
}

extend<region r> Iter<region r> implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.as_path().as_os_str() }
}
extend<region r> Iter<region r> implements AsRef<Path> {
    fn as_ref(): read Path from self { self.as_path() }
}

extend<region r> Iter<region r> implements core.clone.Clone {
    fn clone(): Iter<region r> {
        Iter(Components(
            self.components.path,
            self.components.front,
            self.components.back,
            self.components.prefix_end,
            self.components.prefix_pending,
            self.components.root_pending,
            self.components.leading_cur_dir,
            self.components.verbatim_body
        ))
    }
}

extend<region r> Ancestors<region r> implements core.clone.Clone {
    fn clone(): Ancestors<region r> { Ancestors(self.current, self.finished) }
}

extend Path {
    pub static fn new(read input: PathInput): read Path from input {
        input.as_path()
    }
    pub fn as_bytes(): read [u8] from self { read self.bytes }
    pub fn as_os_str(): read OsStr from self { ffi.os_str(read self.bytes) }
    pub mut fn as_mut_os_str(): mut OsStr from self { ffi.os_str_mut(self.bytes) }
    pub fn is_empty(): bool { self.bytes.len() == 0usize }
    pub fn to_str(): (read Text from self)? {
        match core.text.from_utf8(read self.bytes) {
            success(text) => present(text),
            failure(_) => none
        }
    }
    pub fn to_string_lossy(): String { ffi.lossy(read self.bytes) }
    pub fn is_absolute(): bool { path_is_absolute(self.bytes) }
    pub fn has_root(): bool { path_has_root(self.bytes) }
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
        let info = component_path_info(bytes)
        Components(
            read self,
            info.prefix_end,
            bytes.len(),
            info.prefix_end,
            info.prefix_pending,
            info.root_pending,
            info.leading_cur_dir,
            info.verbatim_body
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
            present(component) => {
                if component_is_root_or_prefix(component) {
                    none
                } else {
                    present(components.as_path())
                }
            },
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
extend Text implements PartialEq<Path> {
    fn eq(read other: Path): bool {
        Path.(PartialEq<Text>).eq(other, self)
    }
}
extend Text implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool {
        Path.(PartialEq<Text>).eq(other.as_path(), self)
    }
}
extend<region r> read Text from r implements PartialEq<Path> {
    fn eq(read other: Path): bool {
        Path.(PartialEq<Text>).eq(other, *self)
    }
}
extend<region r> read Text from r implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool {
        Path.(PartialEq<Text>).eq(other.as_path(), *self)
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
extend Path implements AsRef<Path> {
    fn as_ref(): read Path from self { read self }
}
extend Path implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        let display = self.to_string_lossy()
        var debug = try f.debug_tuple("Path")
        try debug.field(display.as_text())
        try debug.finish()
    }
}

extend<region r> Components<region r> implements core.iter.Iterator {
    type Item = Component<region r>
    mut fn next(): Component<region r>? {
        let bytes = self.path.as_bytes()
        if self.prefix_pending {
            self.prefix_pending = false
            return match path_prefix_component(bytes) {
                present(prefix) => present(prefix),
                none => { core.panic.panic("path prefix state invariant failed") }
            }
        }
        if self.root_pending {
            self.root_pending = false
            while self.front < self.back && is_sep(bytes[self.front]) {
                self.front += 1usize
            }
            return present(Component<region r>.RootDir)
        }

        while self.front < self.back {
            while self.front < self.back &&
                is_component_sep(bytes[self.front], self.verbatim_body) {
                self.front += 1usize
            }
            if self.front >= self.back { return none }
            let start = self.front
            while self.front < self.back &&
                !is_component_sep(bytes[self.front], self.verbatim_body) {
                self.front += 1usize
            }
            let end = self.front
            if is_dot(bytes, start, end) {
                if self.verbatim_body {
                    return present(Component<region r>.CurDir)
                }
                if self.leading_cur_dir && start == self.prefix_end {
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

extend<region r> Components<region r> implements core.iter.BidirectionalIterator {
    mut fn next_back(): Component<region r>? {
        let bytes = self.path.as_bytes()
        while true {
            if self.root_pending && self.front == self.prefix_end {
                var root_end = self.prefix_end
                while root_end < self.back && is_sep(bytes[root_end]) {
                    root_end += 1usize
                }
                if root_end == self.back {
                    self.back = self.prefix_end
                    self.front = self.back
                    self.root_pending = false
                    return present(Component<region r>.RootDir)
                }
            }
            while self.back > self.front &&
                is_component_sep(bytes[self.back - 1usize], self.verbatim_body) {
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
                if self.prefix_pending {
                    self.prefix_pending = false
                    return match path_prefix_component(bytes) {
                        present(prefix) => present(prefix),
                        none => { core.panic.panic("path prefix state invariant failed") }
                    }
                }
                return none
            }

            let end = self.back
            var start = end
            while start > self.front &&
                !is_component_sep(bytes[start - 1usize], self.verbatim_body) {
                start -= 1usize
            }
            self.back = start
            if is_dot(bytes, start, end) {
                if self.verbatim_body {
                    return present(Component<region r>.CurDir)
                }
                if self.leading_cur_dir && start == self.prefix_end {
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

extend<region r> Iter<region r> implements core.iter.Iterator {
    type Item = read OsStr from r
    mut fn next(): (read OsStr from r)? {
        match take self.components.next() {
            present(component) => present(component.as_os_str()),
            none => none
        }
    }
}

extend<region r> Iter<region r> implements core.iter.BidirectionalIterator {
    mut fn next_back(): (read OsStr from r)? {
        match take self.components.next_back() {
            present(component) => present(component.as_os_str()),
            none => none
        }
    }
}

extend<region r> Ancestors<region r> implements core.iter.Iterator {
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
    PathBuf(ffi.os_string_from_bytes(bytes))
}

pub fn path_buf_from_text(read text: Text): PathBuf { path_buf_from_bytes(text.as_bytes()) }

extend PathBuf {
    pub static const fn new(): PathBuf { new_path_buf() }
    pub static fn with_capacity(capacity: usize): PathBuf {
        path_buf_with_capacity(capacity)
    }
    pub fn as_path(): read Path from self { path_unchecked(self.v.as_bytes()) }
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
    pub take fn into_heap_path(): Heap<Path> {
        let bytes = self.v.into_encoded_bytes().into_heap_slice()
        let raw = bytes.into_raw()
        // Path is a single unsized byte-slice field, preserving the allocation
        // and length metadata used by Heap<[u8]>.
        let path_pointer = unsafe {
            core.mem.transmute<ptr<mut Path>>(raw.0)
        }
        unsafe { alloc.boxed.from_raw_in(path_pointer, raw.1) }
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
    pub mut fn try_reserve(additional: usize): Unit throws TryReserveError {
        try self.v.try_reserve(additional)
    }
    pub mut fn try_reserve_exact(additional: usize): Unit throws TryReserveError {
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
        let info = component_path_info(p.as_bytes())
        if p.is_absolute() || info.has_prefix {
            self.v.clear()
        } else if info.has_root {
            let base_info = component_path_info(self.v.as_bytes())
            if base_info.has_prefix {
                self.v.v.truncate(base_info.prefix_end)
            } else {
                self.v.clear()
            }
        } else if self.v.len() > 0usize && !is_sep(self.v.v[self.v.len() - 1usize]) {
            self.v.v.push(main_separator())
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
    fn as_path(): read Path from self { path_unchecked(self.as_bytes()) }
}
extend<region r> read [u8] from r implements PathInput {
    fn as_path(): read Path from r { path(*self) }
}
extend<region r, const N: usize> read [u8; N] from r implements PathInput {
    fn as_path(): read Path from r { path(self.as_slice()) }
}
extend<const N: usize> [u8; N] implements PathInput {
    fn as_path(): read Path from self { path(self.as_slice()) }
}
extend Text implements AsRef<Path> {
    fn as_ref(): read Path from self { path(self.as_bytes()) }
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
    fn clone(): PathBuf { PathBuf(OsString.(Clone).clone(self.v)) }
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
extend PathBuf implements core.borrow.AsMut<Path> {
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
        present(Path.(Ord).cmp(self.as_path(), other))
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
        present(Path.(Ord).cmp(path_from_os_str(self), other))
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
        present(Path.(Ord).cmp(path_from_os_str(self.as_os_str()), other))
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
extend PathBuf implements From<Heap<Path>> {
    static fn from(take value: Heap<Path>): PathBuf {
        let raw = value.into_raw()
        // The inverse cast preserves the same byte-slice layout and metadata.
        let bytes_pointer = unsafe {
            core.mem.transmute<ptr<mut [u8]>>(raw.0)
        }
        let byte_box: Heap<[u8]> = unsafe {
            alloc.boxed.from_raw_in(bytes_pointer, raw.1)
        }
        PathBuf(ffi.os_string_from_vec(List<u8>.(From<Heap<[u8]>>).from(take byte_box)))
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
extend Heap<Path> implements From<PathBuf> {
    static fn from(take value: PathBuf): Heap<Path> {
        value.into_heap_path()
    }
}
extend<region r> Heap<Path> implements From<read Path from r> {
    static fn from(take value: read Path from r): Heap<Path> {
        value.to_path_buf().into_heap_path()
    }
}
extend<region r> Heap<Path> implements From<mut Path from r> {
    static fn from(take value: mut Path from r): Heap<Path> {
        value.to_path_buf().into_heap_path()
    }
}
extend<region r> Heap<Path> implements From<BorrowedOrOwned<region r, Path>> {
    static fn from(take value: BorrowedOrOwned<region r, Path>): Heap<Path> {
        value.into_owned().into_heap_path()
    }
}
extend LocalShared<Path> implements From<PathBuf> {
    static fn from(take value: PathBuf): LocalShared<Path> {
        LocalShared<Path>.(From<Heap<Path>>).from(value.into_heap_path())
    }
}
extend<region r> LocalShared<Path> implements From<read Path from r> {
    static fn from(take value: read Path from r): LocalShared<Path> {
        LocalShared<Path>.(From<PathBuf>).from(value.to_path_buf())
    }
}
extend<region r> LocalShared<Path> implements From<mut Path from r> {
    static fn from(take value: mut Path from r): LocalShared<Path> {
        LocalShared<Path>.(From<PathBuf>).from(value.to_path_buf())
    }
}
extend Shared<Path> implements From<PathBuf> {
    static fn from(take value: PathBuf): Shared<Path> {
        Shared<Path>.(From<Heap<Path>>).from(value.into_heap_path())
    }
}
extend<region r> Shared<Path> implements From<read Path from r> {
    static fn from(take value: read Path from r): Shared<Path> {
        Shared<Path>.(From<PathBuf>).from(value.to_path_buf())
    }
}
extend<region r> Shared<Path> implements From<mut Path from r> {
    static fn from(take value: mut Path from r): Shared<Path> {
        Shared<Path>.(From<PathBuf>).from(value.to_path_buf())
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
extend PathBuf implements core.text.FromStr {
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
extend alloc.string.String implements AsRef<Path> {
    fn as_ref(): read Path from self { path(self.as_bytes()) }
}
extend alloc.string.String implements PartialEq<Path> {
    fn eq(read other: Path): bool {
        path_from_text(self.as_text()) == other
    }
}
extend alloc.string.String implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool {
        path_from_text(self.as_text()) == other.as_path()
    }
}
extend alloc.string.String implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        present(Path.(Ord).cmp(path_from_text(self.as_text()), other))
    }
}
extend alloc.string.String implements PartialOrd<PathBuf> {
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
extend<region r> BorrowedOrOwned<region r, Path> implements PartialEq<OsStr> {
    fn eq(read other: OsStr): bool {
        Path.(PartialEq).eq(self.as_ref(), path_from_os_str(other))
    }
}
extend<region r, region s> BorrowedOrOwned<region r, Path>
    implements PartialEq<read OsStr from s> {
    fn eq(read other: read OsStr from s): bool {
        Path.(PartialEq).eq(self.as_ref(), path_from_os_str(*other))
    }
}
extend<region r> BorrowedOrOwned<region r, Path> implements PartialEq<OsString> {
    fn eq(read other: OsString): bool {
        Path.(PartialEq).eq(self.as_ref(), path_from_os_str(other.as_os_str()))
    }
}
extend<region r> BorrowedOrOwned<region r, Path> implements PartialOrd<OsStr> {
    fn partial_cmp(read other: OsStr): Ordering? {
        Path.(PartialOrd).partial_cmp(self.as_ref(), path_from_os_str(other))
    }
}
extend<region r, region s> BorrowedOrOwned<region r, Path>
    implements PartialOrd<read OsStr from s> {
    fn partial_cmp(read other: read OsStr from s): Ordering? {
        Path.(PartialOrd).partial_cmp(self.as_ref(), path_from_os_str(*other))
    }
}
extend<region r> BorrowedOrOwned<region r, Path> implements PartialOrd<OsString> {
    fn partial_cmp(read other: OsString): Ordering? {
        Path.(PartialOrd).partial_cmp(self.as_ref(), path_from_os_str(other.as_os_str()))
    }
}
extend<region r> BorrowedOrOwned<region r, Path> implements PartialEq<Path> {
    fn eq(read other: Path): bool { self.as_ref() == other }
}
extend<region r> BorrowedOrOwned<region r, Path> implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        Path.(PartialOrd).partial_cmp(self.as_ref(), other)
    }
}
extend<region r, region s> BorrowedOrOwned<region r, Path> implements PartialEq<read Path from s> {
    fn eq(read other: read Path from s): bool { self.as_ref() == *other }
}
extend<region r, region s> BorrowedOrOwned<region r, Path> implements PartialOrd<read Path from s> {
    fn partial_cmp(read other: read Path from s): Ordering? {
        Path.(PartialOrd).partial_cmp(self.as_ref(), *other)
    }
}
extend<region r> BorrowedOrOwned<region r, Path> implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool { self.as_ref() == other }
}
extend<region r> BorrowedOrOwned<region r, Path> implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        Path.(PartialOrd).partial_cmp(self.as_ref(), other.as_path())
    }
}
extend<region r> BorrowedOrOwned<region r, OsStr> implements PartialEq<Path> {
    fn eq(read other: Path): bool { path_from_os_str(self.as_ref()) == other }
}
extend<region r> BorrowedOrOwned<region r, OsStr> implements PartialOrd<Path> {
    fn partial_cmp(read other: Path): Ordering? {
        Path.(PartialOrd).partial_cmp(path_from_os_str(self.as_ref()), other)
    }
}
extend<region r, region s> BorrowedOrOwned<region r, OsStr> implements PartialEq<read Path from s> {
    fn eq(read other: read Path from s): bool { path_from_os_str(self.as_ref()) == *other }
}
extend<region r, region s> BorrowedOrOwned<region r, OsStr> implements PartialOrd<read Path from s> {
    fn partial_cmp(read other: read Path from s): Ordering? {
        Path.(PartialOrd).partial_cmp(path_from_os_str(self.as_ref()), *other)
    }
}
extend<region r> BorrowedOrOwned<region r, OsStr> implements PartialEq<PathBuf> {
    fn eq(read other: PathBuf): bool { path_from_os_str(self.as_ref()) == other }
}
extend<region r> BorrowedOrOwned<region r, OsStr> implements PartialOrd<PathBuf> {
    fn partial_cmp(read other: PathBuf): Ordering? {
        Path.(PartialOrd).partial_cmp(
            path_from_os_str(self.as_ref()),
            other.as_path()
        )
    }
}
