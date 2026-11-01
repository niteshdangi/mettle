// expect-error: type 4:14 invalid primitive operation or operand types

fn main(): i32 {
    unsafe { 1i32.to_int_unchecked<i32>() }
    0
}
