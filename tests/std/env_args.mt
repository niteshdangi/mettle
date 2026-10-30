// args: one two
// Program arguments, environment variables and the working directory.
import std::ffi;
import std::io::Error;
import std::path::path_from_text;

fn run(): i32 throws Error {
    let args = std::env::args()
    if args.len() != 3usize { return 1 }
    if !args[1usize].as_os_str().same(ffi::os_str_from_text("one")) { return 2 }
    if !args[2usize].as_os_str().same(ffi::os_str_from_text("two")) { return 3 }
    let name = ffi::os_str_from_text("MT_ENV_TEST")
    match std::env::var_os(name) { present(v) => { return 4 }, none => {} }
    try std::env::set_var(name, ffi::os_str_from_text("a=b"))
    match std::env::var_os(name) { present(v) => { if !v.as_os_str().same(ffi::os_str_from_text("a=b")) { return 5 } }, none => { return 6 } }
    var seen = false
    let all = std::env::vars()
    var i = 0usize
    while i < all.len() {
        if all[i].name.as_os_str().same(name) && all[i].value.as_os_str().same(ffi::os_str_from_text("a=b")) { seen = true }
        i += 1usize
    }
    if !seen { return 7 }
    try std::env::remove_var(name)
    match std::env::var_os(name) { present(v) => { return 8 }, none => {} }
    // Names with `=` or NUL are rejected.
    let bad = capture std::env::set_var(ffi::os_str_from_text("A=B"), ffi::os_str_from_text("x"))
    if bad.is_success() { return 9 }
    // Changing directory is visible through current_dir.
    try std::fs::create_dir(path_from_text("sub"))
    let before = try std::env::current_dir()
    try std::env::set_current_dir(path_from_text("sub"))
    let after = try std::env::current_dir()
    match after.as_path().file_name() { present(n) => { if !n.same(ffi::os_str_from_text("sub")) { return 10 } }, none => { return 10 } }
    if before.same(after) { return 11 }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => { match e.raw_os_error() { present(c) => 100 + c, none => 99 } } }
}
