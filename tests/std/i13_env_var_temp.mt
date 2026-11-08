// env::var returns the value as text, reports unset and non-UTF-8 values, and
// temp_dir follows TMPDIR.
import std.env
import std.env.VarError
import std.ffi
import std.io.Error
import std.path.path_from_text
import core.text.Text

fn is_text(value: read Text, want: read Text): bool { value == want }

fn run(): i32 throws Error {
    let name = ffi.os_str_from_text("MT_I13_VAR_TEXT")
    try std.env.remove_var(name)

    let missing = capture std.env.`var`(name)
    match take missing {
        success(value) => { return 2 },
        failure(error) => {
            match error {
                VarError.NotPresent => {},
                _ => { return 3 }
            }
        }
    }

    try std.env.set_var(name, ffi.os_str_from_text("hello"))
    let value = capture std.env.`var`(name)
    match take value {
        success(text) => {
            if !is_text(text.as_text(), "hello") { return 4 }
        },
        failure(error) => { return 5 }
    }

    // A value that is not UTF-8 is reported with its raw bytes.
    let invalid: [u8; 1] = [255u8]
    try std.env.set_var(name, ffi.os_str(invalid))
    let rejected = capture std.env.`var`(name)
    match take rejected {
        success(text) => { return 6 },
        failure(error) => {
            match error {
                VarError.NotUnicode(raw) => {
                    if !raw.as_os_str().same(ffi.os_str(invalid)) { return 7 }
                },
                _ => { return 8 }
            }
        }
    }
    try std.env.remove_var(name)

    // temp_dir uses TMPDIR when it is set and /tmp otherwise.
    let tmpdir = ffi.os_str_from_text("TMPDIR")
    try std.env.set_var(tmpdir, ffi.os_str_from_text("/tmp/mt-i13-scratch"))
    if !std.env.temp_dir().as_path().same(path_from_text("/tmp/mt-i13-scratch")) { return 9 }
    try std.env.remove_var(tmpdir)
    if !std.env.temp_dir().as_path().same(path_from_text("/tmp")) { return 10 }
    // vars lists the entry set_var created; current_dir follows set_current_dir.
    try std.env.set_var(name, ffi.os_str_from_text("seen"))
    var seen = false
    let all = std.env.vars()
    var i = 0usize
    while i < all.len() {
        if all[i].name.as_os_str().same(name) && all[i].value.as_os_str().same(ffi.os_str_from_text("seen")) {
            seen = true
        }
        i += 1usize
    }
    if !seen { return 11 }
    try std.env.remove_var(name)
    if std.env.args().len() == 0usize { return 12 }
    let original = try std.env.current_dir()
    try std.env.set_current_dir(path_from_text("/tmp"))
    let moved = try std.env.current_dir()
    if !moved.as_path().same(path_from_text("/tmp")) { return 13 }
    try std.env.set_current_dir(read original)
    if !(try std.env.current_dir()).same(read original) { return 14 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
