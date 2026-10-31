// expect-error: parse 3:17 `let mut` is not valid syntax
// expect-help: use `var` for a mutable local binding
fn main() { let mut value = 1 }
