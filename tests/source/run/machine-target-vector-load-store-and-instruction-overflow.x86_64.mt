// arch: x86_64

fn main() {
    var input = [20,22,23,2147483647]
    var output = [0,0,0,0]
    let source = core::ptr::from_mut(input).cast::<core::arch::x86_64::__m128i>()
    let destination = core::ptr::from_mut(output).cast::<core::arch::x86_64::__m128i>()
    unsafe {
        let vector = core::arch::x86_64::_mm_loadu_si128(source)
        let sum = core::arch::x86_64::_mm_add_epi32(
            vector,core::arch::x86_64::_mm_set1_epi32(22))
        core::arch::x86_64::_mm_storeu_si128(destination,sum)
    }
    if input[0] == 20 && output[0] == 42 && output[3] == -2147483627 { 0 } else { 1 }
}
