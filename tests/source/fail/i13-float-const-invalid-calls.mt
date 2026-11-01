// profiles: debug release
// expect-error: constant 10:38 expected u32, found u64
// expect-error: constant 11:42 expected an array of 8 elements, found 4
// expect-error: constant 12:38 mismatched floating types in constant expression
// expect-error: constant 13:24 wrong number of float method arguments
// expect-error: constant 14:24 clamp bounds require non-NaN min <= max
// expect-error: constant 15:28 clamp bounds require non-NaN min <= max
// expect-error: constant 16:23 call to non-const or unavailable float method 'sqrt'
// expect-error-count: 7
const BAD_WIDTH: f32 = f32.from_bits(1u64)
const BAD_BYTES: f64 = f64.from_le_bytes([0u8; 4])
const BAD_ARGUMENT: f32 = 1.0f32.min(2.0f64)
const BAD_ARITY: f64 = 1.0f64.mul_add(2.0f64)
const BAD_CLAMP: f32 = 1.0f32.clamp(2.0f32, 0.0f32)
const BAD_NAN_CLAMP: f64 = 1.0f64.clamp(f64.NAN, 2.0f64)
const NONCONST: f32 = 1.0f32.sqrt()
