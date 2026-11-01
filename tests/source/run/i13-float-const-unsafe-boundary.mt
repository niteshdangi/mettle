unsafe const fn echo(value: f32): f32 { value }
const VALUE: f32 = unsafe { echo(1.25f32) }
fn main(): i32 {
    if VALUE == 1.25f32 { 0 } else { 1 }
}
