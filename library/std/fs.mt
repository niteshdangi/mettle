// Files and directories on the POSIX layer shared by macOS and Linux. A
// successful write is not a durability guarantee (`File.sync_all` is).
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.string.String
import package.core.text.Text
import package.core.outcome
import super.ffi
import super.ffi.OsString
import super.io
import super.io.{Error, ErrorKind, Reader, Writer}
pub import super.io.SeekFrom
import super.path.{Path, PathBuf, PathInput}
import super.sys
import super.time.SystemTime
import package.core.clone.Clone
import package.core.cmp.PartialEq
import package.core.hash.{Hash, Hasher}
import package.core.convert.From
import package.core.fmt
import package.core.error.{Error as CoreError}

extern "C" {
    unsafe fn fsync(fd: i32): i32;
    unsafe fn ftruncate(fd: i32, length: i64): i32;
    unsafe fn flock(fd: i32, operation: i32): i32;
    unsafe fn pread(fd: i32, buffer: ptr<mut u8>, count: usize, offset: i64): isize;
    unsafe fn pwrite(fd: i32, buffer: ptr<read u8>, count: usize, offset: i64): isize;
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

pub enum TryLockError { Error(Error); WouldBlock }

extend TryLockError implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self {
            TryLockError.Error(error) => try Error.(fmt.Display).fmt(error, mut f),
            TryLockError.WouldBlock => try f.write_str("file lock would block")
        }
    }
}

extend TryLockError implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self {
            TryLockError.Error(error) => {
                var debug = try f.debug_tuple("Error")
                try debug.field(error)
                try debug.finish()
            },
            TryLockError.WouldBlock => try f.write_str("WouldBlock")
        }
    }
}

extend TryLockError implements CoreError {
    fn source<region r>(receiver read self: TryLockError from r): (read any CoreError from r)? {
        match self {
            TryLockError.Error(error) => {
                let source: read any CoreError from r = read error
                present(source)
            },
            TryLockError.WouldBlock => none
        }
    }
}

pub copy enum FileType { File, Directory, Symlink, Other }

extend FileType {
    pub fn is_file(): bool { (self as i32) == (FileType.File as i32) }
    pub fn is_dir(): bool { (self as i32) == (FileType.Directory as i32) }
    pub fn is_symlink(): bool { (self as i32) == (FileType.Symlink as i32) }
}

extend FileType implements PartialEq {
    fn eq(read other: FileType): bool { (self as i32) == (other as i32) }
}
extend FileType implements package.core.cmp.Eq {}
extend FileType implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { state.write_u8(self as u8) }
}
extend FileType implements package.core.fmt.Debug {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        match self {
            FileType.File => try f.write_str("File"),
            FileType.Directory => try f.write_str("Directory"),
            FileType.Symlink => try f.write_str("Symlink"),
            FileType.Other => try f.write_str("Other")
        }
    }
}

type RealPathBuffer {
    p: ptr<mut u8>
    drop { unsafe { free(self.p) } }
}

pub copy type Permissions { mode: u32 }

// Unix permission bits, as `chmod` takes them.
pub fn permissions_from_mode(mode: u32): Permissions { Permissions(mode) }

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
    accessed_time: SystemTime?
    created_time: SystemTime?
}

pub copy type FileTimes { accessed: SystemTime?; modified: SystemTime? }

extend FileTimes {
    pub static fn new(): FileTimes { FileTimes(none, none) }
    pub take fn set_accessed(time: SystemTime): FileTimes { FileTimes(present(time), self.modified) }
    pub take fn set_modified(time: SystemTime): FileTimes { FileTimes(self.accessed, present(time)) }
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
    pub fn accessed(): SystemTime throws Error {
        match self.accessed_time {
            present(time) => time,
            none => throw io.from_kind(ErrorKind.Unsupported)
        }
    }
    pub fn created(): SystemTime throws Error {
        match self.created_time {
            present(time) => time,
            none => throw io.from_kind(ErrorKind.Unsupported)
        }
    }
}

