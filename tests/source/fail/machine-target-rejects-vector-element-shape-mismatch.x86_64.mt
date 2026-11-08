// arch: x86_64
// expect-error: type 3:100 expected __m128i, found __m128
fn main() { unsafe { let value=core.arch.x86_64._mm_set1_ps(1.0f32);core.arch.x86_64._mm_add_epi32(value,value) }; 0 }
