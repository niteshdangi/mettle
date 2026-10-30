// arch: aarch64

fn main() {
    var input = [20,22,23,2147483647]
    var output = [0,0,0,0]
    let source = core::ptr::from_mut(input[0])
    let destination = core::ptr::from_mut(output[0])
    unsafe {
        let vector = core::arch::aarch64::vld1q_s32(source)
        let sum = core::arch::aarch64::vaddq_s32(
            vector,core::arch::aarch64::vdupq_n_s32(22))
        core::arch::aarch64::vst1q_s32(destination,sum)
    }
    if input[0] == 20 && output[0] == 42 && output[3] == -2147483627 { 0 } else { 1 }
}
