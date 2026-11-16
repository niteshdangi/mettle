import core.ops.{Deref, DerefMut}
import alloc.boxed

type Bytes<region r> { data: mut [u8] from r; projections: i32 }
extend<region r> Bytes<region r> implements Deref {
    type Target = [u8]
    fn deref(): read [u8] from self { read self.data }
}
extend<region r> Bytes<region r> implements DerefMut {
    mut fn deref_mut(): mut [u8] from self {
        self.projections += 1
        mut self.data
    }
}

fn main(): i32 {
    var data = [10u8, 20u8, 30u8]
    var bytes = Bytes(mut data[..], 0)
    if bytes.len() != 3usize || bytes[0] != 10u8 || bytes[1usize] != 20u8 { return 1 }
    bytes[1] = 42u8
    if bytes[1usize] != 42u8 || bytes.projections != 1 { return 2 }
    {
        let tail = mut bytes[1usize..]
        tail[1usize] = 43u8
    }
    if bytes[2] != 43u8 || bytes.projections != 2 { return 3 }
    let other = [7u8, 8u8]
    let owned_view = heap (read other[..])
    if owned_view.len() != 2usize || owned_view[1] != 8u8 { return 4 }
    0
}
