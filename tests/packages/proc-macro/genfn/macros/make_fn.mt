import std.io.Error;
import std.path.path_from_text;

fn run(): i32 throws Error {
    let call = try std.macros.read_invocation()
    if call.tokens.len() == 0usize {
        try std.macros.fail("make_fn! expects the name of the function")
        return 0
    }
    let spec = try std.fs.read_to_string(path_from_text("spec.txt"))
    let name = call.text()
    let value = spec.as_text()
    var out = alloc.string.new()
    out.push_str("fn ")
    out.push_str(name.as_text())
    out.push_str("(): i32 { ")
    out.push_str(value.trim())
    out.push_str(" }\n")
    try std.macros.emit(out.as_text())
    try std.macros.depends_on_file("spec.txt")
    try std.macros.reproducible()
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => 1 }
}
