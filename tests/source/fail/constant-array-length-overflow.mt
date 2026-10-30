// expect-error-count: 1
// expect-error: type 3:31 constant overflows
fn main() { let values: [i32; 2147483647+1] = []; 0 }
