// expect-error: type 2:39 array index is out of bounds
fn main() { let values = [42]; values[4294967296usize] }
