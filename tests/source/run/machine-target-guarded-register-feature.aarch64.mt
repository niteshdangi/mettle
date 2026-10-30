// arch: aarch64

fn main() {
    if is_aarch64_feature_detected!("neon") {
        var answer = 0i64
        unsafe {
            asm!("fmov {value:d}, {input}",value = out(vreg) _,
                 input = in(reg) 42i64, options(nomem,nostack))
            asm!("mov {out}, #42",out = out(reg) answer,options(pure,nomem,nostack))
        }
        if answer == 42 { 0 } else { 1 }
    } else { 1 }
}
