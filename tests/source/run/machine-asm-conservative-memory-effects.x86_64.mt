// arch: x86_64

fn main() {
    var value = 0i32
    let pointer = core.ptr.from_mut(value)
    unsafe {
        asm!("mov dword ptr [{pointer}], 42", pointer = in(reg) pointer,

        options(nostack))
    }
    if value == 42 { 0 } else { 1 }
}
