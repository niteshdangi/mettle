// expect-error: constant 6:5 overflow
alias Bytes = [u8; increment()]
const fn increment() {
    var value = 255
    let compared = value == 0u8
    value += 1
    value as usize
}
fn main(): i32 { 0 }
