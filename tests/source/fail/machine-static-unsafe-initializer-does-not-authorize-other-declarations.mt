// expect-error: unsafe 2:106 requires an unsafe
static mut VALUE: i32 = 1; static FIRST: ptr<mut i32> = unsafe { SECOND }; static SECOND: ptr<mut i32> = core.ptr.from_mut(VALUE); fn main() { 0 }
