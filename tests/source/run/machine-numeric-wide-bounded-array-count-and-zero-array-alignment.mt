
type Tail { first: u8; empty: [u64;0usize] }
fn main() {
    let repeated: [i32;2u128] = [21;2u64]
    if repeated[0] + repeated[1] == 42 &&
       core::mem::size_of::<[u64;0usize]>() == 0usize &&
       core::mem::align_of::<[u64;0usize]>() == 8usize &&
       core::mem::size_of::<Tail>() == 8usize &&
       core::mem::align_of::<Tail>() == 8usize { 0 } else { 1 }
}
