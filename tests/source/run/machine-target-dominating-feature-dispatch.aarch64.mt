// arch: aarch64

@target_feature("neon")
unsafe fn accelerated(): i32 {
    let vector = core.arch.aarch64.vdupq_n_s32(42)
    core.arch.aarch64.vgetq_lane_s32(vector,0)
}
fn main() {
    if is_aarch64_feature_detected!("neon") {
        if unsafe { accelerated() } == 42 { 0 } else { 1 }
    } else { 1 }
}
