// expect-error: unsafe 5:5 operation requires an unsafe block or unsafe function
// expect-error-count: 1
import core.ptr.NonNull
fn copy_without_unsafe(pointer: NonNull<u8>): Unit {
    pointer.copy_to(pointer, 0usize)
}
fn main(): i32 { 0 }
