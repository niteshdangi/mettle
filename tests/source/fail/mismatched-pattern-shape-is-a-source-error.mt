// expect-error-count: 1
// expect-error: type 3:26 incompatible aggregate shape
fn main() { match true { present(value) => 0, _ => 1 } }
