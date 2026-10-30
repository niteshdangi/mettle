// expect-error: type 2:26 requires integer operands
fn value<const C: char = 'a' + 'b'>(): char { C }
fn main() { 0 }
