// expect-error: ownership 4:34 live read loan
type C { value: i32 }
fn both(a: C,b: mut C) {}
fn main() { var c = C(1); both(c,c); 0 }
