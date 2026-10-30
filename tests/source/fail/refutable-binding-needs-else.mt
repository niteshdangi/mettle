// expect-error: type 2:41 refutable pattern
fn main() { let value: i32? = none; let present(answer) = value; answer }
