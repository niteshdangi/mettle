// expect-error-count: 1
// expect-error: ownership 3:40 write through a read
fn main() { var x = 1; let p = read x; *p = 2; 0 }
