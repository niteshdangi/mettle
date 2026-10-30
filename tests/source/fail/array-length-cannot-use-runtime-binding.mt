// expect-error-count: 1
// expect-error: type 3:44 constant integer
fn main() { let count=3; let values: [i32; count] = [1,2,3]; 0 }
