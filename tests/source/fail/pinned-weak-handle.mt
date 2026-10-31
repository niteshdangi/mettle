// expect-error: type 2:12 weak handles cannot be pinned
fn invalid(value: pinned weak i32) {}
fn main(): i32 { 0 }
