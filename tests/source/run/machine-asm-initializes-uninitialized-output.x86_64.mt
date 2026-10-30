// arch: x86_64

fn main() {
    var value: i32
    unsafe {
        asm!("mov {out:e}, 42",out = out(reg) value, options(pure,nomem,nostack))
    }
    if value == 42 { 0 } else { 1 }
}
