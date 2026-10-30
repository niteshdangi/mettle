// expect-error: type 4:46 a 'format' parameter can only be forwarded to another 'format' parameter or used as a method receiver
// expect-error-count: 1
import core.fmt.Message;
fn f(message: format Message): i32 { let m = message; 0 }
fn main(): i32 { f("x") }
