// expect-exit: 101
import core.slice.SliceIndex

fn main(): i32 {
    var bytes = [97u8, 195u8, 169u8]
    let text = core.text.from_utf8_mut(mut bytes).or_panic()
    core.range.RangeFrom(2usize).index_mut(mut text).len() as i32
}
