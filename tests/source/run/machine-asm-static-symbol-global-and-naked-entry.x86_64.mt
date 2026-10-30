// arch: x86_64

static VALUE: i32 = 42;
extern "C" { static ADDRESS: ptr<read i32>; }
global_asm!(".data\n.globl {address}\n.p2align 3\n{address}:\n.quad {value}\n.text",
            address = sym ADDRESS, value = sym VALUE)
unsafe extern "C" fn read_value():i32 { *ADDRESS }
@naked
unsafe extern "C" fn answer():i32 {
    naked_asm!("jmp {callee}",
               callee = sym read_value)
}
fn main() {
    var pointer: ptr<read i32> = core.ptr.null<i32>()
    unsafe {
        asm!("lea {out}, [rip + {value}]",
             out = out(reg) pointer, value = sym VALUE, options(nomem,nostack))
        if *pointer == 42 && answer() == 42 { 0 } else { 1 }
    }
}
