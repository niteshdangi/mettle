// arch: x86_64

@target_feature("avx2")
unsafe fn identity(value:core.arch.x86_64.__m256i):core.arch.x86_64.__m256i {
    core.arch.x86_64._mm256_add_epi32(
        plain(value,core.arch.x86_64._mm256_set1_epi32(41)),
        core.arch.x86_64._mm256_set1_epi32(1))
}
fn plain<T:Copy>(first:T,second:T):T { second }
@target_feature("avx")
unsafe extern "C" fn foreign(value:core.arch.x86_64.__m256i):core.arch.x86_64.__m256i {
    value
}
fn main() {
    if is_x86_feature_detected!("avx2") {
        let value = unsafe { core.arch.x86_64._mm256_set1_epi32(42) }
        let callback = identity
        let returned = unsafe { foreign(callback(value)) }
        let lanes = unsafe { core.mem.transmute::<[i32;8]>(returned) }
        if lanes[0] == 42 && lanes[7] == 42 { 0 } else { 1 }
    } else { 0 }
}
