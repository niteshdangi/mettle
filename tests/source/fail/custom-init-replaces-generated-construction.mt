// expect-error: type 3:24 argument shape
type Pair { first: i32; second: i32; init() { self.first = 20; self.second = 22 } }
fn main() { let pair = Pair(first:20,second:22); 0 }
