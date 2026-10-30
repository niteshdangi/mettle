// expect-error: parse 5:26 expected an expression
// expect-error-count: 1
import core::fmt::Message;
fn show(message: format Message): i32 { 0 }
fn main(): i32 { show(f"{}") }
