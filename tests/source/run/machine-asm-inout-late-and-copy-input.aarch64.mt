// arch: aarch64

fn main() {
    var value = 20i32
    let input = 22i32
    unsafe {
        asm!("add {value:w}, {value:w}, {input:w}",
             value = inout(reg) value,
             input = in(reg) input, options(nomem,nostack))
    }
    var result = 0
    unsafe {
        asm!("mov {out:w}, {input:w}", input = in(reg) value,
             out = lateout(reg) result, options(pure,nomem,nostack))
    }
    if result == 42 && value == 42 && input == 22 { 0 } else { 1 }
}
