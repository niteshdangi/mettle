// arch: x86_64

fn identity<T:Copy>(value:T):T { value }
fn main() {
    unsafe {
        let floating = identity(core::arch::x86_64::_mm_set1_ps(1.25f32))
        let integer = identity(core::arch::x86_64::_mm_set1_epi32(42))
        let floats = core::mem::transmute::<[f32;4]>(floating)
        let ints = core::mem::transmute::<[i32;4]>(integer)
        if floats[2] == 1.25f32 && ints[3] == 42 { 0 } else { 1 }
    }
}
