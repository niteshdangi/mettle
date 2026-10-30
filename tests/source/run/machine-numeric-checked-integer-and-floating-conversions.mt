
fn missing<T:Copy>(value:T?): bool {
    match value { none => true, present(item) => false }
}
fn signed(value:i8?, expected:i8): bool {
    match value { none => false, present(item) => item == expected }
}
fn byte(value:u8?, expected:u8): bool {
    match value { none => false, present(item) => item == expected }
}
fn wide(value:u128?, expected:u128): bool {
    match value { none => false, present(item) => item == expected }
}
fn main() {
    let large = 340282366920938463463374607431768211455u128
    let nan = f64.from_bits(0x7ff8000000000042u64)
    if signed(127.9f64.checked_cast<i8>(),127i8) &&
       signed((-128.9f64).checked_cast<i8>(),-128i8) &&
       byte((-0.5f64).checked_cast<u8>(),0u8) &&
       missing(128.0f64.checked_cast<i8>()) &&
       missing((-129.0f64).checked_cast<i8>()) &&
       missing(nan.checked_cast<u128>()) &&
       missing((1.0f64 / 0.0f64).checked_cast<i128>()) &&
       missing(18446744073709551616u128.checked_cast<u64>()) &&
       missing(large.checked_cast<i128>()) &&
       missing((-1i128).checked_cast<u128>()) &&
       byte(255u128.checked_cast<u8>(),255u8) &&
       wide(170141183460469231731687303715884105727i128.checked_cast<u128>(),
            170141183460469231731687303715884105727u128) &&
       wide(340282346638528859811704183484516925440.0f32.checked_cast<u128>(),
            340282346638528859811704183484516925440u128) &&
       nan as i8 == 0i8 && 128.0f64 as i8 == 127i8 { 0 } else { 1 }
}
