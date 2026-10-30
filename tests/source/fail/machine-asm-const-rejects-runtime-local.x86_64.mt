// arch: x86_64
// expect-error: type 9:56 required constant

fn main() {
    let amount = 42
    var result = 0
    unsafe {
        asm!("add {value:e}, {amount}",
             value = inout(reg) result, amount = const amount)
    }
    0
}
