// profiles: debug release
// expect-error: constant 7:14 constant write requires exclusive access
// expect-error-count: 1
const fn mutation(): u8 {
    let text = "x"
    let pointer = core.slice.data(text.as_bytes()).cast_mut()
    unsafe { *pointer = 65u8 }
    0u8
}
const VALUE: u8 = mutation()
fn main(): i32 { VALUE as i32 }
