// expect-exit-debug: trap
// expect-exit-release: 0
// Plain `abs` checks overflow like other arithmetic: it traps in debug and
// wraps to MIN in release.
fn main(): i32 {
    let minimum = i32.MIN
    if minimum.abs() == i32.MIN { 0 } else { 1 }
}
