// arch: x86_64
// expect-error: feature 4:22 established target feature
@target_feature("avx2") unsafe fn accelerated(): i32 { 42 }
fn main() { unsafe { accelerated() }; 0 }
