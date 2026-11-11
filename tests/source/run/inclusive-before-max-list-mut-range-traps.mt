// expect-exit: trap
import alloc.vec.List

fn main(): i32 {
    var values = List<i32>()
    let end = !0usize - 1usize
    let selected: mut [i32] = mut values[..=end]
    selected.len() as i32
}
