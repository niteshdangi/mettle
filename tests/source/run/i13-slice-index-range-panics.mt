// expect-exit: 101
import core.slice.SliceIndex

fn main(): i32 {
    let values = [1i32, 2i32]
    core.range.Range(2usize, 1usize).index(read values).len() as i32
}
