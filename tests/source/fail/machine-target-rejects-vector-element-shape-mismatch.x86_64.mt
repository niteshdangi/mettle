// arch: x86_64
// expect-error: type 3:104 expected core::arch::
fn main() { unsafe { let value=core::arch::x86_64::_mm_set1_ps(1.0f32);core::arch::x86_64::_mm_add_epi32(value,value) }; 0 }
