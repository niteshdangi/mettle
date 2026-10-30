// arch: aarch64
// expect-error: type 3:119 constant integer
fn main() { let lane=1; unsafe { let vector=core.arch.aarch64.vdupq_n_s32(42);core.arch.aarch64.vgetq_lane_s32(vector,lane) }; 0 }
