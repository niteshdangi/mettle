// expect-error: type 8:13 SplitOffRange
// expect-error: type 9:13 SplitOffRange
import core.iter
import core.slice
fn main(): i32 {
    var values = [10, 20]
    var view: mut [i32] = mut values[..]
    let _ = slice.split_off_mut(mut view, iter.range(0usize, 1usize))
    let _ = slice.split_off_mut(mut view, iter.range_full())
    0
}
