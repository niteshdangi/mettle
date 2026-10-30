// expect-error-count: 1
// expect-error: lex 3:26 invalid text escape
fn main(): i32 { let a = b"\u{41}"; 0 }
