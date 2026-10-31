// arch: aarch64
// expect-error: type 3:104 expected int32x4_t, found float32x4_t
fn main() { unsafe { let value=core.arch.aarch64.vdupq_n_f32(1.0f32);core.arch.aarch64.vaddq_s32(value,value) }; 0 }
