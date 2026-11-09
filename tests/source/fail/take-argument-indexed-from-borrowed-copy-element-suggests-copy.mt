// expect-error: ownership 3:49 consumes its value, so copy it into a binding first
fn sink(take value: u8): u8 { value }
fn pick(read digits: [u8], i: usize): u8 { sink(digits[i]) }
fn main(): i32 { 0 }
