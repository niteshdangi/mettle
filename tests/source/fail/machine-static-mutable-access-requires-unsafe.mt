// expect-error: unsafe 2:41 requires an unsafe
static mut VALUE: i32 = 42; fn main() { VALUE; 0 }
