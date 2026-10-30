// arch: aarch64

fn main() {
    var answer = 0i32
    unsafe {
        asm!("add w0, w0, #1",
             in("x0") 41i64,
             lateout("w0") answer,
             options(nomem,nostack))
    }
    if answer == 42 { 0 } else { 1 }
}
