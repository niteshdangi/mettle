// expect-error: ownership 3:54 cannot move out of a borrowed place
type C { value: i32 }
fn main() { var c = C(1); let p = mut c; let moved = *p; 0 }
