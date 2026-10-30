
@layout(C,u8)
copy enum Value { Empty = 7; Byte(u8) = 9; Wide(u64) = 42 }
fn main() {
    let bytes = unsafe { core.mem.transmute::<[u8;16]>(Value.Byte(42u8)) }
    let answer = match Value.Byte(42u8) {
        Value.Byte(value) => value as i32,
        _ => 0
    }
    if bytes[0] == 9u8 && bytes[8] == 42u8 && answer == 42 &&
       core.mem.align_of<Value>() == 8usize { 0 } else { 1 }
}
