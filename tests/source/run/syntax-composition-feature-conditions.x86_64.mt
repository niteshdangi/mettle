// arch: x86_64

@target_feature("avx2")
unsafe fn accelerated(): i32 {
    let vector = core.arch.x86_64._mm256_set1_epi32(42)
    let lanes = core.mem.transmute<[i32;8]>(vector)
    lanes[7]
}

fn main(): i32 {
    if is_x86_feature_detected!("avx2"), true {
        if unsafe { accelerated() } != 42 { return 1 }
    }
    if true, is_x86_feature_detected!("avx2"), unsafe { accelerated() } != 42 {
        return 2
    }
    0
}
