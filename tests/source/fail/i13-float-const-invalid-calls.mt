// profiles: debug release
// expect-error: type 7:38 expected u32, found u64
// expect-error: type 8:42 aggregate lengths do not match
// expect-error: type 9:38 expected f32, found f64
// expect-error: type 10:24 invalid primitive operation or operand types
// expect-error-count: 4
const BAD_WIDTH: f32 = f32.from_bits(1u64)
const BAD_BYTES: f64 = f64.from_le_bytes([0u8; 4])
const BAD_ARGUMENT: f32 = 1.0f32.min(2.0f64)
const BAD_ARITY: f64 = 1.0f64.mul_add(2.0f64)
