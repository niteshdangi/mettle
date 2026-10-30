// arch: x86_64

fn main() {
    if is_x86_feature_detected!("avx2") {
        let vector = unsafe { core::arch::x86_64::_mm256_set1_epi32(42) }
        let lanes = unsafe { core::mem::transmute::<[i32;8]>(vector) }
        if lanes[5] == 42 { 0 } else { 1 }
    } else { 0 }
}
