// expect-error: ownership 3:48 live read loan
type Guard<region r> { value: read i32 from r; drop { let observed = *self.value } }
fn main() { let guard = loop { let owned = 42; break Guard(read owned) }; 0 }
