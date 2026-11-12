// expect-error: type 4:17 an f-string can only be passed to a 'format' parameter
import std.io
fn main(): i32 {
    io.eprint({ f"value"; })
    0
}
