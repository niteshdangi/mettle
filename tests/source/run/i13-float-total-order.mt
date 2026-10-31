import core.float
import core.cmp.Ordering

fn main(): i32 {
    let negative_nan = f64.from_bits(0xfff8000000000001u64)
    let later_negative_nan = f64.from_bits(0xfff8000000000002u64)
    let negative_infinity = f64.from_bits(0xfff0000000000000u64)
    let negative_zero = f64.from_bits(0x8000000000000000u64)
    let positive_zero = f64.from_bits(0u64)
    let positive_infinity = f64.from_bits(0x7ff0000000000000u64)
    let positive_nan = f64.from_bits(0x7ff8000000000001u64)
    let later_nan = f64.from_bits(0x7ff8000000000002u64)
    let f32_negative_zero = f32.from_bits(0x80000000u32)
    let f32_positive_zero = f32.from_bits(0u32)

    if !negative_nan.total_cmp(later_negative_nan).is_gt() ||
        !negative_nan.total_cmp(negative_infinity).is_lt() ||
        !negative_infinity.total_cmp(negative_zero).is_lt() ||
        !negative_zero.total_cmp(positive_zero).is_lt() ||
        !positive_zero.total_cmp(positive_infinity).is_lt() ||
        !positive_infinity.total_cmp(positive_nan).is_lt() ||
        !positive_nan.total_cmp(later_nan).is_lt() ||
        !later_nan.total_cmp(positive_nan).is_gt() ||
        negative_zero.total_cmp(negative_zero) != Ordering.Equal ||
        positive_nan.total_cmp(positive_nan) != Ordering.Equal ||
        !f32_negative_zero.total_cmp(f32_positive_zero).is_lt() {
        return 1
    }
    0
}
