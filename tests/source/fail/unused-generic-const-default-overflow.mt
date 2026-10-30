// expect-error: type 2:23 overflows
fn answer<const N:i32=2147483647+1>():i32{N}
fn main():i32{0}
