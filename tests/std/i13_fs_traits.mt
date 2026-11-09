import alloc.string
import core.cmp.{Eq, PartialEq}
import core.fmt
import core.hash.{Hash, Hasher}
import core.iter.Iterator
import core.text.Text
import std.io.Error
import std.path.path_from_text
import std.fs.{FileType, OpenOptions}

fn equal<T: Eq + PartialEq>(read left: T, read right: T): bool { left == right }

fn hash_value<T: Hash>(read value: T): u64 {
    var state = core.hash.fnv1a()
    value.hash(mut state)
    state.finish()
}

fn debug_starts<T: fmt.Debug>(read value: T, read prefix: Text): bool {
    var output = string.new()
    var formatted = false
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(fmt.Debug).fmt(value, mut formatter) {
            success(_) => { formatted = true },
            failure(_) => {}
        }
    }
    formatted && output.as_text().starts_with(read prefix)
}

fn run(): i32 throws Error {
    if !FileType.File.is_file() || !FileType.Directory.is_dir() ||
        !FileType.Symlink.is_symlink() {
        return 1
    }
    if !equal(FileType.File, FileType.File) ||
        equal(FileType.File, FileType.Directory) {
        return 2
    }
    if hash_value(FileType.File) != hash_value(FileType.File) ||
        hash_value(FileType.File) == hash_value(FileType.Directory) {
        return 3
    }
    if !debug_starts(FileType.File, "File") { return 4 }

    let permissions = std.fs.permissions_from_mode(420u32)
    if !equal(permissions, std.fs.permissions_from_mode(420u32)) { return 5 }
    if !debug_starts(permissions, "Permissions") { return 6 }
    var options = OpenOptions.new()
    if !debug_starts(read options, "OpenOptions") { return 7 }

    let directory = path_from_text("i13-fs-traits")
    let file_path = path_from_text("i13-fs-traits/data")
    try std.fs.create_dir(directory)
    var file = try std.fs.create_new(file_path)
    if !debug_starts(read file, "File") { return 8 }
    let first = try file.metadata()
    if !debug_starts(first, "Metadata") { return 10 }
    core.mem.drop(take file)
    {
        var entries = try std.fs.read_dir(directory)
        if !debug_starts(read entries, "ReadDir") { return 11 }
        match take entries.next() {
            present(result) => match take result {
                success(entry) => {
                    if !debug_starts(read entry, "DirEntry") { return 12 }
                },
                failure(_) => { return 13 }
            },
            none => { return 14 }
        }
    }
    try std.fs.remove_file(file_path)
    try std.fs.remove_dir(directory)
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
