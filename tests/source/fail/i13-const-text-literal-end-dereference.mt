// profiles: debug release
// expect-error: constant 6:14 constant pointer is dangling, misaligned or out of bounds
// expect-error-count: 1
const fn past_end(): u8 {
    let pointer = core.slice.data("abc".as_bytes())
    unsafe { *pointer.add(3usize) }
}
const VALUE: u8 = past_end()
fn main(): i32 { VALUE as i32 }
