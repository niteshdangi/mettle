// arch: x86_64

fn main() {
    let input = 340282366920938463463374607431768211413u128
    var output = 0u128
    unsafe {
        asm!("movdqa {out:x}, {input:x}",out = out(xmm_reg) output,
             input = in(xmm_reg) input,options(pure,nomem,nostack,preserves_flags))
    }
    if input == output { 0 } else { 1 }
}
