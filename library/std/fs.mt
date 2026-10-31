// Files and directories on the POSIX layer shared by macOS and Linux. A
// successful write is not a durability guarantee (`File.sync_all` is).
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.string.String
import package.core.text.Text
import package.core.outcome
import super.ffi
import super.ffi.{OsStr, OsString}
import super.io
import super.io.{Error, ErrorKind, Reader, Writer}
import super.path.{Path, PathBuf, PathInput}
import super.sys
import super.time.SystemTime

extern "C" {
    unsafe fn fsync(fd: i32): i32;
    unsafe fn ftruncate(fd: i32, length: i64): i32;
    unsafe fn dup(fd: i32): i32;
    unsafe fn fchmod(fd: i32, mode: u32): i32;
    unsafe fn link(old: ptr<read u8>, new: ptr<read u8>): i32;
    unsafe fn symlink(target: ptr<read u8>, link_path: ptr<read u8>): i32;
    unsafe fn readlink(path: ptr<read u8>, buffer: ptr<mut u8>, size: usize): isize;
    unsafe fn chmod(path: ptr<read u8>, mode: u32): i32;
    unsafe fn realpath(path: ptr<read u8>, resolved: ptr<mut u8>): ptr<mut u8>;
    unsafe fn free(memory: ptr<mut u8>): Unit;
}

// An open file; the descriptor is closed when the value is dropped.
pub type File {
    fd: i32
    drop {
        if self.fd >= 0 { let closed = unsafe { sys.close(self.fd) } }
    }
}

pub copy enum SeekFrom { Start(u64), End(i64), Current(i64) }

pub copy enum FileType { File, Directory, Symlink, Other }

type RealPathBuffer {
    p: ptr<mut u8>
    drop { unsafe { free(self.p) } }
}

pub copy type Permissions { mode: u32 }

extend Permissions {
    pub fn mode(): u32 { self.mode }
    pub fn readonly(): bool { (self.mode & 146u32) == 0u32 }
    pub mut fn set_readonly(readonly: bool): Unit {
        if readonly {
            self.mode = self.mode & 3949u32
        } else {
            self.mode = self.mode | 128u32
        }
    }
}

pub copy type Metadata {
    size: u64
    kind: FileType
    mode: u32
    modified_secs: i64
    modified_nanos: u32
}

extend Metadata {
    pub fn len(): u64 { self.size }
    pub fn file_type(): FileType { self.kind }
    pub fn is_file(): bool { match self.kind { FileType.File => true, _ => false } }
    pub fn is_dir(): bool { match self.kind { FileType.Directory => true, _ => false } }
    pub fn is_symlink(): bool { match self.kind { FileType.Symlink => true, _ => false } }
    // Permission bits (`st_mode & 0o7777`).
    pub fn permissions(): Permissions { Permissions(self.mode) }
    pub fn modified(): SystemTime { super.time.system_time_from_parts(self.modified_secs, self.modified_nanos) }
}

fn file_type_from(code: i64): FileType {
    if code == 0i64 { FileType.File } else if code == 1i64 { FileType.Directory } else if code == 2i64 { FileType.Symlink } else { FileType.Other }
}

fn metadata_from(info: read [i64; 5]): Metadata {
    Metadata(info[0usize] as u64, file_type_from(info[1usize]), info[2usize] as u32, info[3usize], info[4usize] as u32)
}

fn stat_path(p: read Path, follow: i32): Metadata throws Error {
    let c = try ffi.cstring(p.as_bytes())
    var info = [0i64; 5]
    let r = unsafe { sys.mettle_rt_stat(c.as_ptr(), -1, follow, core.ptr.from_mut(info).cast<i64>()) }
    if r != 0 { throw io.last_os_error() }
    metadata_from(info)
}

// Follows symbolic links.
pub fn metadata(input: read PathInput): Metadata throws Error { try stat_path(input.as_path(), 1) }
pub fn symlink_metadata(input: read PathInput): Metadata throws Error { try stat_path(input.as_path(), 0) }

