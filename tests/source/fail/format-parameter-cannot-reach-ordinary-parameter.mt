// expect-error: type 5:40 a 'format' parameter can only be forwarded to another 'format' parameter or used as a method receiver
// expect-error-count: 1
import core::fmt::Message;
fn g(m: read Message): i32 { 0 }
fn f(message: format Message): i32 { g(message) }
fn main(): i32 { f("x") }
