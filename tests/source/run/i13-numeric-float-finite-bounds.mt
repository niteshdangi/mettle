const F32_MAX: f32 = f32.MAX
const F32_MIN: f32 = f32.MIN
const F64_MAX: f64 = f64.MAX
const F64_MIN: f64 = f64.MIN

fn main(): i32 {
    if F32_MAX.to_bits() != 0x7f7fffffu32 ||
        F32_MIN.to_bits() != 0xff7fffffu32 ||
        F64_MAX.to_bits() != 0x7fefffffffffffffu64 ||
        F64_MIN.to_bits() != 0xffefffffffffffffu64 {
        return 1
    }
    if f32.MAX != F32_MAX || f32.MIN != F32_MIN ||
        f64.MAX != F64_MAX || f64.MIN != F64_MIN {
        return 2
    }
    0
}