pub fn exists(input: read PathInput): bool {
    let r = capture metadata(input)
    r.is_success()
}

pub fn try_exists(input: read PathInput): bool throws Error {
    let result = capture metadata(input)
    match take result {
        success(_) => true,
        failure(error) => {
            if error.kind().is(ErrorKind.NotFound) { false } else { throw error }
        }
    }
}

pub fn canonicalize(input: read PathInput): PathBuf throws Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    let resolved = unsafe { realpath(c.as_ptr(), core.ptr.null_mut<u8>()) }
    if resolved == core.ptr.null_mut<u8>() { throw io.last_os_error() }
    let owner = RealPathBuffer(resolved)
    let bytes = unsafe { sys.bytes_from_c(owner.p.cast_const()) }
    super.path.path_buf_from_bytes(bytes.as_slice())
}

pub fn read_link(input: read PathInput): OsString throws Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    var capacity = 256usize
    var result = vec.with_capacity<u8>(capacity)
    while true {
        result.resize(capacity, 0u8)
        let count = unsafe { readlink(c.as_ptr(), sys.data_mut(result.as_mut_slice()), capacity) }
        if count < 0isize { throw io.last_os_error() }
        if (count as usize) < capacity {
            result.truncate(count as usize)
            return ffi.os_string_from_vec(result)
        }
        capacity *= 2usize
    }
}

// Open-mode builder; `open` fails with the OS error (`NotFound`,
// `AlreadyExists`, ...) unchanged.
pub copy type OpenOptions { flags: i32; mode: u32 }

pub fn open_options(): OpenOptions { OpenOptions(0, 438u32) }

extend OpenOptions {
    pub static fn new(): OpenOptions { open_options() }
    pub mut fn read(on: bool): Unit { self.set_read(on) }
    pub mut fn write(on: bool): Unit { self.set_write(on) }
    pub mut fn append(on: bool): Unit { self.set_append(on) }
    pub mut fn truncate(on: bool): Unit { self.set_truncate(on) }
    pub mut fn create(on: bool): Unit { self.set_create(on) }
    pub mut fn create_new(on: bool): Unit { self.set_create_new(on) }
    pub mut fn set_read(on: bool): Unit { self.set(sys.open_read(), on) }
    pub mut fn set_write(on: bool): Unit { self.set(sys.open_write(), on) }
    pub mut fn set_append(on: bool): Unit { self.set(sys.open_append(), on) }
    pub mut fn set_truncate(on: bool): Unit { self.set(sys.open_truncate(), on) }
    pub mut fn set_create(on: bool): Unit { self.set(sys.open_create(), on) }
    pub mut fn set_create_new(on: bool): Unit { self.set(sys.open_create_new(), on) }
    // Permission bits for a newly created file (before the umask).
    pub mut fn set_mode(bits: u32): Unit { self.mode = bits }
    mut fn set(flag: i32, on: bool): Unit {
        if on { self.flags = self.flags | flag } else { self.flags = self.flags & (-1 - flag) }
    }
    pub fn open(input: read PathInput): File throws Error {
        let c = try ffi.cstring(input.as_path().as_bytes())
        let fd = unsafe { sys.mettle_rt_open(c.as_ptr(), self.flags, self.mode) }
        if fd < 0 { throw io.last_os_error() }
        File(fd)
    }
}

pub type DirBuilder { recursive: bool; mode: u32 }

pub fn dir_builder(): DirBuilder { DirBuilder(false, 511u32) }

extend DirBuilder {
    pub static fn new(): DirBuilder { dir_builder() }
    pub mut fn recursive(on: bool): Unit { self.recursive = on }
    pub mut fn mode(bits: u32): Unit { self.mode = bits }
    pub fn create(input: read PathInput): Unit throws Error {
        if self.recursive {
            try create_dirs(input.as_path(), self.mode)
        } else {
            let c = try ffi.cstring(input.as_path().as_bytes())
            if unsafe { sys.mkdir(c.as_ptr(), self.mode) } != 0 { throw io.last_os_error() }
        }
    }
}

