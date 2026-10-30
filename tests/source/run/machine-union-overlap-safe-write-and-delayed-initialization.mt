
@layout(C)
union Bits { integer: u32, real: f32 }
union Generic<T: Copy> { value: T; bytes: u64 }
fn main() {
    var bits = Bits(integer: 0x3f800000u32)
    let first = unsafe { bits.real }
    bits.real = 2.0f32
    let second = unsafe { bits.integer }
    var delayed: Bits
    delayed.integer = 42u32
    let answer = unsafe { delayed.integer }
    let generic = Generic::<i32>(value: 42)
    let value = unsafe { generic.value }
    if first == 1.0f32 && second == 0x40000000u32 && answer == 42u32 &&
       value == 42 && core::mem::size_of::<Bits>() == 4usize { 0 } else { 1 }
}
