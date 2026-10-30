// arch: aarch64

fn main() {
    unsafe {
        var left = core.arch.aarch64.vdupq_n_s32(20)
        let right = core.arch.aarch64.vdupq_n_s32(22)
        asm!("add {left:v}.4s, {left:v}.4s, {right:v}.4s",
             left = inlateout(vreg) left, right = in(vreg_low16) right,
             options(pure,nomem,nostack,preserves_flags))
        if core.arch.aarch64.vgetq_lane_s32(left,3) == 42 { 0 } else { 1 }
    }
}
