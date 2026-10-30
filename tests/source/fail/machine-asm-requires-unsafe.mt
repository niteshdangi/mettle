// expect-error: unsafe 2:13 operation requires an unsafe block or unsafe function
fn main() { asm!("nop"); 0 }
