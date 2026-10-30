// arch: x86_64

fn main() {
    var result = 0i32
    unsafe {
        asm!("mov {out:e}, {constant}",
             constant = const (20 + 22), out = out(reg) result,
             options(pure,nomem,nostack,preserves_flags))
        asm!("nop", options(raw,nomem,nostack,preserves_flags))
    }
    if result == 42 { 0 } else { 1 }
}
