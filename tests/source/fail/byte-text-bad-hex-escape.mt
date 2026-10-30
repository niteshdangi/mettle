// expect-error-count: 1
// expect-error: lex 3:26 byte escape requires two hexadecimal digits
fn main(): i32 { let a = b"\xzz"; 0 }
