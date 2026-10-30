// expect-error: signature 3:25 format parameter must have type core::fmt::Message
// expect-error-count: 1
fn bad(message: format i32): i32 { 0 }
fn main(): i32 { 0 }
