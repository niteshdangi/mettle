// expect-error: type 2:38 uninitialized
fn main() { let value: i32; unsafe { value } }
