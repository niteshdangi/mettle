// expect-error: type 2:16 required parameter
fn bad(a:i32=0,b:i32) { a+b }
fn main() { bad(0,0) }
