// arch: aarch64

fn main() {
    var value = 0i32
    let pointer = core::ptr::from_mut(value)
    unsafe {
        asm!("mov w8, #42\nstr w8, [{pointer}]", pointer = in(reg) pointer,
        out("w8") _,
        options(nostack))
    }
    if value == 42 { 0 } else { 1 }
}