pub fn open(input: read PathInput): File throws Error {
    var o = open_options()
    o.set_read(true)
    try o.open(input)
}

// Creates or truncates for writing.
pub fn create(input: read PathInput): File throws Error {
    var o = open_options()
    o.set_write(true)
    o.set_create(true)
    o.set_truncate(true)
    try o.open(input)
}

extend File {
    pub fn as_raw_fd(): i32 { self.fd }
    pub fn try_clone(): File throws Error {
        let cloned = unsafe { dup(self.fd) }
        if cloned < 0 { throw io.last_os_error() }
        File(cloned)
    }
    pub fn metadata(): Metadata throws Error {
        var info = [0i64; 5]
        let r = unsafe { sys.mettle_rt_stat(core.ptr.null<u8>(), self.fd, 1, core.ptr.from_mut(info).cast<i64>()) }
        if r != 0 { throw io.last_os_error() }
        metadata_from(info)
    }
    pub mut fn seek(pos: SeekFrom): u64 throws Error {
        var whence = 0
        var offset = 0i64
        match pos {
            SeekFrom.Start(n) => { whence = 0; offset = n as i64 },
            SeekFrom.Current(n) => { whence = 1; offset = n },
            SeekFrom.End(n) => { whence = 2; offset = n }
        }
        let r = unsafe { sys.lseek(self.fd, offset, whence) }
        if r < 0i64 { throw io.last_os_error() }
        r as u64
    }
    pub fn sync_all(): Unit throws Error {
        if unsafe { fsync(self.fd) } != 0 { throw io.last_os_error() }
    }
    pub fn sync_data(): Unit throws Error {
        if unsafe { fsync(self.fd) } != 0 { throw io.last_os_error() }
    }
    pub fn set_permissions(permissions: Permissions): Unit throws Error {
        if unsafe { fchmod(self.fd, permissions.mode()) } != 0 { throw io.last_os_error() }
    }
    pub fn set_len(length: u64): Unit throws Error {
        if unsafe { ftruncate(self.fd, length as i64) } != 0 { throw io.last_os_error() }
    }
}

extend File implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error { try io.read_fd(self.fd, buf) }
}

