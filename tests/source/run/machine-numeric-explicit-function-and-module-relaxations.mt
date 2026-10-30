
@fast_math(contract)
fn multiply_add(a:f32,b:f32,c:f32): f32 { a * b + c }
@fast_math(contract)
fn defaulted(a:f32,b:f32,c:f32=a*b+1.0f32): f32 { c }
@fast_math(contract)
fn closure(a:f32,b:f32,c:f32): f32 {
    let operation=fn(x:f32,y:f32,z:f32):f32{x*y+z}
    operation(a,b,c)
}
@fast_math(no_nans,no_infinities,no_signed_zeros)
fn checked(value:f64): bool {
    match value.checked_cast::<i8>() { none => true, present(item) => false }
}
@fast_math(reassociate,reciprocal,approximate_functions)
module relaxed {
    pub fn calculate(a:f64,b:f64,c:f64): f64 { (a + b) + c }
}
fn strict(value:f64): bool {
    let nan = 0.0f64 / 0.0f64
    value.to_bits() == 0x8000000000000000u64 && nan != nan
}
fn separate(a:f32,b:f32,c:f32): f32 { a*b+c }
fn main() {
    if multiply_add(2.0f32,10.0f32,22.0f32) == 42.0f32 &&
       defaulted(2.0f32,10.0f32) == 21.0f32 &&
       closure(2.0f32,10.0f32,22.0f32) == 42.0f32 &&
       checked(f64::from_bits(0x7ff8000000000042u64)) &&
       relaxed::calculate(20.0f64,20.0f64,2.0f64) == 42.0f64 &&
       separate(1.00000011920928955078125f32,0.99999988079071044921875f32,-1.0f32) == 0.0f32 &&
       1.00000011920928955078125f32.mul_add(
           0.99999988079071044921875f32,-1.0f32) != 0.0f32 &&
       strict(-0.0f64) { 0 } else { 1 }
}
