import std.io.Error
import std.path.path_from_text

fn run(): i32 throws Error {
    let spec = try std.fs.read_bytes(path_from_text("spec.txt"))
    try std.fs.write(path_from_text("target/mettle/out/generated.mt"), spec.as_slice())
    std.io.print("mettle:module=generated=generated.mt\n")
    std.io.print("mettle:feature=generated\n")
    std.io.print("mettle:rerun-if-changed=spec.txt\n")
    std.io.print("mettle:reproducible\n")
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => 1 }
}
