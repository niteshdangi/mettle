
fn sink(value: take u8): u8 { value }
fn pick(digits: read [u8], i: usize): u8 { let d = digits[i]; sink(d) }
fn main(): i32 { let a = [7u8, 8u8]; if pick(a, 1usize) != 8u8 { return 1 }; 0 }
