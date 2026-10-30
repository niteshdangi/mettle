// expect-error: type 2:57 may be uninitialized
type Pair { first: i32; second: i32; init(value: i32) { self.first = value } }
fn main() { let pair = Pair(42); 0 }
