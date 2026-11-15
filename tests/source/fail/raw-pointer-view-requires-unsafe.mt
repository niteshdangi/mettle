// expect-error: unsafe 4:5 operation requires an unsafe block or unsafe function
fn main() {
    let pointer = core.ptr.null<i32>()
    pointer.as_ref_unchecked()
}
