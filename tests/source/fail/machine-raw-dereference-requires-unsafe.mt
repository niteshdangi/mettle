// expect-error: unsafe 2:66 requires an unsafe block
fn main() { let value = 42; let p = read value as ptr<read i32>; *p }
