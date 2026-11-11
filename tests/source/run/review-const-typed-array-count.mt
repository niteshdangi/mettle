const fn first(values: [i32; 2u8]): i32 { values[0usize] }
const fn empty(values: [i32; -0i8]): i32 { 0 }
const VALUE: i32 = first([5, 6])
const ZERO: i32 = empty([])
fn main(): i32 { VALUE + ZERO - 5 }
