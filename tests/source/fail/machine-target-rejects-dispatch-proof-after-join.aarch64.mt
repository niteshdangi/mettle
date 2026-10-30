// arch: aarch64
// expect-error: feature 4:67 target operation/call requires established target feature availability
@target_feature("aes") unsafe fn accelerated(): i32 { 42 }
fn main() { if is_aarch64_feature_detected!("neon") { }; unsafe { accelerated() }; 0 }
