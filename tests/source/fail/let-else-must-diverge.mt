// expect-error: type 2:70 must diverge
fn main() { let value: i32? = none; let present(answer) = value else { 0 }; answer }
