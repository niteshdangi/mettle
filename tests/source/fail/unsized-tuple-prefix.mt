// expect-error: type 2:29 Sized
fn invalid<T: unsized>(read value: (T, i32)): Unit {}
fn main(): i32 { 0 }
