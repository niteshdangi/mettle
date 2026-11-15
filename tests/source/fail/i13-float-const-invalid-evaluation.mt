// profiles: debug release
// expect-error: constant 6:24 clamp bounds require non-NaN min <= max
// expect-error: constant 7:28 clamp bounds require non-NaN min <= max
// expect-error: constant 8:23 call to non-const or unavailable float method 'sqrt'
// expect-error-count: 3
const BAD_CLAMP: f32 = 1.0f32.clamp(2.0f32, 0.0f32)
const BAD_NAN_CLAMP: f64 = 1.0f64.clamp(f64.NAN, 2.0f64)
const NONCONST: f32 = 1.0f32.sqrt()
