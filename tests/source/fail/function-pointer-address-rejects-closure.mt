// expect-error: type 5:5 invalid primitive operation or operand types
fn main(): i32 {
    let captured = 1i32
    let closure = fn(value: i32): i32 { value + captured }
    core.intrinsics.fn_addr(closure)
    0
}