fn file_type_from(code: i64): FileType {
    if code == 0i64 { FileType.File } else if code == 1i64 { FileType.Directory } else if code == 2i64 { FileType.Symlink } else { FileType.Other }
}

fn metadata_from(read info: [i64; 10]): Metadata {
    let accessed = if (info[9usize] & 1i64) != 0i64 {
        present(super.time.system_time_from_parts(info[5usize], info[6usize] as u32))
    } else { none }
    let created = if (info[9usize] & 4i64) != 0i64 {
        present(super.time.system_time_from_parts(info[7usize], info[8usize] as u32))
    } else { none }
    Metadata(info[0usize] as u64, file_type_from(info[1usize]), info[2usize] as u32,
        info[3usize], info[4usize] as u32, accessed, created)
}

fn stat_path(read p: Path, follow: i32): Metadata throws Error {
    let c = try ffi.cstring(p.as_bytes())
    var info = [0i64; 10]
    let r = unsafe { sys.mettle_rt_stat_full(c.as_ptr(), -1, follow, core.ptr.from_mut(info).cast<i64>()) }
    if r != 0 { throw io.last_os_error() }
    metadata_from(info)
}

// Follows symbolic links.
pub fn metadata(read input: PathInput): Metadata throws Error { try stat_path(input.as_path(), 1) }
pub fn symlink_metadata(read input: PathInput): Metadata throws Error { try stat_path(input.as_path(), 0) }

pub fn exists(read input: PathInput): bool throws Error { try try_exists(input) }

pub fn try_exists(read input: PathInput): bool throws Error {
    let result = capture metadata(input)
    match take result {
        success(_) => true,
        failure(error) => {
            if error.kind().is(ErrorKind.NotFound) { false } else { throw error }
        }
    }
}

pub fn canonicalize(read input: PathInput): PathBuf throws Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    let resolved = unsafe { realpath(c.as_ptr(), core.ptr.null_mut<u8>()) }
    if resolved == core.ptr.null_mut<u8>() { throw io.last_os_error() }
    let owner = RealPathBuffer(resolved)
    let bytes = unsafe { sys.bytes_from_c(owner.p.cast_const()) }
    super.path.path_buf_from_bytes(bytes.as_slice())
}

