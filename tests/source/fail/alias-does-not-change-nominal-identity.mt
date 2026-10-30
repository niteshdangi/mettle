// expect-error: type 6:21 expected First, found Second
copy type First { value: i32 }
copy type Second { value: i32 }
alias Same = First
fn consume(value: Same) {}
fn main() { consume(Second(42)); 0 }
