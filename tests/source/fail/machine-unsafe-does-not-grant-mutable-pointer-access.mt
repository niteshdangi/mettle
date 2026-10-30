// expect-error-count: 1
// expect-error: ownership 3:75 cannot write through a read parameter
fn main() { let value = 42; let p = read value as ptr<read i32>; unsafe { *p = 1 }; 0 }
