// arch: aarch64
// expect-error-count: 1
// expect-error: feature 4:22 architecture operation is unavailable on this target
fn main() { unsafe { core.arch.x86_64._mm_set1_epi32(42) }; 0 }
