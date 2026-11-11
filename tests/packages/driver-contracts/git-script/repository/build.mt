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
    let out = cwd.join(path_from_text("target/mettle/out"))
    match std.env.var_os(std.ffi.os_str_from_text("METTLE_OUT_DIR")) {
        present(directory) => {
            if !out.as_os_str().same(directory.as_os_str()) { return 4 }
        },
        none => { return 5 }
    }
    let spec = try std.fs.read_bytes(path_from_text("spec.txt"))
    let outside = try std.fs.read_bytes(path_from_text("../outside/input.txt"))
    if outside.len() != 8usize { return 6 }
    try std.fs.write(path_from_text("target/mettle/out/generated.mt"), spec.as_slice())
    std.io.print("mettle:module=gen=generated.mt\n")
    std.io.print("mettle:feature=ready\n")
    std.io.print("mettle:rerun-if-changed=spec.txt\n")
    std.io.print("mettle:rerun-if-changed=../outside/input.txt\n")
    std.io.print("mettle:reproducible\n")
    0
}

fn main(): i32 {
    let result = capture run()
    match take result { success(code) => code, failure(error) => 1 }
}
