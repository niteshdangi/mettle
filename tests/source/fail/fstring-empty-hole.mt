// expect-error: syntax 5:21 expected expression
// expect-error-count: 1
import core::fmt::Message;
fn take(message: format Message): i32 { 0 }
fn main(): i32 { take(f"{}") }
