// truncated: the program ends mid-construct; diagnostics refer to its end
// expect-error-count: 1
// expect-error: parse 4:41 expected an assembly operand mode
fn main() { unsafe { asm!("nop", value =