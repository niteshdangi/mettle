// expect-error: type 3:35 argument
type Pair { first: i32; second: i32; init() { self.first = 20; self.second = 22 } }
fn main() { let pair = Pair(first:20,second:22); 0 }
