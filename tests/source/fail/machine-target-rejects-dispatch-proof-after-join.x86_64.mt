// arch: x86_64
// expect-error: feature 4:67 target operation/call requires established target feature availability
@target_feature("avx2") unsafe fn accelerated(): i32 { 42 }
fn main() { if is_x86_feature_detected!("avx2") { }; unsafe { accelerated() }; 0 }
