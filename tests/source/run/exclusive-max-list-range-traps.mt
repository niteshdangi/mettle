// expect-exit: trap
import alloc.vec.List

fn main(): i32 {
    let values = List<i32>()
    let end = !0usize
    let selected: read [i32] = read values[..end]
    selected.len() as i32
}
