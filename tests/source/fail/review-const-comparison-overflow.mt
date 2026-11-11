// expect-error: constant 5:5 overflow
const fn increment(): u8 {
    var value = 255
    let compared = value == 0u8
    value += 1
    value as u8
}
const VALUE: u8 = increment()
fn main(): i32 { 0 }
