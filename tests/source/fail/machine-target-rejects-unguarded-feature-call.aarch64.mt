// arch: aarch64
// expect-error: feature 4:22 established target feature
@target_feature("aes") unsafe fn accelerated(): i32 { 42 }
fn main() { unsafe { accelerated() }; 0 }
