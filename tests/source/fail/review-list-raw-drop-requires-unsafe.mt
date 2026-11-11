// expect-error: unsafe 3:13 requires an unsafe block
import alloc.vec.drop_run
fn main() { drop_run<i32>(core.ptr.null_mut<i32>(), 1usize) }
