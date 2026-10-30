// expect-error: ownership 2:56 mutable place
fn main() { var x = 1; let p = read x; let child = mut *p; 0 }
