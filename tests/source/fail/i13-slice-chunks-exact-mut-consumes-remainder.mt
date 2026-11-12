// profiles: debug release
// expect-error: ownership 9:5 moved
import core.iter.Iterator
fn main(): i32 {
    var values = [1, 2, 3]
    let view: mut [i32] = mut values[..]
    var chunks = view.chunks_exact_mut(2usize)
    let remainder = take chunks.into_remainder()
    chunks.next()
    remainder[0usize]
}
