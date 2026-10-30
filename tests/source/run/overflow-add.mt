// expect-exit-debug: trap
// expect-exit-release: 0
fn main(): i32 { let x = 2147483647; if x + 1 == -2147483648 { 0 } else { 1 } }
