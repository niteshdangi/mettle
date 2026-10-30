// expect-error: unsafe 3:1 manual Unpin implementation requires unsafe impl
type Stable { value: i32 }
extend Stable implements Unpin {}
fn main() { 0 }
