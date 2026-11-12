// expect-exit: trap
fn main(): i32 { let values=[42]; let index=0usize.wrapping_sub(1usize); values[index] }
