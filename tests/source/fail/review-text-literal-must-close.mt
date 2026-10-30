// expect-error: lex 2:27 unterminated text literal
fn main() { unsafe { asm!("unterminated)
} }
