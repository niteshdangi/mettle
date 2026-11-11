// expect-error: type 4:5 invalid primitive operation or operand types
copy type Native { value: i32 }
unsafe extern "C" fn callback(count: i32, args: ...): i32 {
    args.arg<[Native; 65]>()
    0
}
fn main() { 0 }