pub fn read_link(read input: PathInput): OsString throws Error {
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
    pub mut fn `read`(on: bool): Unit { self.set_read(on) }
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
    pub fn open(read input: PathInput): File throws Error {
        let access_modes = sys.open_read() | sys.open_write() | sys.open_append()
        if (self.flags & access_modes) == 0 {
            throw io.from_kind(ErrorKind.InvalidInput)
        }
        let write = (self.flags & sys.open_write()) != 0
        let append = (self.flags & sys.open_append()) != 0
        let create_new = (self.flags & sys.open_create_new()) != 0
        if !write && !append &&
            (self.flags & (sys.open_create() | sys.open_create_new())) != 0 {
            throw io.from_kind(ErrorKind.InvalidInput)
        }
        if !create_new && (!write || append) && (self.flags & sys.open_truncate()) != 0 {
            throw io.from_kind(ErrorKind.InvalidInput)
        }
        let flags = if create_new {
            self.flags & (-1 - sys.open_truncate())
        } else { self.flags }
        let c = try ffi.cstring(input.as_path().as_bytes())
        let fd = unsafe { sys.mettle_rt_open(c.as_ptr(), flags, self.mode) }
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
    pub fn create(read input: PathInput): Unit throws Error {
        if self.recursive {
            try create_dirs(input.as_path(), self.mode)
        } else {
            let c = try ffi.cstring(input.as_path().as_bytes())
            if unsafe { sys.mkdir(c.as_ptr(), self.mode) } != 0 { throw io.last_os_error() }
        }
    }
}

pub fn open(read input: PathInput): File throws Error {
    var o = open_options()
    o.set_read(true)
    try o.open(input)
}

pub fn create_new(read input: PathInput): File throws Error {
    var o = open_options()
    o.set_write(true)
    o.set_create_new(true)
    try o.open(input)
}

// Creates or truncates for writing.
pub fn create(read input: PathInput): File throws Error {
    var o = open_options()
    o.set_write(true)
    o.set_create(true)
    o.set_truncate(true)
    try o.open(input)
}

extend File {
    pub static fn open(read input: PathInput): File throws Error { try super.fs.open(input) }
    pub static fn create(read input: PathInput): File throws Error { try super.fs.create(input) }
    pub static fn create_new(read input: PathInput): File throws Error { try super.fs.create_new(input) }
    pub static fn options(): OpenOptions { open_options() }
    pub fn as_raw_fd(): i32 { self.fd }
    pub fn lock(): Unit throws Error { try file_lock(self.fd, 2) }
    pub fn lock_shared(): Unit throws Error { try file_lock(self.fd, 1) }
    pub fn try_lock(): Unit throws TryLockError { try try_file_lock(self.fd, 6) }
    pub fn try_lock_shared(): Unit throws TryLockError { try try_file_lock(self.fd, 5) }
    pub fn unlock(): Unit throws Error { try file_lock(self.fd, 8) }
    pub fn try_clone(): File throws Error {
        let cloned = unsafe { sys.mettle_rt_dup(self.fd) }
        if cloned < 0 { throw io.last_os_error() }
        File(cloned)
    }
    pub fn metadata(): Metadata throws Error {
        var info = [0i64; 10]
        let r = unsafe { sys.mettle_rt_stat_full(core.ptr.null<u8>(), self.fd, 1, core.ptr.from_mut(info).cast<i64>()) }
        if r != 0 { throw io.last_os_error() }
        metadata_from(info)
    }
    pub fn set_times(take times: FileTimes): Unit throws Error {
        var mask = 0u32
        let accessed = match times.accessed {
            present(time) => { mask |= 1u32; time },
            none => super.time.unix_epoch()
        }
        let modified = match times.modified {
            present(time) => { mask |= 2u32; time },
            none => super.time.unix_epoch()
        }
        while true {
            let status = unsafe {
                sys.mettle_rt_file_set_times(self.fd, mask,
                    accessed.unix_secs(), accessed.subsec_nanos(),
                    modified.unix_secs(), modified.subsec_nanos())
            }
            if status == 0i32 { return }
            let error = io.last_os_error()
            if !error.kind().is(ErrorKind.Interrupted) { throw error }
        }
    }
    pub fn set_modified(time: SystemTime): Unit throws Error {
        try self.set_times(FileTimes.new().set_modified(time))
    }
    pub mut fn seek(pos: SeekFrom): u64 throws Error { try seek_file(self.fd, pos) }
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
        if length > 9223372036854775807u64 {
            throw io.from_kind(ErrorKind.InvalidInput)
        }
        if unsafe { ftruncate(self.fd, length as i64) } != 0 { throw io.last_os_error() }
    }
}

extend File implements From<sys.OwnedFd> {
    static fn from(take descriptor: sys.OwnedFd): File { File(descriptor.into_raw_fd()) }
}

extend sys.OwnedFd implements From<File> {
    static fn from(take file: File): sys.OwnedFd {
        var owned = file
        let fd = owned.fd
        owned.fd = -1
        unsafe { sys.OwnedFd.from_raw_fd(fd) }
    }
}

extend File implements package.core.fmt.Debug {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        var debug = try f.debug_struct("File")
        try debug.field("fd", self.fd)
        try debug.finish()
    }
}

fn file_lock(fd: i32, operation: i32): Unit throws Error {
    while true {
        if unsafe { flock(fd, operation) } == 0 { return }
        let error = io.last_os_error()
        if !error.kind().is(ErrorKind.Interrupted) { throw error }
    }
}

fn try_file_lock(fd: i32, operation: i32): Unit throws TryLockError {
    match take capture file_lock(fd, operation) {
        success(_) => {},
        failure(error) => {
            if error.kind().is(ErrorKind.WouldBlock) { throw TryLockError.WouldBlock }
            throw TryLockError.Error(error)
        }
    }
}

