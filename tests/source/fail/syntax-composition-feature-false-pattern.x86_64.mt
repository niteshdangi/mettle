// arch: x86_64
// expect-error: feature 6:18 established target feature
@target_feature("avx2") unsafe fn accelerated(): i32 { 42 }
fn main(): i32 {
    if let false = is_x86_feature_detected!("avx2"), true {
        unsafe { accelerated() }
    } else { 0 }
}
