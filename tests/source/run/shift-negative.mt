// expect-exit-debug: trap
// expect-exit-release: 0
fn main(): i32 { if (1 >> -1) == 0 { 0 } else { 1 } }
