// expect-error: type 5:26 a function with a 'format' parameter cannot be used as a value
// expect-error-count: 1
import core.fmt.Message;
fn f(message: format Message): i32 { 0 }
fn main(): i32 { let p = f; 0 }
