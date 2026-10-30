// expect-error: ownership 4:13 live read loan
type C { value: i32 }
fn identity(c: C): read C from c { read c }
fn main() { let v = identity(C(42)); v.value }
