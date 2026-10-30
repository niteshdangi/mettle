// expect-error: type 4:42 a 'format' parameter can only be forwarded to another 'format' parameter or used as a method receiver
// expect-error-count: 1
import core.fmt.Message
fn f(message: format Message): Message { message }
fn main(): i32 { 0 }
