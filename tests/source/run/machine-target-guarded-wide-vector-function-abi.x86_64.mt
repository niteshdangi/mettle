// arch: x86_64

@target_feature("avx2")
unsafe fn identity(value:core.arch.x86_64.__m256i):core.arch.x86_64.__m256i {
    core.arch.x86_64._mm256_add_epi32(
        plain(core.arch.x86_64._mm256_set1_epi32(0),value),
        core.arch.x86_64._mm256_set1_epi32(1))
}
fn plain<T:Copy>(first:T,second:T):T { second }
@target_feature("avx")
unsafe extern "C" fn foreign(value:core.arch.x86_64.__m256i):core.arch.x86_64.__m256i {
    value
}
fn main() {
    if is_x86_feature_detected!("avx2") {
        let value = unsafe { core.mem.transmute<core.arch.x86_64.__m256i>([10i32,20i32,30i32,40i32,50i32,60i32,70i32,80i32]) }
        let callback = identity
        let returned = unsafe { foreign(callback(value)) }
        let lanes = unsafe { core.mem.transmute<[i32;8]>(returned) }
        if lanes[0] == 11 && lanes[1] == 21 && lanes[2] == 31 && lanes[3] == 41 &&
           lanes[4] == 51 && lanes[5] == 61 && lanes[6] == 71 && lanes[7] == 81 { 0 } else { 1 }
    } else { 0 }
}
