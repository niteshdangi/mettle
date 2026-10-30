// expect-error: type 4:1 not Copy
type Owned { value: i32 }
alias Same = Owned
copy type Wrapper { value: Same }
fn main() { 0 }
