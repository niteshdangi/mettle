import std.io.Error
import std.path.path_from_text

@cfg(feature = "host")
fn input(): read Text from static { "../../host-spec.txt" }
@cfg(not(feature = "host"))
fn input(): read Text from static { "../../spec.txt" }

fn run(): i32 throws Error {
    let spec = try std.fs.read_bytes(path_from_text(input()))
    try std.fs.write(path_from_text("target/mettle/out/nested.mt"), spec.as_slice())
    std.io.print("mettle:module=nested_gen=nested.mt\n")
    std.io.print("mettle:feature=ready\n")
    std.io.print("mettle:rerun-if-changed=")
    std.io.print(input())
    std.io.print("\n")
    std.io.print("mettle:reproducible\n")
    0
}

fn main(): i32 {
    let result = capture run()
    match take result { success(code) => code, failure(error) => 1 }
}
