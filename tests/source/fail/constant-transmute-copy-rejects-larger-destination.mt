// expect-error-count: 1
// expect-error: constant 5:14 destination is larger than source
const fn invalid(): u64 {
    let value = 1u8
    unsafe { core.mem.transmute_copy<u64>(read value) }
}
const INVALID: u64 = invalid()
fn main(): i32 { 0 }
