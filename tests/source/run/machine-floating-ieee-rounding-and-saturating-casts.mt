
fn main() {
    let direct: f32 = 1.0000000596046448
    let through_double: f64 = 1.0000000596046448
    let zero: f64 = 0.0
    let infinity = 1.0f64 / zero
    let nan = zero / zero
    let negative_zero: f32 = -0.0
    let small: f32 = 1e-45
    let rounded = 16777217u32 as f32
    if direct == 1.00000011920928955078125f32 &&
       through_double as f32 == 1.0f32 &&
       1.0f32 / negative_zero < 0.0f32 &&
       infinity as i8 == 127i8 && (-infinity) as i8 == -128i8 &&
       nan as u64 == 0u64 && nan != nan &&
       3.9f64 as i16 == 3i16 && -3.9f64 as i16 == -3i16 &&
       small > 0.0f32 && rounded == 16777216.0f32 &&
       5.5f64 % 2.0f64 == 1.5f64 { 0 } else { 1 }
}
