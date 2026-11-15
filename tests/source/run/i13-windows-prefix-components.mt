// profiles: debug release
// Windows path prefix recognition, rootedness, and bidirectional components.

import std.path.{Component, Path, PathBuf, path_from_text, path_buf_from_text}

@cfg(target_os = "windows")
fn first_is_prefix(read value: Path): bool {
    match value.components().next() {
        present(Component.Prefix(_)) => true,
        _ => false
    }
}

@cfg(target_os = "windows")
fn check_prefix_kinds(): i32 {
    let verbatim = path_from_text("\\\\?\\C:relative")
    let verbatim_disk = path_from_text("\\\\?\\C:\\root")
    let verbatim_unc = path_from_text("\\\\?\\UNC\\server\\share\\file")
    let device = path_from_text("\\\\.\\pipe\\name")
    let unc = path_from_text("\\\\server\\share\\file")
    let disk = path_from_text("c:relative")

    if !first_is_prefix(verbatim) || !first_is_prefix(verbatim_disk) ||
        !first_is_prefix(verbatim_unc) || !first_is_prefix(device) ||
        !first_is_prefix(unc) || !first_is_prefix(disk) { return 1 }

    var verbatim_components = verbatim.components()
    match verbatim_components.next() {
        present(Component.Prefix(prefix)) => match prefix.kind() {
            std.path.Prefix.Verbatim(name) => {
                if name.to_str() != present("C:relative") { return 2 }
                if prefix.as_os_str().to_str() != present("\\\\?\\C:relative") { return 2 }
            },
            _ => { return 2 }
        },
        _ => { return 2 }
    }

    var disk_components = verbatim_disk.components()
    match disk_components.next() {
        present(Component.Prefix(prefix)) => match prefix.kind() {
            std.path.Prefix.VerbatimDisk(letter) => { if letter != 67u8 { return 3 } },
            _ => { return 3 }
        },
        _ => { return 3 }
    }

    var verbatim_unc_components = verbatim_unc.components()
    match verbatim_unc_components.next() {
        present(Component.Prefix(prefix)) => match prefix.kind() {
            std.path.Prefix.VerbatimUNC(server, share) => {
                if server.to_str() != present("server") || share.to_str() != present("share") {
                    return 4
                }
            },
            _ => { return 4 }
        },
        _ => { return 4 }
    }

    var device_components = device.components()
    match device_components.next() {
        present(Component.Prefix(prefix)) => match prefix.kind() {
            std.path.Prefix.DeviceNS(name) => {
                if name.to_str() != present("pipe") { return 5 }
            },
            _ => { return 5 }
        },
        _ => { return 5 }
    }

    var unc_components = unc.components()
    match unc_components.next() {
        present(Component.Prefix(prefix)) => match prefix.kind() {
            std.path.Prefix.UNC(server, share) => {
                if server.to_str() != present("server") || share.to_str() != present("share") {
                    return 6
                }
            },
            _ => { return 6 }
        },
        _ => { return 6 }
    }

    var drive_components = disk.components()
    match drive_components.next() {
        present(Component.Prefix(prefix)) => match prefix.kind() {
            std.path.Prefix.Disk(letter) => { if letter != 67u8 { return 7 } },
            _ => { return 7 }
        },
        _ => { return 7 }
    }
    if disk.is_absolute() || disk.has_root() { return 8 }
    if !path_from_text("C:\\relative").is_absolute() { return 9 }
    if !verbatim.is_absolute() || !verbatim.has_root() { return 10 }

    var joined: PathBuf = path_buf_from_text("C:\\base")
    joined.push(path_from_text("\\root"))
    if joined.as_path().to_str() != present("C:\\root") { return 12 }
    joined.push(path_from_text("D:relative"))
    if joined.as_path().to_str() != present("D:relative") { return 13 }

    let incomplete_unc = path_from_text("\\\\server")
    match incomplete_unc.components().next() {
        present(Component.Prefix(_)) => { return 11 },
        present(Component.RootDir) => {},
        _ => { return 11 }
    }
    0
}

@cfg(target_os = "windows")
fn check_component_order(): i32 {
    let path = path_from_text("\\\\server\\share\\folder\\file")
    var components = path.components()
    match components.next() {
        present(Component.Prefix(_)) => {},
        _ => { return 20 }
    }
    if components.as_path().to_str() != present("\\folder\\file") { return 27 }
    match components.next() {
        present(Component.RootDir) => {},
        _ => { return 21 }
    }
    if components.as_path().to_str() != present("folder\\file") { return 28 }
    match components.next() {
        present(Component.Normal(value)) => {
            if value.to_str() != present("folder") { return 22 }
        },
        _ => { return 22 }
    }
    if components.as_path().to_str() != present("file") { return 29 }

    var reverse = path.components()
    match reverse.next_back() {
        present(Component.Normal(value)) => {
            if value.to_str() != present("file") { return 23 }
        },
        _ => { return 23 }
    }
    match reverse.next_back() {
        present(Component.Normal(value)) => {
            if value.to_str() != present("folder") { return 30 }
        },
        _ => { return 30 }
    }
    match reverse.next_back() {
        present(Component.RootDir) => {},
        _ => { return 24 }
    }
    match reverse.next_back() {
        present(Component.Prefix(_)) => {},
        _ => { return 25 }
    }
    if reverse.next().is_present() || reverse.next_back().is_present() { return 26 }
    0
}

@cfg(target_os = "windows")
fn check_verbatim_components(): i32 {
    let path = path_from_text("\\\\?\\C:\\a\\.\\..\\b")
    var components = path.components()
    match components.next() {
        present(Component.Prefix(_)) => {},
        _ => { return 30 }
    }
    match components.next() {
        present(Component.RootDir) => {},
        _ => { return 31 }
    }
    match components.next() {
        present(Component.Normal(value)) => {
            if value.to_str() != present("a") { return 32 }
        },
        _ => { return 32 }
    }
    match components.next() {
        present(Component.CurDir) => {},
        _ => { return 33 }
    }
    match components.next() {
        present(Component.ParentDir) => {},
        _ => { return 34 }
    }
    match components.next() {
        present(Component.Normal(value)) => {
            if value.to_str() != present("b") { return 35 }
        },
        _ => { return 35 }
    }

    let slash = path_from_text("\\\\?\\C:\\a/./b")
    var slash_components = slash.components()
    let _ = slash_components.next()
    let _ = slash_components.next()
    match slash_components.next() {
        present(Component.Normal(value)) => {
            if value.to_str() != present("a/./b") { return 36 }
        },
        _ => { return 36 }
    }
    0
}

@cfg(target_os = "windows")
fn main(): i32 {
    let prefixes = check_prefix_kinds()
    if prefixes != 0 { return prefixes }
    let order = check_component_order()
    if order != 0 { return order }
    check_verbatim_components()
}

@cfg(not(target_os = "windows"))
fn main(): i32 { 0 }
