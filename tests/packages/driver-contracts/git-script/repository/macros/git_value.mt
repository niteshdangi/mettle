import std.io.Error
import std.path.path_from_text

fn run(): i32 throws Error {
    let cwd = try std.env.current_dir()
    match std.env.var_os(std.ffi.os_str_from_text("METTLE_PACKAGE_DIR")) {
        present(directory) => {
            if !cwd.as_os_str().same(directory.as_os_str()) { return 2 }
        },
        none => { return 3 }
    }
    let call = try std.macros.read_invocation()
    let spec = try std.fs.read_to_string(path_from_text("macro-spec.txt"))
    let name = call.text()
    var output = alloc.string.new()
    output.push_str("fn ")
    output.push_str(name.as_text())
    output.push_str("(): i32 { ")
    output.push_str(spec.as_text().trim())
    output.push_str(" }\n")
    try std.macros.emit(output.as_text())
    try std.macros.depends_on_file("macro-spec.txt")
    try std.macros.reproducible()
    0
}

fn main(): i32 {
    let result = capture run()
    match take result { success(code) => code, failure(error) => 1 }
}
