// arch: aarch64

fn main() {
    var floating = 0.0f64
    var storage = 42
    let pointer = core::ptr::from_mut(storage)
    var address = 0usize
    unsafe {
        asm!("mov {out}, {input}",out = out(reg) floating,input = in(reg) 1.25f64,
             options(pure,nomem,nostack,preserves_flags))
        asm!("add {pointer}, {pointer}, #0",pointer = inout(reg) pointer => address,options(nomem,nostack))
    }
    if floating == 1.25f64 && address == pointer.addr() && storage == 42 { 0 } else { 1 }
}
