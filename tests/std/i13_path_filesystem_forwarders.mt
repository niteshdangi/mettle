import std.io.Error
import std.path.{PathBuf, path_from_text, path_buf_from_text}

fn check_path(read path: std.path.Path): i32 throws Error {
    if !path.exists() || !(try path.try_exists()) { return 1 }
    if !path.is_dir() || path.is_file() || path.is_symlink() { return 2 }
    if !(try path.metadata()).is_dir() { return 3 }
    if !(try path.symlink_metadata()).is_dir() { return 4 }
    let resolved = try path.canonicalize()
    if !resolved.is_absolute() { return 5 }
    {
        var entries = try path.read_dir()
        match try entries.next_entry() {
            present(_) => {},
            none => {}
        }
    }
    match capture path.read_link() {
        success(_) => { return 6 },
        failure(_) => {}
    }
    0
}

fn check_path_buf(read path: PathBuf): i32 throws Error {
    if !path.exists() || !(try path.try_exists()) { return 11 }
    if !path.is_dir() || path.is_file() || path.is_symlink() { return 12 }
    if !(try path.metadata()).is_dir() { return 13 }
    if !(try path.symlink_metadata()).is_dir() { return 14 }
    let resolved = try path.canonicalize()
    if !resolved.is_absolute() { return 15 }
    {
        var entries = try path.read_dir()
        match try entries.next_entry() {
            present(_) => {},
            none => {}
        }
    }
    match capture path.read_link() {
        success(_) => { return 16 },
        failure(_) => {}
    }
    0
}

fn run(): i32 throws Error {
    let first = try check_path(path_from_text("."))
    if first != 0 { return first }
    try check_path_buf(path_buf_from_text("."))
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