fn seek_file(fd: i32, pos: SeekFrom): u64 throws Error {
    var whence = 0
    var offset = 0i64
    match pos {
        SeekFrom.Start(n) => {
            if n > 9223372036854775807u64 {
                throw io.from_kind(ErrorKind.InvalidInput)
            }
            whence = 0
            offset = n as i64
        },
        SeekFrom.Current(n) => { whence = 1; offset = n },
        SeekFrom.End(n) => { whence = 2; offset = n }
    }
    let result = unsafe { sys.lseek(fd, offset, whence) }
    if result < 0i64 { throw io.last_os_error() }
    result as u64
}

extend File implements io.Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error { try seek_file(self.fd, pos) }
}

extend File implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try io.read_fd(self.fd, buf) }
}
extend<region r> read File from r implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error { try io.read_fd(self.fd, buf) }
}

extend File implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error { try io.write_fd(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}
extend<region r> read File from r implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error { try io.write_fd(self.fd, buf) }
    mut fn flush(): Unit throws Error {}
}

extend<region r> read File from r implements io.Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error { try seek_file(self.fd, pos) }
}

// POSIX positional I/O; calls do not change the file's shared cursor.
pub interface FileExt {
    fn read_at(mut buf: [u8], offset: u64): usize throws Error;
    fn write_at(read buf: [u8], offset: u64): usize throws Error;
}

fn checked_file_offset(offset: u64): i64 throws Error {
    if offset > 9223372036854775807u64 {
        throw io.from_kind(ErrorKind.InvalidInput)
    }
    offset as i64
}

extend File implements FileExt {
    fn read_at(mut buf: [u8], offset: u64): usize throws Error {
        let native_offset = try checked_file_offset(offset)
        while true {
            let count = unsafe { pread(self.fd, sys.data_mut(buf), buf.len(), native_offset) }
            if count >= 0isize { return count as usize }
            let error = io.last_os_error()
            if !error.kind().is(ErrorKind.Interrupted) { throw error }
        }
        0usize
    }

    fn write_at(read buf: [u8], offset: u64): usize throws Error {
        let native_offset = try checked_file_offset(offset)
        while true {
            let count = unsafe { pwrite(self.fd, package.core.slice.data(buf), buf.len(), native_offset) }
            if count >= 0isize { return count as usize }
            let error = io.last_os_error()
            if !error.kind().is(ErrorKind.Interrupted) { throw error }
        }
        0usize
    }
}

// The whole file.
pub fn read_bytes(read input: PathInput): List<u8> throws Error {
    var f = try open(input)
    var out = vec.new<u8>()
    let n = try f.read_to_end(out)
    out
}

pub fn `read`(read input: PathInput): List<u8> throws Error { try read_bytes(input) }

// The whole file as text; ill-formed UTF-8 fails with `InvalidData`.
pub fn read_to_string(read input: PathInput): String throws Error {
    let bytes = try read_bytes(input)
    let decoded = capture package.alloc.string.from_utf8(bytes)
    match take decoded {
        success(s) => s,
        failure(e) => throw io.from_kind(ErrorKind.InvalidData)
    }
}

// Replaces the file's contents.
pub fn write(read input: PathInput, read bytes: [u8]): Unit throws Error {
    var f = try create(input)
    try f.write_all(bytes)
}

pub fn `copy`(read from: PathInput, read to: PathInput): u64 throws Error {
    var source = try open(from)
    let source_metadata = try source.metadata()
    var destination = try create(to)
    var buffer = [0u8; 4096]
    var total = 0u64
    while true {
        let count = try source.read_some(buffer)
        if count == 0usize { break }
        let bytes = unsafe { package.core.slice.subslice_unchecked(buffer, 0usize, count) }
        try destination.write_all(bytes)
        total = match total.checked_add(count as u64) {
            present(next) => next,
            none => throw io.from_kind(ErrorKind.InvalidData)
        }
    }
    let target_mode = source_metadata.permissions()
    try destination.set_permissions(target_mode)
    total
}

