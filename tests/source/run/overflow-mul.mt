// expect-exit-debug: trap
// expect-exit-release: 0
fn main(): i32 { let x = 1073741824; if x * 2 == -2147483648 { 0 } else { 1 } }
