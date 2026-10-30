// arch: x86_64

fn main() {
    unsafe {
        var left = core.arch.x86_64._mm_set1_epi32(20)
        let right = core.arch.x86_64._mm_set1_epi32(22)
        asm!("paddd {left:x}, {right:x}",
             left = inlateout(xmm_reg) left, right = in(xmm_reg) right,
             options(pure,nomem,nostack,preserves_flags))
        let lanes = core.mem.transmute<[i32;4]>(left)
        if lanes[3] == 42 { 0 } else { 1 }
    }
}
