// expect-error: ownership 3:51 live read loan
type Guard<region r> { view: read i32 from r; drop { let observed = *self.view } }
fn main() { var x = 1; let guard = Guard(read x); x = 2; 0 }
