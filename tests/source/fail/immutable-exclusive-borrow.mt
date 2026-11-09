// expect-error: ownership 4:34 mutable place
type C { value: i32 }
fn change(mut c: C) { c.value += 1 }
fn main() { let c = C(1); change(c); 0 }
