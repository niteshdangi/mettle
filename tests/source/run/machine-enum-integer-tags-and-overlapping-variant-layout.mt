
@layout(u8)
copy enum Byte { First = 64; Next; Last = 255 }
@layout(i128)
copy enum Wide { Minimum = -170141183460469231731687303715884105728i128; Next }
@layout(u8)
copy enum Payload { Empty = 7; Small(u8) = 9; Large(u64) = 42 }
fn main() {
    let bytes = unsafe { core.mem.transmute::<[u8;16]>(Payload.Small(42u8)) }
    let matched = match Byte.Last { Byte.First => 1, Byte.Next => 2, Byte.Last => 42 }
    if Byte.Next as u16 == 65u16 && matched == 42 &&
       Wide.Minimum as i128 == -170141183460469231731687303715884105728i128 &&
       Wide.Next as i128 == -170141183460469231731687303715884105727i128 &&
       bytes[0] == 9u8 && bytes[1] == 42u8 &&
       core.mem.size_of<Byte>() == 1usize &&
       core.mem.size_of<Payload>() == 16usize { 0 } else { 1 }
}
