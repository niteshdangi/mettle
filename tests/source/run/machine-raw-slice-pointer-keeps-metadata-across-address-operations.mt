
fn total(read values: [i32]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
const fn fixed<const N: usize>(
    pointer: ptr<read [i32]>
): ptr<read [i32; N]>? {
    pointer.as_array<N>()
}
const fn constant_array(): i32 {
    let values = [20i32, 22]
    let slice: read [i32] = read values
    let pointer = slice as ptr<read [i32]>
    match fixed<2usize>(pointer) {
        present(array) => unsafe { (*array)[0] + (*array)[1] },
        nil => 0
    }
}
const ARRAY_SUM: i32 = constant_array()
fn main() {
    let values = [20,22]
    let slice: read [i32] = read values
    let pointer = slice as ptr<read [i32]>
    let same = pointer.wrapping_byte_add(0usize).with_addr(pointer.addr())
    let borrowed: read [i32] = unsafe { read *same }
    let matched = match fixed<2usize>(pointer) {
        present(array) => unsafe { (*array)[0] + (*array)[1] == 42 },
        nil => false
    }
    let rejected = match fixed<3usize>(pointer) {
        present(_) => false,
        nil => true
    }
    var mutable_values = [20, 21]
    let mutable_slice: mut [i32] = mut mutable_values
    let mutable_pointer = mutable_slice as ptr<mut [i32]>
    match mutable_pointer.as_mut_array<2usize>() {
        present(array) => unsafe { (*array)[1] = 22 },
        nil => {}
    }
    if same == pointer && total(borrowed) == 42 &&
       matched && rejected && mutable_values[1] == 22 &&
       ARRAY_SUM == 42 { 0 } else { 1 }
}
