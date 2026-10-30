// arch: aarch64

fn main() {
    unsafe {
        let left = core.arch.aarch64.vdupq_n_s32(20)
        let right = core.arch.aarch64.vdupq_n_s32(22)
        let sum = core.arch.aarch64.vaddq_s32(left,right)
        let changed = core.arch.aarch64.vsetq_lane_s32(7,sum,0)
        if core.arch.aarch64.vgetq_lane_s32(sum,3) == 42 &&
           core.arch.aarch64.vgetq_lane_s32(changed,0) == 7 &&
           core.arch.aarch64.vgetq_lane_s32(left,1) == 20 &&
           core.mem.size_of<core.arch.aarch64.int32x4_t>() == 16usize &&
           core.mem.align_of<core.arch.aarch64.int32x4_t>() == 16usize {
            0
        } else { 1 }
    }
}
