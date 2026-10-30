// arch: x86_64

fn step(counter: ptr<mut i32>, value: i32): i32 {
    unsafe { *counter = *counter * 10 + value }
    value
}
fn destination(counter: ptr<mut i32>, output: ptr<mut i32>): ptr<mut i32> {
    unsafe { *counter = *counter * 10 + 3 }
    output
}
fn main() {
    var order = 0
    var result = 0
    let counter = core.ptr.from_mut(order)
    let output = core.ptr.from_mut(result)
    unsafe {
        asm!("mov {out:e}, {left:e}; add {out:e}, {right:e}",
             left = in(reg) step(counter,1),
             right = in(reg) step(counter,2),
             out = out(reg) *destination(counter,output),
             options(nomem,nostack))
    }
    if order == 123 && result == 3 { 0 } else { 1 }
}
