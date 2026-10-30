// arch: x86_64
// expect-error-count: 1
// expect-error: feature 4:22 architecture operation is unavailable on this target
fn main() { unsafe { core::arch::aarch64::vdupq_n_s32(42) }; 0 }
