// expect-error-count: 1
// expect-error: lex 3:26 raw text literals were removed; use a """ text block
fn main(): i32 { let a = r"abc"; 0 }
