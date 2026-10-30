// expect-error: type 2:78 may be uninitialized
type Pair { first: i32; second: i32; init() { self.first = 20; self.second = self.sum() }; fn sum() { self.first + self.second } }
fn main() { let pair = Pair(); 0 }
