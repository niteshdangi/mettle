import core.ops.Deref

extend [u8] { fn len(): usize { 99usize } }
type Bytes<region r> { data: read [u8] from r }
extend<region r> Bytes<region r> implements Deref {
    type Target = [u8]
    fn deref(): read [u8] from self { self.data }
}
fn main(): i32 {
    let data = [1u8, 2u8]
    let bytes = Bytes(read data[..])
    if bytes.len() == 99usize { 0 } else { 1 }
}
