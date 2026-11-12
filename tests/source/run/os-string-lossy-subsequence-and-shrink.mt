// profiles: debug release
fn main(): i32 {
    let bytes = [0xe2u8, 0x82u8, 97u8]
    if std.ffi.os_str(bytes).to_string_lossy().as_ref() != "\u{fffd}a" { return 1 }
    var text = std.ffi.OsString.with_capacity(4usize)
    let capacity = text.capacity()
    text.shrink_to(capacity + 1usize)
    if text.capacity() != capacity { return 2 }
    var path = std.path.PathBuf.with_capacity(4usize)
    let capacity = path.capacity()
    path.shrink_to(capacity + 1usize)
    if path.capacity() != capacity { return 3 }
    0
}
