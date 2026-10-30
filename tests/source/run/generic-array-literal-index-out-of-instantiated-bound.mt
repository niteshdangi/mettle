// expect-exit: trap
fn pick<const N: i32>(v: read [i32;N]): i32 { v[5] }
fn main(): i32 { let values = [1, 2, 3]; pick(values) }
