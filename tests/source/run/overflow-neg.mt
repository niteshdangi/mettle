// expect-exit-debug: trap
// expect-exit-release: 0
fn main(): i32 { let x = -2147483648; if -x == x { 0 } else { 1 } }
