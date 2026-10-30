// expect-error: unsafe 3:1 manual Unpin implementation requires an unsafe extend
type Stable { value: i32 }
extend Stable implements Unpin {}
fn main() { 0 }
