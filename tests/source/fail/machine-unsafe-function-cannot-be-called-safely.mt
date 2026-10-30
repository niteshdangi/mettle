// expect-error: unsafe 3:13 requires an unsafe block
unsafe fn operation(): i32 { 42 }
fn main() { operation() }
