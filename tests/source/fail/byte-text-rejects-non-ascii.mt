// expect-error-count: 1
// expect-error: lex 3:26 byte text must contain only ASCII characters
fn main(): i32 { let a = b"é"; 0 }
