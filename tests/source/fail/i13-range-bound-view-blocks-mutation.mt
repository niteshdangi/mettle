// expect-error: ownership 9:5 access or storage lifetime conflicts
import core.iter
import core.iter.{Bound, RangeBounds}
fn main(): i32 {
    var range = iter.range(2, 5)
    let value = match take range.start_bound() {
        Bound.Included(start) => start, _ => { return 1 }
    }
    range.start = 3
    *value
}
