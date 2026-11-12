import core.convert.From
import core.iter.Iterator
import std.ffi.OsString
import std.fs.File
import std.io.{Error, ErrorKind, Reader, Seek, SeekFrom, Writer}
import std.path.path_from_text
import std.sys

fn require_shared<T: Shareable>(read value: T): Unit {}

fn run(): i32 throws Error {
    let root = path_from_text("i13-fs-missing-entries")
    let path = path_from_text("i13-fs-missing-entries/data")
    let link = path_from_text("i13-fs-missing-entries/link")
    try std.fs.create_dir(root)
    var file = try File.create_new(path)
    try file.write_all("old".as_bytes())
    match take capture File.create_new(path) {
        failure(error) => { assert(error.kind().is(ErrorKind.AlreadyExists), "exclusive creation") },
        success(_) => { return 1 }
    }
    core.mem.drop(take file)
    var replacement = try File.create(path)
    assert((try replacement.metadata()).len() == 0u64, "associated create truncates")
    try replacement.write_all("abc".as_bytes())
    core.mem.drop(take replacement)

    var original = try File.open(path)
    let raw = unsafe { sys.mettle_rt_dup(original.as_raw_fd()) }
    if raw < 0i32 { throw std.io.last_os_error() }
    let descriptor = unsafe { sys.OwnedFd.from_raw_fd(raw) }
    var adopted = File.(From<sys.OwnedFd>).from(descriptor)
    var byte = [0u8]
    assert(try adopted.read_some(mut byte) == 1usize && byte[0usize] == 97u8,
        "descriptor adoption retains readable state")
    core.mem.drop(take adopted)
    assert(try original.read_some(mut byte) == 1usize && byte[0usize] == 98u8,
        "closing the adopted duplicate preserves original ownership and shared position")
    {
        var view = read original
        assert(try view.seek(SeekFrom.Start(0u64)) == 0u64, "shared file seek")
        try view.read_exact(mut byte)
        assert(byte[0usize] == 97u8, "shared file read")
    }
    let original_fd = original.as_raw_fd()
    let transferred_fd = sys.OwnedFd.(From<File>).from(original)
    assert(transferred_fd.as_raw_fd() == original_fd, "file transfer preserves the descriptor without duplication")
    var restored = File.(From<sys.OwnedFd>).from(transferred_fd)
    try restored.read_exact(mut byte)
    assert(byte[0usize] == 98u8, "file ownership roundtrip preserves cursor and live descriptor")
    core.mem.drop(take restored)
    try std.fs.soft_link(path_from_text("data"), link)

    var name: OsString? = none
    {
        var entries = try std.fs.read_dir(root)
        while true {
            match try entries.next_entry() {
                present(entry) => {
                    let owned = entry.file_name()
                    if owned.as_bytes() == "link".as_bytes() {
                        assert((try entry.metadata()).is_symlink(), "entry metadata does not follow symlinks")
                        assert((try entry.file_type()).is_symlink(), "entry type agrees with its metadata")
                        name = present(owned)
                    }
                },
                none => { break }
            }
        }
        assert(entries.next().is_none() && entries.next().is_none(),
            "directory iterator remains exhausted")
    }
    match take name {
        present(owned) => { assert(owned.as_bytes() == "link".as_bytes(), "file name outlives entry and iterator") },
        none => { return 2 }
    }
    var transferred = try std.fs.read_dir(root)
    require_shared(read transferred)
    let worker = std.thread.spawn(take fn(): usize {
        var count = 0usize
        while true {
            match take transferred.next() {
                present(success(_)) => { count += 1usize },
                present(failure(_)) => { return 0usize },
                none => { break }
            }
        }
        assert(transferred.next().is_none(), "transferred directory remains exhausted")
        count
    })
    match take capture worker.join() {
        success(count) => { assert(count == 2usize, "directory iteration can move between threads") },
        failure(_) => { return 3 }
    }
    try std.fs.remove_file(link)
    try std.fs.remove_file(path)
    try std.fs.remove_dir(root)
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
