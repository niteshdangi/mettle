// expect-error: type 6:32 a 'format' parameter can only be forwarded to another 'format' parameter or used as a method receiver
// expect-error-count: 1
import core.fmt.Message
import std.macros.format_args
fn bad(message: format Message): i32 {
    let escaped = format_args!(message)
    0
}
fn main(): i32 { bad("value") }
