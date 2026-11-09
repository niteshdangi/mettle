// expect-error: ownership 4:34 live exclusive loan
type C { value: i32 }
fn both(mut a: C,mut b: C) {}
fn main() { var c = C(1); both(c,c); 0 }
