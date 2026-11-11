// arch: aarch64
// expect-error: feature 9:18 target operation/call requires established target feature availability
// expect-error: feature 11:14 target operation/call requires established target feature availability
// expect-error-count: 2
@target_feature("aes")
unsafe fn accelerated(): i32 { 42 }
fn main() {
    if is_aarch64_feature_detected!("neon") {
        unsafe { accelerated() };
    }
    unsafe { accelerated() };
    0
}
