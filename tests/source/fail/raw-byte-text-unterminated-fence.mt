// expect-error-count: 1
// expect-error: lex 3:26 unterminated raw text literal
fn main(): i32 { let a = br#"abc"; 0 }
