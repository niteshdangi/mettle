// arch: aarch64
// expect-error: type 3:107 lane is outside
fn main() { unsafe { let vector=core.arch.aarch64.vdupq_n_s32(42);core.arch.aarch64.vgetq_lane_s32(vector,4) }; 0 }
