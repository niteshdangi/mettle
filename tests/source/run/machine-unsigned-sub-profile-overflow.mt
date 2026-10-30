// expect-exit-debug: trap
// expect-exit-release: 0
fn main(): i32 { let value=0u8; if value-1 == 255u8 { 0 } else { 1 } }
