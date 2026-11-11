// expect-error: signature 6:22 variadic argument has no C-compatible representation
copy type Native { value: i32 }
extern "C" { unsafe fn sink(count: i32, ...): Unit; }
fn main() {
    let values = [Native(7); 65]
    unsafe { sink(0, values) }
    0
}
