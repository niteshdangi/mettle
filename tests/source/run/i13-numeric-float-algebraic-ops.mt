import core.float

const F32_ADD: f32 = 5.0f32.algebraic_add(2.0f32)
const F32_SUB: f32 = 5.0f32.algebraic_sub(2.0f32)
const F32_MUL: f32 = 5.0f32.algebraic_mul(2.0f32)
const F32_DIV: f32 = 5.0f32.algebraic_div(2.0f32)
const F32_REM: f32 = 5.0f32.algebraic_rem(2.0f32)
const F64_ADD: f64 = 5.0f64.algebraic_add(2.0f64)
const F64_SUB: f64 = 5.0f64.algebraic_sub(2.0f64)
const F64_MUL: f64 = 5.0f64.algebraic_mul(2.0f64)
const F64_DIV: f64 = 5.0f64.algebraic_div(2.0f64)
const F64_REM: f64 = 5.0f64.algebraic_rem(2.0f64)

fn check_f32(): bool {
    let negative_zero = f32.from_bits(0x80000000u32)
    let nan = f32.from_bits(0x7fc00000u32)
    5.0f32.algebraic_add(2.0f32) == 7.0f32 &&
        5.0f32.algebraic_sub(2.0f32) == 3.0f32 &&
        5.0f32.algebraic_mul(2.0f32) == 10.0f32 &&
        5.0f32.algebraic_div(2.0f32) == 2.5f32 &&
        5.0f32.algebraic_rem(2.0f32) == 1.0f32 &&
        negative_zero.algebraic_mul(2.0f32).to_bits() == 0x80000000u32 &&
        nan.algebraic_add(1.0f32).is_nan()
}

fn check_f64(): bool {
    let negative_zero = f64.from_bits(0x8000000000000000u64)
    let nan = f64.from_bits(0x7ff8000000000000u64)
    5.0f64.algebraic_add(2.0f64) == 7.0f64 &&
        5.0f64.algebraic_sub(2.0f64) == 3.0f64 &&
        5.0f64.algebraic_mul(2.0f64) == 10.0f64 &&
        5.0f64.algebraic_div(2.0f64) == 2.5f64 &&
        5.0f64.algebraic_rem(2.0f64) == 1.0f64 &&
        negative_zero.algebraic_mul(2.0f64).to_bits() == 0x8000000000000000u64 &&
        nan.algebraic_add(1.0f64).is_nan()
}

fn main(): i32 {
    if !check_f32() { return 1 }
    if !check_f64() { return 2 }
    if F32_ADD != 7.0f32 || F32_SUB != 3.0f32 || F32_MUL != 10.0f32 ||
       F32_DIV != 2.5f32 || F32_REM != 1.0f32 ||
       F64_ADD != 7.0f64 || F64_SUB != 3.0f64 || F64_MUL != 10.0f64 ||
       F64_DIV != 2.5f64 || F64_REM != 1.0f64 {
        return 3
    }
    0
}
