// expect-error: type 6:32 an f-string can only be passed to a 'format' parameter
// expect-error-count: 1
import std.macros.format_args
fn main(): i32 {
    let value = 7
    let escaped = format_args!(f"{value}")
    0
}
