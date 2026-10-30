pub module limits { pub const COUNT: usize = 3usize; pub const TAG: u8 = 9u8; }
interface Width { const BITS: i32; }
type Narrow {}
impl Narrow implements Width { const BITS: i32 = limits.TAG as i32 + 1 }
@layout(C,u8)
copy enum Value { Empty = limits.TAG; Byte(u8) = 42 }
fn main() {
    let row: [i32; limits.COUNT] = [1, 2, 3]
    let cells: [u8; limits.COUNT - 1usize] = [4u8, 5u8]
    let bytes = unsafe { core::mem::transmute::<[u8;2]>(Value::Byte(42u8)) }
    let empty = unsafe { core::mem::transmute::<[u8;2]>(Value::Empty) }
    if empty[0] == 9u8 && row[2] == 3 && cells[1] == 5u8 && <Narrow implements Width>::BITS == 10 &&
       bytes[0] == 42u8 { 0 } else { 1 }
}
