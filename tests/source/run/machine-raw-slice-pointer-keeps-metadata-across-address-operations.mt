
fn total(values: read [i32]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
fn main() {
    let values = [20,22]
    let slice: read [i32] = read values
    let pointer = slice as ptr<read [i32]>
    let same = pointer.wrapping_byte_add(0usize).with_addr(pointer.addr())
    let borrowed: read [i32] = unsafe { read *same }
    if same == pointer && total(borrowed) == 42 { 0 } else { 1 }
}
