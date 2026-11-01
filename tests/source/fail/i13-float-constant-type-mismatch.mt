// profiles: debug release
// expect-error: constant 5:24 constant native value has an incompatible type
// expect-error: constant 6:27 constant native value has an incompatible type
// expect-error-count: 2
const BAD_FLOAT: f32 = f64.EPSILON
const BAD_METADATA: f32 = f32.DIGITS

fn main(): i32 { 0 }