extend File implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error { try io.write_fd(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

// The whole file.
pub fn read_bytes(input: read PathInput): List<u8> throws Error {
    var f = try open(input)
    var out = vec.new<u8>()
    let n = try f.read_to_end(out)
    out
}

pub fn read(input: read PathInput): List<u8> throws Error { try read_bytes(input) }

// The whole file as text; ill-formed UTF-8 fails with `InvalidData`.
pub fn read_to_string(input: read PathInput): String throws Error {
    let bytes = try read_bytes(input)
    let decoded = capture package.alloc.string.from_utf8(bytes)
    match take decoded {
        success(s) => s,
        failure(e) => throw io.from_kind(ErrorKind.InvalidData)
    }
}

// Replaces the file's contents.
pub fn write(input: read PathInput, bytes: read [u8]): Unit throws Error {
    var f = try create(input)
    try f.write_all(bytes)
}

pub fn copy(from: read PathInput, to: read PathInput): u64 throws Error {
    let source_metadata = try metadata(from)
    if try_exists(to) {
        let from_path = try canonicalize(from)
        let to_path = try canonicalize(to)
        if from_path.as_path().same(to_path.as_path()) {
            throw io.from_kind(ErrorKind.InvalidInput)
        }
    }
    var source = try open(from)
    var destination = try create(to)
    var buffer = [0u8; 4096]
    var total = 0u64
    while true {
        let count = try source.read_some(buffer)
        if count == 0usize { break }
        let bytes = unsafe { package.core.slice.subslice_unchecked(buffer, 0usize, count) }
        try destination.write_all(bytes)
        total += count as u64
    }
    let target_mode = source_metadata.permissions()
    try set_permissions(to, target_mode)
    total
}

pub fn set_permissions(input: read PathInput, permissions: Permissions): Unit throws Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    if unsafe { chmod(c.as_ptr(), permissions.mode()) } != 0 { throw io.last_os_error() }
}

pub fn hard_link(existing: read PathInput, link_path: read PathInput): Unit throws Error {
    let old = try ffi.cstring(existing.as_path().as_bytes())
    let new = try ffi.cstring(link_path.as_path().as_bytes())
    if unsafe { link(old.as_ptr(), new.as_ptr()) } != 0 { throw io.last_os_error() }
}

pub fn soft_link(target: read PathInput, link_path: read PathInput): Unit throws Error {
    let target_bytes = try ffi.cstring(target.as_path().as_bytes())
    let link_bytes = try ffi.cstring(link_path.as_path().as_bytes())
    if unsafe { symlink(target_bytes.as_ptr(), link_bytes.as_ptr()) } != 0 {
        throw io.last_os_error()
    }
}

fn path_call(p: read Path, which: i32, mode: u32): Unit throws Error {
    let c = try ffi.cstring(p.as_bytes())
    var r = 0
    if which == 0 { r = unsafe { sys.unlink(c.as_ptr()) } }
    else if which == 1 { r = unsafe { sys.rmdir(c.as_ptr()) } }
    else { r = unsafe { sys.mkdir(c.as_ptr(), mode) } }
    if r != 0 { throw io.last_os_error() }
}

pub fn remove_file(input: read PathInput): Unit throws Error { try path_call(input.as_path(), 0, 0u32) }
pub fn remove_dir(input: read PathInput): Unit throws Error { try path_call(input.as_path(), 1, 0u32) }
pub fn create_dir(input: read PathInput): Unit throws Error { try path_call(input.as_path(), 2, 511u32) }

pub fn remove_dir_all(input: read PathInput): Unit throws Error {
    try remove_tree(input.as_path())
}

fn remove_tree(p: read Path): Unit throws Error {
    let details = try symlink_metadata(p)
    if !details.is_dir() {
        try remove_file(p)
        return
    }
    var entries = try read_dir(p)
    while true {
        match try entries.next_entry() {
            present(entry) => {
                let entry_path = entry.path()
                let kind = try symlink_metadata(entry_path.as_path())
                if kind.is_dir() {
                    try remove_tree(entry_path.as_path())
                } else {
                    try remove_file(entry_path.as_path())
                }
            },
            none => { break }
        }
    }
    try remove_dir(p)
}

// Creates the path and any missing parents; an existing directory is not an error.
pub fn create_dir_all(input: read PathInput): Unit throws Error { try create_dirs(input.as_path(), 511u32) }

fn create_dirs(p: read Path, mode: u32): Unit throws Error {
    let made = capture path_call(p, 2, mode)
    match take made {
        success(u) => { return },
        failure(e) => {
            if e.kind().is(ErrorKind.AlreadyExists) {
                let found = capture metadata(p)
                if found.is_success() { return }
                throw e
            }
            if !e.kind().is(ErrorKind.NotFound) { throw e }
            match p.parent() {
                present(parent) => { try create_dirs(parent, mode) },
                none => { throw e }
            }
            try path_call(p, 2, mode)
        }
    }
}

pub fn rename(old: read PathInput, new: read PathInput): Unit throws Error {
    let a = try ffi.cstring(old.as_path().as_bytes())
    let b = try ffi.cstring(new.as_path().as_bytes())
    if unsafe { sys.rename(a.as_ptr(), b.as_ptr()) } != 0 { throw io.last_os_error() }
}

// One directory entry: its name and the directory it was listed from.
pub type DirEntry { name: OsString; dir: PathBuf }

extend DirEntry {
    pub fn file_name(): read OsStr from self { self.name.as_os_str() }
    pub fn file_type(): FileType throws Error {
        try symlink_metadata(self.path()).file_type()
    }
    pub fn metadata(): Metadata throws Error { try metadata(self.path()) }
    pub fn path(): PathBuf {
        var p = self.dir.as_path().to_path_buf()
        p.push(super.path.path_from_os_str(self.name.as_os_str()))
        p
    }
}

// Open directory listing; `.` and `..` are skipped and the order is the
// operating system's. Closed on drop.
pub type ReadDir {
    handle: ptr<mut u8>
    dir: PathBuf
    finished: bool
    drop {
        if self.handle != core.ptr.null_mut<u8>() { let closed = unsafe { sys.closedir(self.handle) } }
    }
}

pub fn read_dir(input: read PathInput): ReadDir throws Error {
    let p = input.as_path()
    let c = try ffi.cstring(p.as_bytes())
    let h = unsafe { sys.opendir(c.as_ptr()) }
    if h == core.ptr.null_mut<u8>() { throw io.last_os_error() }
    ReadDir(h, p.to_path_buf(), false)
}

extend ReadDir {
    // EOF or a read error permanently ends this listing.
    pub mut fn next_entry(): DirEntry? throws Error {
        if self.finished { return none }
        let name = unsafe { sys.mettle_rt_readdir(self.handle) }
        if name == core.ptr.null<u8>() {
            let code = sys.errno()
            self.finished = true
            if code != 0 { throw io.from_raw_os_error(code) }
            return none
        }
        let bytes = unsafe { sys.bytes_from_c(name) }
        present(DirEntry(ffi.os_string_from_vec(bytes), self.dir.as_path().to_path_buf()))
    }
}

// Yields each entry; a read failure is yielded once and ends the iteration.
extend ReadDir implements package.core.iter.Iterator {
    type Item = (DirEntry throws Error);
    mut fn next(): (DirEntry throws Error)? {
        if self.finished { return none }
        let entry = capture self.next_entry()
        match take entry {
            success(found) => match take found {
                present(value) => present(success(value)),
                none => { self.finished = true; none }
            },
            failure(error) => { self.finished = true; present(failure(error)) }
        }
    }
}

extend Path {
    pub fn canonicalize(): PathBuf throws Error { try super.fs.canonicalize(self) }
    pub fn metadata(): Metadata throws Error { try super.fs.metadata(self) }
    pub fn symlink_metadata(): Metadata throws Error { try super.fs.symlink_metadata(self) }
    pub fn exists(): bool { super.fs.exists(self) }
    pub fn try_exists(): bool throws Error { try super.fs.try_exists(self) }
    pub fn is_file(): bool {
        match capture super.fs.metadata(self) {
            success(value) => value.is_file(),
            failure(_) => false
        }
    }
    pub fn is_dir(): bool {
        match capture super.fs.metadata(self) {
            success(value) => value.is_dir(),
            failure(_) => false
        }
    }
    pub fn is_symlink(): bool {
        match capture super.fs.symlink_metadata(self) {
            success(value) => value.is_symlink(),
            failure(_) => false
        }
    }
    pub fn read_dir(): ReadDir throws Error { try super.fs.read_dir(self) }
    pub fn read_link(): OsString throws Error { try super.fs.read_link(self) }
}

extend PathBuf {
    pub fn canonicalize(): PathBuf throws Error { try super.fs.canonicalize(self.as_path()) }
    pub fn metadata(): Metadata throws Error { try super.fs.metadata(self.as_path()) }
    pub fn symlink_metadata(): Metadata throws Error {
        try super.fs.symlink_metadata(self.as_path())
    }
    pub fn exists(): bool { super.fs.exists(self.as_path()) }
    pub fn try_exists(): bool throws Error { try super.fs.try_exists(self.as_path()) }
    pub fn is_file(): bool { self.as_path().is_file() }
    pub fn is_dir(): bool { self.as_path().is_dir() }
    pub fn is_symlink(): bool { self.as_path().is_symlink() }
    pub fn read_dir(): ReadDir throws Error { try super.fs.read_dir(self.as_path()) }
    pub fn read_link(): OsString throws Error { try super.fs.read_link(self.as_path()) }
}
