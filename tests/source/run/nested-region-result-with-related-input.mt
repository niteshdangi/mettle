import core.iter.Reversed
import core.iter.BidirectionalIterator
import core.iter.Iterator
import core.slice.SliceIter
fn f(read x: [i32], read y: [i32] from x): Reversed<SliceIter<region x, i32>> { x.iter().rev() }
fn main(): i32 {
    let a = [1, 2, 3]
    var r = f(read a, read a)
    match r.next() { present(v) => *v - 3, none => 9 }
}
