// expect-error: attribute 2:22 transparent enum representation requires exactly one variant
@layout(transparent) enum Invalid { First(i32); Second(i32) }
fn main() { 0 }
