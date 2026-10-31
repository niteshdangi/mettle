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
    pub fn permissions(): u32 { self.mode }
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

// Open-mode builder; `open` fails with the OS error (`NotFound`,
// `AlreadyExists`, ...) unchanged.
pub copy type OpenOptions { flags: i32; mode: u32 }

pub fn open_options(): OpenOptions { OpenOptions(0, 438u32) }

extend OpenOptions {
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

fn path_call(p: read Path, which: i32): Unit throws Error {
    let c = try ffi.cstring(p.as_bytes())
    var r = 0
    if which == 0 { r = unsafe { sys.unlink(c.as_ptr()) } }
    else if which == 1 { r = unsafe { sys.rmdir(c.as_ptr()) } }
    else { r = unsafe { sys.mkdir(c.as_ptr(), 511u32) } }
    if r != 0 { throw io.last_os_error() }
}

pub fn remove_file(input: read PathInput): Unit throws Error { try path_call(input.as_path(), 0) }
pub fn remove_dir(input: read PathInput): Unit throws Error { try path_call(input.as_path(), 1) }
pub fn create_dir(input: read PathInput): Unit throws Error { try path_call(input.as_path(), 2) }

// Creates the path and any missing parents; an existing directory is not an error.
pub fn create_dir_all(input: read PathInput): Unit throws Error { try create_dirs(input.as_path()) }

fn create_dirs(p: read Path): Unit throws Error {
    let made = capture path_call(p, 2)
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
                present(parent) => { try create_dirs(parent) },
                none => { throw e }
            }
            try path_call(p, 2)
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
