// arch: x86_64

fn main() {
    var value = 20i32
    let input = 22i32
    unsafe {
        asm!("add {value:e}, {input:e}",
             value = inout(reg) value,
             input = in(reg) input, options(nomem,nostack))
    }
    var result = 0
    unsafe {
        asm!("mov {out:e}, {input:e}", input = in(reg) value,
             out = lateout(reg) result, options(pure,nomem,nostack))
    }
    if result == 42 && value == 42 && input == 22 { 0 } else { 1 }
}
