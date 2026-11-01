// expect-error: type 2:24 Sized
fn invalid<T: unsized>(value: read (T, i32)): Unit {}
fn main(): i32 { 0 }
