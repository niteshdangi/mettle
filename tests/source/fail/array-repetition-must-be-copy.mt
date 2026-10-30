// expect-error: ownership 3:26 requires Copy
type Owned { value: i32 }
fn main() { let values = [Owned(42); 2]; 0 }
