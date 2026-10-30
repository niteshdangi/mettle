// expect-error: ownership 5:42 live read loan
type C { value: i32 }
fn outer(a: C,b: i32) {}
fn change(c: mut C) { c.value += 1; 0 }
fn main() { var c = C(1); outer(c,change(c)); 0 }
