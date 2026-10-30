// arch: x86_64

@target_feature("avx2")
unsafe fn accelerated(): i32 {
    let vector = core.arch.x86_64._mm256_set1_epi32(42)
    let lanes = core.mem.transmute<[i32;8]>(vector)
    lanes[7]
}
fn main() {
    if is_x86_feature_detected!("avx2") {
        if unsafe { accelerated() } == 42 { 0 } else { 1 }
    } else { 0 }
}
