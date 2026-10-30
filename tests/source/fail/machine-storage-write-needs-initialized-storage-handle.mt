// expect-error: type 2:67 storage handle may be uninitialized
fn main() { var value: core::mem::MaybeUninit<i32>; let reference=value.write(42); *reference }
