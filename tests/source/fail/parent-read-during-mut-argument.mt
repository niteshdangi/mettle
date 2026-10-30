// expect-error: ownership 4:35 live exclusive loan
type C { value: i32 }
fn outer(a: mut C,b: i32) {}
fn main() { var c = C(1); outer(c,c.value); 0 }
