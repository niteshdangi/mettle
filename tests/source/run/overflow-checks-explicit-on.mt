// expect-exit: trap
// profiles: release
// flags: --overflow-checks on
fn main() { let x = 2147483647; x + 1 }
