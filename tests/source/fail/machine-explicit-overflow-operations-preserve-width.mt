// expect-error-count: 1
// expect-error: type 3:42 expected
fn main() { let value = 1u8.wrapping_add(2u16); 0 }