pub fn set_permissions(read input: PathInput, permissions: Permissions): Unit throws Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    if unsafe { chmod(c.as_ptr(), permissions.mode()) } != 0 { throw io.last_os_error() }
}

pub fn hard_link(read existing: PathInput, read link_path: PathInput): Unit throws Error {
    let old = try ffi.cstring(existing.as_path().as_bytes())
    let new = try ffi.cstring(link_path.as_path().as_bytes())
    if unsafe { link(old.as_ptr(), new.as_ptr()) } != 0 { throw io.last_os_error() }
}

pub fn soft_link(read target: PathInput, read link_path: PathInput): Unit throws Error {
    let target_bytes = try ffi.cstring(target.as_path().as_bytes())
    let link_bytes = try ffi.cstring(link_path.as_path().as_bytes())
    if unsafe { symlink(target_bytes.as_ptr(), link_bytes.as_ptr()) } != 0 {
        throw io.last_os_error()
    }
}

fn path_call(read p: Path, which: i32, mode: u32): Unit throws Error {
    let c = try ffi.cstring(p.as_bytes())
    var r = 0
    if which == 0 { r = unsafe { sys.unlink(c.as_ptr()) } }
    else if which == 1 { r = unsafe { sys.rmdir(c.as_ptr()) } }
    else { r = unsafe { sys.mkdir(c.as_ptr(), mode) } }
    if r != 0 { throw io.last_os_error() }
}

pub fn remove_file(read input: PathInput): Unit throws Error { try path_call(input.as_path(), 0, 0u32) }
pub fn remove_dir(read input: PathInput): Unit throws Error { try path_call(input.as_path(), 1, 0u32) }
pub fn create_dir(read input: PathInput): Unit throws Error { try path_call(input.as_path(), 2, 511u32) }

pub fn remove_dir_all(read input: PathInput): Unit throws Error {
    let c = try ffi.cstring(input.as_path().as_bytes())
    if unsafe { sys.mettle_rt_remove_dir_all(c.as_ptr()) } != 0 { throw io.last_os_error() }
}

// Creates the path and any missing parents; an existing directory is not an error.
pub fn create_dir_all(read input: PathInput): Unit throws Error { try create_dirs(input.as_path(), 511u32) }

fn create_dirs(read p: Path, mode: u32): Unit throws Error {
    if p.is_empty() { return }
    let made = capture path_call(p, 2, mode)
    match take made {
        success(u) => { return },
        failure(e) => {
            if e.kind().is(ErrorKind.AlreadyExists) {
                let found = capture metadata(p)
                match take found {
                    success(details) => { if details.is_dir() { return } },
                    failure(_) => {}
                }
                throw e
            }
            if !e.kind().is(ErrorKind.NotFound) { throw e }
            match p.parent() {
                present(parent) => { try create_dirs(parent, mode) },
                none => { throw e }
            }
            match take capture path_call(p, 2, mode) {
                success(_) => {},
                failure(error) => {
                    if error.kind().is(ErrorKind.AlreadyExists) {
                        match take capture metadata(p) {
                            success(details) => { if details.is_dir() { return } },
                            failure(_) => {}
                        }
                    }
                    throw error
                }
            }
        }
    }
}

pub fn rename(read old: PathInput, read new: PathInput): Unit throws Error {
    let a = try ffi.cstring(old.as_path().as_bytes())
    let b = try ffi.cstring(new.as_path().as_bytes())
    if unsafe { sys.rename(a.as_ptr(), b.as_ptr()) } != 0 { throw io.last_os_error() }
}

// One directory entry: its name and the directory it was listed from.
pub type DirEntry { name: OsString; dir: PathBuf }

