// arch: aarch64

fn main() {
    var value: i32
    unsafe {
        asm!("mov {out:w}, #42",out = out(reg) value, options(pure,nomem,nostack))
    }
    if value == 42 { 0 } else { 1 }
}
