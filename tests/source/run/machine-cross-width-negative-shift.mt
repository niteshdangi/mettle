// expect-exit-debug: trap
// expect-exit-release: 0
fn main(): i32 { let count=-1i8; if 1u64 << count == 9223372036854775808u64 { 0 } else { 1 } }
