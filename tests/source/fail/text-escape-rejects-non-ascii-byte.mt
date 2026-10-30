// expect-error: lex 2:27 text byte escape requires an ASCII value
fn main() { unsafe { asm!("a\x80b") }; 0 }
