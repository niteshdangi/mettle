// expect-error: lex 2:27 unsupported constant text escape
fn main() { unsafe { asm!("a\q") }; 0 }
