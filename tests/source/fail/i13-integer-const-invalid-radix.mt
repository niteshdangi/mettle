// profiles: debug release
// expect-error-source: core/num.mt
// expect-error: constant 2833:23 panic during constant evaluation
// expect-error: constant 2858:23 panic during constant evaluation
// expect-error: constant 2903:13 panic during constant evaluation
// expect-error-count: 3
import core.num

const ZERO: i8 = match capture num.parse_radix<i8>("1", 0u32) {
    success(value) => value,
    failure(_) => 0i8
}
const ONE: isize = match capture num.parse_radix<isize>("", 1u32) {
    success(value) => value,
    failure(_) => 0isize
}
const HIGH: u128 = match capture num.parse_radix<u128>("1", 37u32) {
    success(value) => value,
    failure(_) => 0u128
}
fn main(): i32 { 0 }
