// expect-error: ownership 7:5 access or storage conflicts with a live read loan

union Bits { integer: u32; real: f32 }
fn main() {
    var value = Bits(integer: 42u32)
    let borrowed = unsafe { read value.integer }
    value.real = 0.0f32
    if *borrowed == 42u32 { 0 } else { 1 }
}
