// expect-error: type 3:13 found unsafe fn
unsafe fn operation(): i32 { 42 }
fn main() { let p: fn(): i32 = operation; p() }
