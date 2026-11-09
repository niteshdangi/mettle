// expect-exit: 0
// profiles: debug release
// Blanket and auto-property evidence for ffi, fs and io types. Each call instantiates the
// blanket trait row for a hosted std type. Pairs the compiler cannot satisfy are
// listed as gaps at the end of main; negative impls are evidenced in tests/source/fail.
fn any_ok<T: unsized + core.any.Any>(): Unit {}
fn borrow_ok<T: unsized + core.borrow.Borrow<T>>(): Unit {}
fn owned_ok<T: core.borrow.ToOwned>(): Unit {}
fn from_ok<T: core.convert.From<T>>(): Unit {}
fn into_ok<T: core.convert.Into<T>>(): Unit {}
fn tryfrom_ok<T: core.convert.TryFrom<T>>(): Unit {}
fn tryinto_ok<T: core.convert.TryInto<T>>(): Unit {}
fn string_ok<T: alloc.string.ToString>(): Unit {}
fn send_ok<T: unsized + Transferable>(): Unit {}
fn sync_ok<T: unsized + Shareable>(): Unit {}
alias A_ffi_CStr = std.ffi.CStr
alias A_ffi_CString = std.ffi.CString
alias A_ffi_OsStr = std.ffi.OsStr
alias A_ffi_OsString = std.ffi.OsString
alias A_fs_DirEntry = std.fs.DirEntry
alias A_fs_File = std.fs.File
alias A_fs_FileType = std.fs.FileType
alias A_fs_Metadata = std.fs.Metadata
alias A_fs_OpenOptions = std.fs.OpenOptions
alias A_fs_Permissions = std.fs.Permissions
alias A_fs_ReadDir = std.fs.ReadDir
alias A_io_BufReader = std.io.BufferedReader<std.io.Stdin>
alias A_io_BufWriter = std.io.BufferedWriter<std.io.Stdout>
alias A_io_Error = std.io.Error
alias A_io_ErrorKind = std.io.ErrorKind
alias A_io_Stderr = std.io.Stderr
alias A_io_Stdin = std.io.Stdin
alias A_io_Stdout = std.io.Stdout
fn main(): i32 {
    // ffi::CStr
    borrow_ok<A_ffi_CStr>()
    send_ok<A_ffi_CStr>()
    sync_ok<A_ffi_CStr>()
    // ffi::CString
    any_ok<A_ffi_CString>()
    borrow_ok<A_ffi_CString>()
    from_ok<A_ffi_CString>()
    tryfrom_ok<A_ffi_CString>()
    tryinto_ok<A_ffi_CString>()
    into_ok<A_ffi_CString>()
    send_ok<A_ffi_CString>()
    sync_ok<A_ffi_CString>()
    owned_ok<A_ffi_CString>()
    // ffi::OsStr
    any_ok<A_ffi_OsStr>()
    borrow_ok<A_ffi_OsStr>()
    send_ok<A_ffi_OsStr>()
    sync_ok<A_ffi_OsStr>()
    // ffi::OsString
    any_ok<A_ffi_OsString>()
    borrow_ok<A_ffi_OsString>()
    from_ok<A_ffi_OsString>()
    tryfrom_ok<A_ffi_OsString>()
    tryinto_ok<A_ffi_OsString>()
    into_ok<A_ffi_OsString>()
    send_ok<A_ffi_OsString>()
    sync_ok<A_ffi_OsString>()
    // fs::DirEntry
    any_ok<A_fs_DirEntry>()
    borrow_ok<A_fs_DirEntry>()
    from_ok<A_fs_DirEntry>()
    tryfrom_ok<A_fs_DirEntry>()
    tryinto_ok<A_fs_DirEntry>()
    into_ok<A_fs_DirEntry>()
    send_ok<A_fs_DirEntry>()
    sync_ok<A_fs_DirEntry>()
    // fs::File
    any_ok<A_fs_File>()
    borrow_ok<A_fs_File>()
    from_ok<A_fs_File>()
    tryfrom_ok<A_fs_File>()
    tryinto_ok<A_fs_File>()
    into_ok<A_fs_File>()
    send_ok<A_fs_File>()
    sync_ok<A_fs_File>()
    // fs::FileType
    any_ok<A_fs_FileType>()
    borrow_ok<A_fs_FileType>()
    from_ok<A_fs_FileType>()
    tryfrom_ok<A_fs_FileType>()
    tryinto_ok<A_fs_FileType>()
    into_ok<A_fs_FileType>()
    send_ok<A_fs_FileType>()
    sync_ok<A_fs_FileType>()
    // fs::Metadata
    any_ok<A_fs_Metadata>()
    borrow_ok<A_fs_Metadata>()
    from_ok<A_fs_Metadata>()
    tryfrom_ok<A_fs_Metadata>()
    tryinto_ok<A_fs_Metadata>()
    into_ok<A_fs_Metadata>()
    send_ok<A_fs_Metadata>()
    sync_ok<A_fs_Metadata>()
    // fs::OpenOptions
    any_ok<A_fs_OpenOptions>()
    borrow_ok<A_fs_OpenOptions>()
    from_ok<A_fs_OpenOptions>()
    tryfrom_ok<A_fs_OpenOptions>()
    tryinto_ok<A_fs_OpenOptions>()
    into_ok<A_fs_OpenOptions>()
    send_ok<A_fs_OpenOptions>()
    sync_ok<A_fs_OpenOptions>()
    // fs::Permissions
    any_ok<A_fs_Permissions>()
    borrow_ok<A_fs_Permissions>()
    from_ok<A_fs_Permissions>()
    tryfrom_ok<A_fs_Permissions>()
    tryinto_ok<A_fs_Permissions>()
    into_ok<A_fs_Permissions>()
    send_ok<A_fs_Permissions>()
    sync_ok<A_fs_Permissions>()
    // fs::ReadDir
    any_ok<A_fs_ReadDir>()
    borrow_ok<A_fs_ReadDir>()
    from_ok<A_fs_ReadDir>()
    tryfrom_ok<A_fs_ReadDir>()
    tryinto_ok<A_fs_ReadDir>()
    into_ok<A_fs_ReadDir>()
    // io::BufReader
    any_ok<A_io_BufReader>()
    borrow_ok<A_io_BufReader>()
    from_ok<A_io_BufReader>()
    tryfrom_ok<A_io_BufReader>()
    tryinto_ok<A_io_BufReader>()
    into_ok<A_io_BufReader>()
    send_ok<A_io_BufReader>()
    sync_ok<A_io_BufReader>()
    // io::BufWriter
    any_ok<A_io_BufWriter>()
    borrow_ok<A_io_BufWriter>()
    from_ok<A_io_BufWriter>()
    tryfrom_ok<A_io_BufWriter>()
    tryinto_ok<A_io_BufWriter>()
    into_ok<A_io_BufWriter>()
    send_ok<A_io_BufWriter>()
    sync_ok<A_io_BufWriter>()
    // io::Error
    any_ok<A_io_Error>()
    borrow_ok<A_io_Error>()
    from_ok<A_io_Error>()
    tryfrom_ok<A_io_Error>()
    tryinto_ok<A_io_Error>()
    into_ok<A_io_Error>()
    send_ok<A_io_Error>()
    sync_ok<A_io_Error>()
    // io::ErrorKind
    any_ok<A_io_ErrorKind>()
    borrow_ok<A_io_ErrorKind>()
    from_ok<A_io_ErrorKind>()
    tryfrom_ok<A_io_ErrorKind>()
    tryinto_ok<A_io_ErrorKind>()
    into_ok<A_io_ErrorKind>()
    send_ok<A_io_ErrorKind>()
    sync_ok<A_io_ErrorKind>()
    // io::Stderr
    any_ok<A_io_Stderr>()
    borrow_ok<A_io_Stderr>()
    from_ok<A_io_Stderr>()
    tryfrom_ok<A_io_Stderr>()
    tryinto_ok<A_io_Stderr>()
    into_ok<A_io_Stderr>()
    send_ok<A_io_Stderr>()
    sync_ok<A_io_Stderr>()
    // io::Stdin
    any_ok<A_io_Stdin>()
    borrow_ok<A_io_Stdin>()
    from_ok<A_io_Stdin>()
    tryfrom_ok<A_io_Stdin>()
    tryinto_ok<A_io_Stdin>()
    into_ok<A_io_Stdin>()
    send_ok<A_io_Stdin>()
    sync_ok<A_io_Stdin>()
    // io::Stdout
    any_ok<A_io_Stdout>()
    borrow_ok<A_io_Stdout>()
    from_ok<A_io_Stdout>()
    tryfrom_ok<A_io_Stdout>()
    tryinto_ok<A_io_Stdout>()
    into_ok<A_io_Stdout>()
    send_ok<A_io_Stdout>()
    sync_ok<A_io_Stdout>()
    // gap ffi::OsString ToOwned: no Clone implementation (ToOwned blanket requires Clone)
    // gap fs::FileType ToOwned: no Clone implementation
    // gap fs::Metadata ToOwned: no Clone implementation
    // gap fs::OpenOptions ToOwned: no Clone implementation
    // gap fs::Permissions ToOwned: no Clone implementation
    // gap fs::ReadDir Send: not Transferable; Rust auto-derives Send via Dir raw pointer unsafe impl
    // gap fs::ReadDir Sync: not Shareable; Rust auto-derives Sync via Dir raw pointer unsafe impl
    // gap io::Error ToString: no Display implementation
    // gap io::ErrorKind ToOwned: no Clone implementation
    // gap io::ErrorKind ToString: no Display implementation
    // gap: io::Cursor absent from the Mettle library (no declaration found)
    // gap: io::Lines absent from the Mettle library (no declaration found)
    0
}
