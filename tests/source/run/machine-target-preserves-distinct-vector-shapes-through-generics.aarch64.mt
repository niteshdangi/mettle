// arch: aarch64

fn identity<T:Copy>(value:T):T { value }
fn main() {
    unsafe {
        let short = identity(core::arch::aarch64::vdup_n_s32(42))
        let wide = identity(core::arch::aarch64::vdupq_n_s32(20))
        if core::arch::aarch64::vget_lane_s32(short,1) == 42 &&
           core::arch::aarch64::vgetq_lane_s32(wide,3) == 20 &&
           core::mem::size_of::<core::arch::aarch64::int32x2_t>() == 8usize {
            0
        } else { 1 }
    }
}
