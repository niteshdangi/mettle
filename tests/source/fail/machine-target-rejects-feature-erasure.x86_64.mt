// arch: x86_64
// expect-error: type 4:13 found unsafe fn
@target_feature("avx2") unsafe fn accelerated(): i32 { 42 }
fn main() { let callback: unsafe fn(): i32 = accelerated; 0 }
