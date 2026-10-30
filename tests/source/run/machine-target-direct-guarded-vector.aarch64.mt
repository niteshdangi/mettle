// arch: aarch64

fn main() {
    if is_aarch64_feature_detected!("neon") {
        let vector = unsafe { core.arch.aarch64.vdupq_n_s32(42) }
        if unsafe { core.arch.aarch64.vgetq_lane_s32(vector,2) } == 42 { 0 } else { 1 }
    } else { 1 }
}
