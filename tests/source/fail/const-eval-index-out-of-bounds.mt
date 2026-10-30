// expect-error: constant 3:30 index out of bounds
const TABLE: [i32; 3] = [1, 2, 3];
const fn at(i: usize): i32 { TABLE[i] }
static V: i32 = at(3);
fn main(): i32 { 0 }
