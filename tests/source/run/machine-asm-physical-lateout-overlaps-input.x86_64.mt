// arch: x86_64

fn main() {
    var answer = 0i32
    unsafe {
        asm!("add eax, 1",
             in("rax") 41i64,
             lateout("eax") answer,
             options(nomem,nostack))
    }
    if answer == 42 { 0 } else { 1 }
}
