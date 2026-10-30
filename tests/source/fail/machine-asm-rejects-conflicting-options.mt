// expect-error: assembly 2:22 nomem and readonly
fn main() { unsafe { asm!("nop",options(nomem,readonly)) }; 0 }
