// expect-error: lex 2:27 incomplete byte escape
fn main() { unsafe { asm!("a\x4") }; 0 }