extend DirEntry {
    pub fn file_name(): OsString { self.name.clone() }
    pub fn file_type(): FileType throws Error {
        try symlink_metadata(self.path()).file_type()
    }
    pub fn metadata(): Metadata throws Error { try symlink_metadata(self.path()) }
    pub fn path(): PathBuf {
        var p = self.dir.as_path().to_path_buf()
        p.push(super.path.path_from_os_str(self.name.as_os_str()))
        p
    }
}

extend DirEntry implements package.core.fmt.Debug {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        var debug = try f.debug_struct("DirEntry")
        try debug.field("name", self.name.as_os_str())
        try debug.field("path", self.path().as_path().as_bytes())
        try debug.finish()
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

// Exclusive iteration and destruction serialize access to the owned DIR cursor.
unsafe extend ReadDir implements Transferable {}
unsafe extend ReadDir implements Shareable {}

pub fn read_dir(read input: PathInput): ReadDir throws Error {
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
        unsafe { sys.mettle_rt_set_errno(0) }
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

extend ReadDir implements package.core.fmt.Debug {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        var debug = try f.debug_struct("ReadDir")
        try debug.field("path", self.dir.as_path().as_bytes())
        try debug.field("finished", self.finished)
        try debug.finish()
    }
}

// Yields each entry; a read failure is yielded once and ends the iteration.
extend ReadDir implements package.core.iter.Iterator {
    type Item = (Outcome<DirEntry, Error>);
    mut fn next(): (Outcome<DirEntry, Error>)? {
        let entry = capture self.next_entry()
        match take entry {
            success(found) => match take found {
                present(value) => present(success(value)),
                none => none
            },
            failure(error) => present(failure(error))
        }
    }
}

extend Path {
    pub fn canonicalize(): PathBuf throws Error { try super.fs.canonicalize(self) }
    pub fn metadata(): Metadata throws Error { try super.fs.metadata(self) }
    pub fn symlink_metadata(): Metadata throws Error { try super.fs.symlink_metadata(self) }
    pub fn exists(): bool {
        match take capture super.fs.exists(self) {
            success(found) => found,
            failure(_) => false
        }
    }
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
    pub fn exists(): bool { self.as_path().exists() }
    pub fn try_exists(): bool throws Error { try super.fs.try_exists(self.as_path()) }
    pub fn is_file(): bool { self.as_path().is_file() }
    pub fn is_dir(): bool { self.as_path().is_dir() }
    pub fn is_symlink(): bool { self.as_path().is_symlink() }
    pub fn read_dir(): ReadDir throws Error { try super.fs.read_dir(self.as_path()) }
    pub fn read_link(): OsString throws Error { try super.fs.read_link(self.as_path()) }
}

// Value types duplicate by copy; owners clone their buffers.
extend FileType implements Clone {
    fn clone(): FileType { self }
}
extend Metadata implements Clone {
    fn clone(): Metadata { self }
}
extend OpenOptions implements Clone {
    fn clone(): OpenOptions { self }
}
extend Permissions implements Clone {
    fn clone(): Permissions { self }
}
extend Permissions implements PartialEq {
    fn eq(read other: Permissions): bool { self.mode == other.mode }
}
extend Permissions implements package.core.cmp.Eq {}
extend Permissions implements package.core.fmt.Debug {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        var debug = try f.debug_struct("Permissions")
        try debug.field("mode", self.mode)
        try debug.finish()
    }
}
extend Metadata implements package.core.fmt.Debug {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        var debug = try f.debug_struct("Metadata")
        try debug.field("size", self.size)
        try debug.field("kind", self.kind)
        try debug.field("mode", self.mode)
        try debug.field("modified_secs", self.modified_secs)
        try debug.field("modified_nanos", self.modified_nanos)
        try debug.finish()
    }
}
extend OpenOptions implements package.core.fmt.Debug {
    fn fmt(mut f: package.core.fmt.Formatter): Unit throws package.core.fmt.Error {
        var debug = try f.debug_struct("OpenOptions")
        try debug.field("flags", self.flags)
        try debug.field("mode", self.mode)
        try debug.finish()
    }
}
