// expect-error: ownership 7:5 moved
import core.iter.{Iterator, range}
fn main(): i32 {
    var source = range(0, 1)
    let count = source.count()
    assert(count == 1usize, "one item")
    source.next()
    0
}
