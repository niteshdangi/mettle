// expect-error-count: 1
// expect-error: type 3:26 invalid scalar conversion
fn main(): i32 { let c = 233u32 as char; let d = c; 0 }
