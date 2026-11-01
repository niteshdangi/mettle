// expect-error: type 4:14 invalid primitive operation or operand types

fn main(): i32 {
    unsafe { 1.0f64.to_int_unchecked<bool>() }
    0
}
