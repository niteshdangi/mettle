// expect-exit-debug: trap
// expect-exit-release: 0
fn main(): i32 { let value=u128::MAX; if value+1 == 0u128 { 0 } else { 1 } }
