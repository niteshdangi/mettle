// expect-exit: trap
// flags: --overflow-checks off
import alloc.vec.List

fn main(): i32 {
    let values = List<i32>()
    let last = !0usize
    let selected: read [i32] = read values[..=last]
    if selected.len() == 0usize { 0 } else { 1 }
}
