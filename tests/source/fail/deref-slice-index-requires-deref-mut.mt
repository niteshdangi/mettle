// expect-error: ownership 11:5 selected mutable receiver requires matching DerefMut
import core.ops.Deref
type Bytes<region r> { data: read [u8] from r }
extend<region r> Bytes<region r> implements Deref {
    type Target = [u8]
    fn deref(): read [u8] from self { self.data }
}
fn main(): i32 {
    let data = [1u8, 2u8]
    var bytes = Bytes(read data[..])
    bytes[0usize] = 3u8
    0
}
