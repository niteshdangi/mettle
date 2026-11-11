// expect-error: constant 3:1 cycle in required static type
const fn width() { ARRAY }
const ARRAY: [u8; width()] = []
fn main(): i32 { 0 }
