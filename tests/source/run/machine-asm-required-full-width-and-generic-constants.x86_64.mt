// arch: x86_64

static OFFSET: i128 = (1i128 << 80) + 42;
unsafe fn answer<const N:i64>(value:i32):i32 {
    var result = value
    asm!("add {value:e}, {amount}",
         value = inout(reg) result, amount = const N,
         options(nomem,nostack))
    asm!("add {value:e}, {amount}",
         value = inout(reg) result, amount = const OFFSET - (1i128 << 80),
         options(nomem,nostack))
    result
}
fn main() { if unsafe { answer<1i64>(-1) } == 42 { 0 } else { 1 } }
