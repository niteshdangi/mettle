import alloc.arc
import core.clone.Clone
import std.fs.File
import std.io.{Error, Reader, Seek, SeekFrom, Writer}
import std.path.path_from_text

type SharedOnly { file: File }

extend<region r> read SharedOnly from r implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        var view = read self.file
        try view.read_some(bytes)
    }
}

extend<region r> read SharedOnly from r implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        var view = read self.file
        try view.write_some(bytes)
    }
    mut fn flush(): Unit throws Error {
        var view = read self.file
        try view.flush()
    }
}

extend<region r> read SharedOnly from r implements Seek {
    mut fn seek(position: SeekFrom): u64 throws Error {
        var view = read self.file
        try view.seek(position)
    }
}

fn read_byte<R: Reader>(mut reader: R): u8 throws Error {
    var byte = [0u8]
    try reader.read_exact(mut byte)
    byte[0usize]
}

fn write_bytes<W: Writer>(mut writer: W, read bytes: [u8]): Unit throws Error {
    try writer.write_all(bytes)
    try writer.flush()
}

fn position<S: Seek>(mut stream: S): u64 throws Error { try stream.stream_position() }
fn rewind<S: Seek>(mut stream: S): Unit throws Error { try stream.rewind() }

fn run(): i32 throws Error {
    let path = path_from_text("i13-io-arc-forwarding")
    try std.fs.write(path, "abcdef".as_bytes())
    var options = std.fs.open_options()
    options.set_read(true)
    options.set_write(true)
    let file = try options.open(path)
    let raw = file.as_raw_fd()
    var first = arc.new(SharedOnly(file))
    var second = first.clone()
    assert(try read_byte(mut first) == 97u8, "Shared forwards shared-only Reader")
    assert(try position(mut second) == 1u64, "cloned Shared shares the OS offset")
    try write_bytes(mut second, "XY".as_bytes())
    assert(try position(mut first) == 3u64, "shared-only Writer advances the same offset")
    assert(try read_byte(mut first) == 100u8, "read observes the shared writer position")
    try rewind(mut second)
    var content = [0u8; 6]
    try first.read_exact(mut content)
    let actual: read [u8] = read content
    assert(actual == "aXYdef".as_bytes(), "writes preserve data through both Shared handles")
    core.mem.drop(take first)
    try rewind(mut second)
    assert(try read_byte(mut second) == 97u8, "dropping one Shared does not close the file")
    core.mem.drop(take second)
    var byte = [0u8]
    match take capture std.io.read_fd(raw, mut byte) {
        failure(error) => { assert(error.raw_os_error() == present(9i32), "last Shared closes the shared file exactly once") },
        success(_) => { return 1 }
    }

    var readonly = arc.new(try File.open(path))
    match take capture write_bytes(mut readonly, "x".as_bytes()) {
        failure(error) => { assert(error.raw_os_error() == present(9i32), "Shared preserves OS write errors") },
        success(_) => { return 2 }
    }
    assert(try read_byte(mut readonly) == 97u8, "failed writes preserve the live shared handle and cursor")
    core.mem.drop(take readonly)
    try std.fs.remove_file(path)
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
