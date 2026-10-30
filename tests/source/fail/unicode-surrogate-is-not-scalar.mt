// expect-error: lex 2:25 valid Unicode scalar
fn main() { let value = '\u{d800}'; 0 }
