import core.float.{FpCategory}

alias Float32 = f32

const fn echo32(value: Float32): Float32 { value }
const fn echo64(value: f64): f64 { value }

const CONTEXT: Float32 = echo32(1.00000005960464477539062500000000000001)
const ALIAS: Float32 = Float32.from_bits(0x3f800001u32)
const SNAN32: f32 = f32.from_bits(0xff812345u32)
const SNAN64: f64 = echo64(f64.from_bits(0xfff0123456789abcu64))
const U128_FLOAT: f32 = u128.MAX as f32
const I128_FLOAT: f64 = i128.MIN as f64
const SAT_MIN: i128 = f64.NEG_INFINITY as i128
const SAT_MAX: u128 = f64.INFINITY as u128
const CAST_NAN: i32 = f32.NAN as i32
const CAST_NEGATIVE: u32 = -1.0f64 as u32
const WIDTH_CAST: f32 = 1.5f64 as f32
const FRACT_ZERO: u64 = (-2.0f64).fract().to_bits()
const NAN_CATEGORY: FpCategory = f32.NAN.classify()
const ZERO_CATEGORY: FpCategory = (-0.0f64).classify()
const NAN_EQUAL: bool = f64.NAN == f64.NAN
const NAN_UNEQUAL: bool = f64.NAN != f64.NAN
const NAN_MIDPOINT: f64 = f64.NAN.midpoint(f64.INFINITY)
const INF_MIDPOINT: f32 = f32.INFINITY.midpoint(f32.NEG_INFINITY)
const ARITHMETIC: f32 = 1.25 + 2.5

fn main(): i32 {
    if CONTEXT.to_bits() != 0x3f800001u32 || ALIAS != CONTEXT {
        return 1
    }
    if SNAN32.to_bits() != 0xff812345u32 ||
       SNAN64.to_bits() != 0xfff0123456789abcu64 {
        return 2
    }
    if !U128_FLOAT.is_infinite() || I128_FLOAT != -170141183460469231731687303715884105728.0f64 ||
       SAT_MIN != i128.MIN || SAT_MAX != u128.MAX || CAST_NAN != 0 ||
       CAST_NEGATIVE != 0u32 || WIDTH_CAST != 1.5f32 {
        return 3
    }
    if FRACT_ZERO != 0x8000000000000000u64 ||
       NAN_CATEGORY != FpCategory.Nan || ZERO_CATEGORY != FpCategory.Zero ||
       NAN_EQUAL || !NAN_UNEQUAL || !NAN_MIDPOINT.is_nan() ||
       !INF_MIDPOINT.is_nan() || ARITHMETIC != 3.75f32 {
        return 4
    }
    0
}
